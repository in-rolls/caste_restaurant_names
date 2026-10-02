source("scripts/00_setup.R")
dictionary <- read_table("data/reference/dictionary.csv")
mapping <- read_table("data/reference/normalization.csv")
verdicts <- read_verdicts("data/adjudication_2026_08_30.jsonl")
exclusions <- read_table("data/match_exclusions.csv")
frozen_sample <- read_table("data/reference/screening_sample.csv")
raw_files <- sort(Sys.glob("data/restaurants_*_raw_collection.jsonl"))
if (length(raw_files) != 11L) {
  stop("Expected eight sampled districts and three grid cities")
}

results <- map(raw_files, function(path) {
  message("Analyzing ", basename(path))
  raw <- read_restaurants(path) |> normalize_restaurants(mapping)
  region <- unique(raw$region_id)
  stopifnot(length(region) == 1L)
  sampled <- grepl("2026_08_31", path, fixed = TRUE)
  rows <- link_sources(raw)
  hits <- match_names(rows, dictionary)
  classified <- classify_hits(rows, hits, verdicts, exclusions)
  outcomes <- entity_outcomes(rows, classified)
  export_matches(rows, hits, paste0("out/matches/analysis_region_", region, "_matches.jsonl"))
  archive_path <- paste0(
    "data/analysis_2026_08_31_", if (sampled) "s3" else "v2",
    "_region_", region, "_matches.jsonl"
  )
  archive <- read_restaurants(archive_path) |>
    mutate(
      entity_id = paste(region_id, source, place_id, sep = ":"),
      adjudication_name = archived_normalized
    )
  old_links <- purrr::map_dfr(read_records(archive_path), function(x) {
    tibble::tibble(place_id = x$place_id, old_osm = x$linked_osm_id %||% NA_character_)
  })
  linkage_changes <- rows |>
    select(place_id, name, new_osm = linked_osm_id) |>
    full_join(old_links, by = "place_id", relationship = "one-to-one") |>
    filter(coalesce(new_osm, "") != coalesce(old_osm, ""))
  old_hits <- archived_hits(archive)
  old_classified <- classify_hits(
    mutate(archive, name_normalized = archived_normalized), old_hits, verdicts, exclusions
  )
  old_outcomes <- entity_outcomes(archive, old_classified)
  if (any(old_classified$unresolved)) stop("Archived baseline lacks verdicts")
  baseline <- summarize_outcomes(old_outcomes)
  current <- summarize_outcomes(outcomes)
  comparison <- baseline |>
    select(group, old_n = n, old_confirmed = confirmed, old_p = p) |>
    full_join(select(current, group, new_n = n, new_confirmed = confirmed, new_p = p, unresolved),
      by = "group", relationship = "one-to-one"
    ) |>
    mutate(change_pp = 100 * (new_p - old_p))
  normalization <- rows |>
    filter(normalization_changed) |>
    select(region_id, entity_id, name, legacy_normalized, name_normalized)
  influence <- tibble()
  sample <- NULL
  diagnostics <- tibble(
    region_id = region, design = if (sampled) "sampled" else "grid",
    raw_n = nrow(raw), n = nrow(rows), linked = sum(!is.na(rows$linked_osm_id)),
    unscorable = sum(!stringr::str_detect(rows$name_normalized, "[a-z]")),
    changed_normalization = nrow(normalization), unresolved_pairs = sum(classified$unresolved)
  )
  if (sampled) {
    meta <- jsonlite::read_json(sub("_raw_collection.jsonl", "_meta.json", path, fixed = TRUE))
    sample <- read_table(meta$points_csv)
    validate_sample(rows, sample, meta)
    estimates <- cluster_estimates(outcomes, sample)
    point_counts <- outcomes |>
      filter(group == "any") |>
      group_by(cell_idx) |>
      summarise(n = n(), k = sum(confirmed), .groups = "drop")
    influence <- point_counts |> mutate(
      leave_one_out = (sum(k) - k) / (sum(n) - n),
      full = sum(k) / sum(n), change_pp = 100 * (leave_one_out - full)
    )
    old_r <- cluster_estimates(old_outcomes, sample, occupied_only = TRUE)
    all_r <- cluster_estimates(old_outcomes, sample)
    bootstrap_audit <- old_r |>
      select(group, estimator, occupied_ci_low = ci_low, occupied_ci_high = ci_high) |>
      left_join(select(all_r, group, estimator, all_ci_low = ci_low, all_ci_high = ci_high),
        by = c("group", "estimator"), relationship = "one-to-one"
      )
    archived_estimates <- read_table(paste0("data/sampled_estimates_v3_", region, ".csv"))
    parity <- archived_estimates |>
      select(group, archived_p = p_unweighted, archived_weighted = p_weighted, archived_n = n) |>
      left_join(select(old_r, group, estimator, p, n),
        by = "group", relationship = "one-to-many"
      ) |>
      mutate(
        expected = if_else(estimator == "unweighted", archived_p, archived_weighted),
        error = abs(p - expected)
      )
    if (any(parity$error > 0.00000051) || any(parity$n != parity$archived_n)) {
      stop("Baseline reproduction failed for ", region)
    }
    diagnostics <- diagnostics |>
      mutate(
        query_points = nrow(sample), occupied_points = n_distinct(rows$cell_idx),
        no_first_capture = query_points - occupied_points,
        capped_queries = meta$capped_queries, capped_share = capped_queries / query_points,
        query_radius_m = meta$radius_m
      )
    screening <- tibble()
  } else {
    estimates <- current |> mutate(estimator = "unweighted", ci_low = NA_real_, ci_high = NA_real_)
    bootstrap_audit <- tibble()
    parity <- baseline |>
      filter(group != "any") |>
      left_join(
        read_table("data/final_estimates_2026_08_31_v2.csv") |>
          filter(.data$region == .env$region) |>
          select(group, archived_p = p, archived_n = n),
        by = "group", relationship = "one-to-one"
      ) |>
      mutate(error = abs(p - archived_p))
    if (
      anyNA(parity$error) || any(parity$error > 0.00000051) ||
        any(parity$n != parity$archived_n)
    ) {
      stop("Grid baseline reproduction failed for ", region)
    }
    screening <- screening_estimates(
      rows, hits, verdicts,
      filter(frozen_sample, region_id == region)
    )
    old_screen <- screening_estimates(
      archive, old_hits, verdicts,
      filter(frozen_sample, region_id == region)
    )
    old_expected <- read_table("data/final_estimates_2026_08_31_v2.csv") |>
      filter(.data$region == .env$region, group == "fn_rate_sampled")
    if (old_screen$n != old_expected$n || old_screen$confirmed != old_expected$confirmed) {
      stop("Frozen screening-sample reproduction failed")
    }
  }
  validate_estimates(estimates)
  sensitivity <- bind_rows(
    summarize_outcomes(outcomes) |> mutate(specification = "adjudicated"),
    summarize_outcomes(entity_outcomes(rows, classified, exclude_own_city = TRUE)) |>
      mutate(specification = "exclude_own_city"),
    summarize_outcomes(entity_outcomes(rows, classified, regional_veto = FALSE)) |>
      mutate(specification = "dictionary_without_regional_veto")
  )
  list(
    rows = rows, estimates = estimates, comparison = comparison, parity = parity,
    normalization = normalization, diagnostics = diagnostics, bootstrap_audit = bootstrap_audit,
    linkage_changes = linkage_changes, influence = influence,
    screening = screening, sensitivity = sensitivity,
    review = classified |> filter(unresolved),
    match_changes = full_join(
      old_hits |> select(entity_id, label, term) |> mutate(old = TRUE),
      hits |> select(entity_id, label, term) |> mutate(new = TRUE),
      by = c("entity_id", "label", "term"), relationship = "one-to-one"
    ) |>
      filter(is.na(old) | is.na(new)), region = region
  )
})
for (name in c(
  "estimates", "comparison", "parity", "normalization", "diagnostics",
  "bootstrap_audit", "screening", "sensitivity", "review", "match_changes",
  "linkage_changes", "influence"
)) {
  combined <- map_dfr(results, function(x) mutate(x[[name]], region_id = x$region))
  write_table(combined, name)
}
all_rows <- map_dfr(results, "rows")
write_table(historical_summary("data/historical/eating_houses_1918_1928.csv"), "historical")
lookup_path <- Sys.getenv(
  "SURNAME_LOOKUP", "../caste-name-information/out/tab/per_name_secc_weighted.parquet"
)
if (!file.exists(lookup_path)) {
  stop("Set SURNAME_LOOKUP to the SECC surname Parquet file: ", lookup_path)
}
lookup <- arrow::read_parquet(lookup_path)
candidates <- surname_candidates(filter(all_rows, !region_id %in% c("blr", "maa", "mys")), lookup)
write_table(candidates, "surname_candidates")
write_table(
  filter(all_rows, !region_id %in% c("blr", "maa", "mys")) |>
    count(region_id, name = "n") |>
    left_join(candidates |> distinct(region_id, entity_id) |> count(region_id, name = "candidates"),
      by = "region_id", relationship = "one-to-one"
    ) |>
    mutate(candidates = replace_na(candidates, 0L), p = candidates / n),
  "surname_summary"
)
writeLines(capture.output(sessionInfo()), "out/session-info.txt")
inputs <- unique(c(
  raw_files, "data/reference/dictionary.csv", "data/reference/normalization.csv",
  "data/reference/screening_sample.csv", "data/adjudication_2026_08_30.jsonl",
  "data/match_exclusions.csv", "data/historical/eating_houses_1918_1928.csv", lookup_path,
  Sys.glob("data/sampling/*n400_seed42.csv"), Sys.glob("data/restaurants_2026*_meta.json")
))
write_table(tibble(path = inputs, md5 = unname(tools::md5sum(inputs))), "input_manifest")
