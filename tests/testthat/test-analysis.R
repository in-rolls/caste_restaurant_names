testthat::test_that("normalization handles Indic scripts, case and accents", {
  testthat::expect_equal(
    normalize_name(c(" IYÉR  Mess ", "ब्राह्मण", "தமிழ்")),
    c("iyer mess", "brahmana", "tamil")
  )
  testthat::expect_true(is.na(normalize_name(NA_character_)))
})

testthat::test_that("dictionary boundaries prevent short-token false matches", {
  rows <- tibble::tibble(
    entity_id = letters[1:5],
    name_normalized = c("brahmin's cafe", "saipai", "pai hotel", "udupis udupi", "udupix")
  )
  dictionary <- read_table(testthat::test_path("../../data/reference/dictionary.csv"))
  hits <- match_names(rows, dictionary)
  testthat::expect_setequal(unique(hits$entity_id), c("a", "c", "d"))
  testthat::expect_equal(sum(hits$entity_id == "d" & hits$term == "udupi"), 1L)
})

testthat::test_that("linkage collapses nearby duplicates but retains distant branches", {
  rows <- tibble::tibble(
    region_id = "test", source = c("places", "osm", "osm"), place_id = c("p", "o1", "o2"),
    name = "Iyer Mess", name_normalized = "iyer mess", lat = c(12, 12.0001, 13), lon = 77
  )
  linked <- link_sources(rows)
  testthat::expect_equal(nrow(linked), 2L)
  testthat::expect_equal(linked$linked_osm_id[1], "o1")
  rows$lat[2] <- NA_real_
  testthat::expect_equal(nrow(link_sources(rows)), 3L)
})

testthat::test_that("missing verdicts remain unresolved and exclusions override verdicts", {
  rows <- tibble::tibble(
    entity_id = c("a", "b", "c"), name = c("A", "B", "C"),
    name_normalized = c("a", "b", "c"), adjudication_name = c("a", "b", "c"), cell_idx = 0:2
  )
  hits <- tibble::tibble(
    entity_id = c("a", "b", "c"), label = "label", term = "term",
    variant = "term", group = c("regional", "surname_title", "regional")
  )
  verdicts <- tibble::tibble(item_id = c("A:a:label", "A:b:label"), genuine = FALSE)
  exclusions <- tibble::tibble(name_normalized = "b", term = "term")
  classified <- classify_hits(rows, hits, verdicts, exclusions)
  testthat::expect_equal(classified$confirmed, rep(FALSE, 3))
  testthat::expect_equal(classified$unresolved, c(FALSE, FALSE, TRUE))
  classified <- classify_hits(rows, hits, verdicts, exclusions[0, ])
  testthat::expect_true(classified$confirmed[2])
  outcomes <- summarize_outcomes(entity_outcomes(rows, classified))
  any <- dplyr::filter(outcomes, group == "any")
  testthat::expect_equal(any$p, 1 / 3)
  testthat::expect_equal(any$identification_upper, 2 / 3)
})

testthat::test_that("cluster estimates include points without first captures and correct weights", {
  rows <- tibble::tibble(entity_id = letters[1:3], cell_idx = c(0L, 0L, 1L))
  outcomes <- tidyr::crossing(entity_id = rows$entity_id, group = branding_groups) |>
    dplyr::left_join(rows, by = "entity_id") |>
    dplyr::mutate(confirmed = entity_id == "c", unresolved = FALSE)
  sample <- tibble::tibble(frame_segments_within_radius = c(1, 2, 1))
  result <- cluster_estimates(outcomes, sample, draws = 500)
  testthat::expect_true(all(result$n_points == 3))
  testthat::expect_equal(unique(result$p[result$estimator == "unweighted"]), 1 / 3)
  testthat::expect_equal(unique(result$p[result$estimator == "density_sensitivity"]), 0.2)
  testthat::expect_equal(result, cluster_estimates(outcomes, sample, draws = 500))
  testthat::expect_true(all(result$failed_draws > 0))
  outcomes$cell_idx[1] <- 8L
  testthat::expect_error(cluster_estimates(outcomes, sample), "assignment")
})

