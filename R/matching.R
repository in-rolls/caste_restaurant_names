normalize_name <- function(x) {
  x |>
    stringi::stri_trans_general("Any-Latin; NFKC; NFD; [:Nonspacing Mark:] Remove; NFC") |>
    stringr::str_to_lower(locale = "en") |>
    stringr::str_squish()
}

boundary_pattern <- function(x) {
  paste0("(?<![a-z0-9])", stringr::str_escape(x), "(?![a-z0-9])")
}

normalize_restaurants <- function(rows, mapping) {
  assert_unique(mapping, "name")
  rows |>
    dplyr::mutate(name_normalized = normalize_name(name)) |>
    dplyr::left_join(mapping, by = "name", relationship = "many-to-one") |>
    dplyr::mutate(
      adjudication_name = dplyr::coalesce(legacy_normalized, name_normalized),
      normalization_changed = !is.na(legacy_normalized) & legacy_normalized != name_normalized
    )
}

match_names <- function(rows, dictionary) {
  assert_unique(rows, "entity_id")
  purrr::map_dfr(seq_len(nrow(dictionary)), function(i) {
    hit <- which(stringr::str_detect(rows$name_normalized, boundary_pattern(dictionary$variant[i])))
    tibble::tibble(
      entity_id = rows$entity_id[hit], term = dictionary$term[i],
      variant = dictionary$variant[i], label = dictionary$label[i], group = dictionary$group[i]
    )
  }) |>
    dplyr::distinct(entity_id, label, term, .keep_all = TRUE)
}

haversine_m <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  2 * 6371000 * asin(sqrt(pmin(1, a)))
}

link_sources <- function(rows, max_dist_m = 200, min_jaccard = 0.5) {
  if (
    anyNA(rows[c("source", "place_id", "name")]) ||
      any(!rows$source %in% c("places", "osm"))
  ) {
    stop("Invalid restaurant identity/source")
  }
  rows <- rows |> dplyr::distinct(source, place_id, .keep_all = TRUE)
  places <- rows |> dplyr::filter(source == "places")
  osm <- rows |> dplyr::filter(source == "osm")
  places$linked_osm_id <- NA_character_
  osm$linked_osm_id <- NA_character_
  tokens <- stringr::str_extract_all(places$name_normalized, "[a-z0-9]+")
  retained <- rep(TRUE, nrow(osm))
  for (i in seq_len(nrow(osm))) {
    candidates <- which(
      is.na(places$linked_osm_id) &
        haversine_m(osm$lat[i], osm$lon[i], places$lat, places$lon) <= max_dist_m
    )
    target <- unique(stringr::str_extract_all(osm$name_normalized[i], "[a-z0-9]+")[[1]])
    if (!length(candidates) || !length(target)) next
    scores <- purrr::map_dbl(tokens[candidates], function(x) {
      length(intersect(target, x)) / length(union(target, x))
    })
    best <- which.max(scores)
    if (scores[best] < min_jaccard) next
    places$linked_osm_id[candidates[best]] <- osm$place_id[i]
    retained[i] <- FALSE
  }
  dplyr::bind_rows(places, osm[retained, ]) |>
    dplyr::mutate(entity_id = paste(region_id, source, place_id, sep = ":"))
}

archived_hits <- function(rows) {
  purrr::map2_dfr(rows$entity_id, rows$archived_matches, function(id, matches) {
    if (!length(matches)) {
      return(tibble::tibble())
    }
    purrr::map_dfr(matches, function(x) {
      tibble::tibble(
        entity_id = id, term = x$term, variant = x$variant, label = x$label, group = x$group
      )
    })
  })
}

classify_hits <- function(rows, hits, verdicts, exclusions) {
  assert_unique(verdicts, "item_id")
  assert_unique(exclusions, c("name_normalized", "term"))
  hits |>
    dplyr::left_join(
      dplyr::select(rows, entity_id, name, name_normalized, adjudication_name),
      by = "entity_id", relationship = "many-to-one"
    ) |>
    dplyr::mutate(item_id = paste0("A:", adjudication_name, ":", label)) |>
    dplyr::left_join(
      dplyr::select(verdicts, item_id, genuine),
      by = "item_id", relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      dplyr::transmute(exclusions, adjudication_name = name_normalized, term, excluded = TRUE),
      by = c("adjudication_name", "term"), relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      excluded = dplyr::coalesce(excluded, FALSE),
      unresolved = !excluded & is.na(genuine),
      confirmed = !excluded & !unresolved & (group != "regional" | genuine)
    )
}

export_matches <- function(rows, hits, path) {
  hit_list <- split(dplyr::select(hits, term, variant, label, group), hits$entity_id)
  records <- purrr::map(seq_len(nrow(rows)), function(i) {
    x <- as.list(dplyr::select(rows[i, ], place_id, name, source, region_id, lat, lon, cell_idx))
    x$name_normalized <- rows$adjudication_name[i]
    h <- hit_list[[rows$entity_id[i]]]
    x$matches <- if (is.null(h)) list() else purrr::map(seq_len(nrow(h)), ~ as.list(h[.x, ]))
    x
  })
  write_records(records, path)
}