testthat::test_that("zero successes do not produce a spurious zero-width bootstrap interval", {
  outcomes <- tidyr::crossing(entity_id = letters[1:2], group = branding_groups) |>
    dplyr::mutate(
      cell_idx = as.integer(factor(entity_id)) - 1L, confirmed = FALSE, unresolved = FALSE
    )
  result <- cluster_estimates(outcomes, tibble::tibble(frame_segments_within_radius = c(1, 1)), 100)
  testthat::expect_true(all(result$p == 0))
  testthat::expect_true(all(is.na(result$ci_high)))
  testthat::expect_equal(wilson_interval(0, 0), c(NA_real_, NA_real_))
  testthat::expect_equal(wilson_interval(5, 10), c(0.2365896, 0.7634104), tolerance = 1e-7)
})

testthat::test_that("surname counts keep restaurants distinct across matched terms", {
  rows <- tibble::tibble(
    region_id = "test", entity_id = "a", name = "Meena Tamang Cafe",
    name_normalized = normalize_name(name)
  )
  lookup <- tibble::tibble(last_name = c("meena", "tamang"), p_sc = 0, p_st = 0.9, n = 20000)
  hits <- surname_candidates(rows, lookup)
  testthat::expect_equal(nrow(hits), 2L)
  testthat::expect_equal(dplyr::n_distinct(hits$entity_id), 1L)
})

testthat::test_that("missing screen verdicts are not measured negatives", {
  rows <- tibble::tibble(entity_id = "a", adjudication_name = "cafe")
  hits <- tibble::tibble(entity_id = character())
  verdicts <- tibble::tibble(item_id = character(), caste_coded = logical(), genuine = logical())
  frozen <- tibble::tibble(legacy_normalized = "cafe")
  result <- screening_estimates(rows, hits, verdicts, frozen)
  testthat::expect_equal(result$unresolved, 1)
  testthat::expect_true(is.na(result$ci_high))
})

testthat::test_that("sample validation rejects incomplete collection and wrong point order", {
  rows <- tibble::tibble(cell_idx = 0L, query_center_lat = 12, query_center_lon = 77)
  sample <- tibble::tibble(
    segment_id = 1:2, mid_lat = c(12, 13), mid_long = c(77, 78),
    frame_segments_within_radius = c(1, 2)
  )
  meta <- list(errors = list(), cells_covered = 2, queries_attempted = 2, requests_made = 2)
  testthat::expect_true(validate_sample(rows, sample, meta))
  testthat::expect_error(validate_sample(rows, sample[2:1, ], meta), "coordinates")
  meta$errors <- list("network error")
  testthat::expect_error(validate_sample(rows, sample, meta), "Incomplete")
})

testthat::test_that("bootstrap recovers a planted Bernoulli share in repeated samples", {
  covered <- withr::with_seed(104, vapply(seq_len(30), function(i) {
    y <- stats::rbinom(100, 1, 0.3)
    outcomes <- tidyr::crossing(entity_id = as.character(seq_len(100)), group = branding_groups) |>
      dplyr::mutate(
        cell_idx = as.integer(entity_id) - 1L,
        confirmed = as.logical(y[cell_idx + 1L]), unresolved = FALSE
      )
    result <- cluster_estimates(outcomes,
      tibble::tibble(frame_segments_within_radius = rep(1, 100)),
      draws = 300, seed = i
    ) |>
      dplyr::filter(group == "any", estimator == "unweighted")
    testthat::expect_equal(result$p, mean(y))
    result$ci_low <= 0.3 && result$ci_high >= 0.3
  }, logical(1)))
  testthat::expect_gte(mean(covered), 0.8)
})
