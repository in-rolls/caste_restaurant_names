branding_groups <- c("any", "regional", "surname_title", "merchant_community", "upper_caste")

entity_outcomes <- function(rows, hits, exclude_own_city = FALSE, regional_veto = TRUE) {
  if (exclude_own_city) {
    hits <- hits |>
      dplyr::filter(!(
        term == "mysore" & entity_id %in% rows$entity_id[rows$region_id %in% c("mys", "mys2")]
      ))
  }
  if (!regional_veto) hits$confirmed <- !hits$excluded & !hits$unresolved
  grouped <- hits |>
    dplyr::group_by(entity_id, group) |>
    dplyr::summarise(confirmed = any(confirmed), unresolved = any(unresolved), .groups = "drop")
  any_group <- grouped |>
    dplyr::group_by(entity_id) |>
    dplyr::summarise(confirmed = any(confirmed), unresolved = any(unresolved), .groups = "drop") |>
    dplyr::mutate(group = "any")
  tidyr::crossing(entity_id = rows$entity_id, group = branding_groups) |>
    dplyr::left_join(dplyr::bind_rows(grouped, any_group),
      by = c("entity_id", "group"), relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      confirmed = dplyr::coalesce(confirmed, FALSE),
      unresolved = dplyr::coalesce(unresolved, FALSE) & !confirmed
    ) |>
    dplyr::left_join(dplyr::select(rows, entity_id, cell_idx),
      by = "entity_id", relationship = "many-to-one"
    )
}

wilson_interval <- function(k, n) {
  if (n <= 0) {
    return(c(NA_real_, NA_real_))
  }
  if (k < 0 || k > n) stop("Invalid binomial count")
  z <- 1.96
  p <- k / n
  denominator <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / denominator
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denominator
  c(max(0, center - half), min(1, center + half))
}

summarize_outcomes <- function(outcomes) {
  outcomes |>
    dplyr::group_by(group) |>
    dplyr::summarise(
      n = dplyr::n(), confirmed = sum(confirmed), unresolved = sum(unresolved),
      p = confirmed / n, identification_upper = (confirmed + unresolved) / n,
      .groups = "drop"
    )
}

validate_sample <- function(rows, sample, meta) {
  assert_unique(sample, "segment_id")
  if (
    length(meta$errors) || meta$cells_covered != nrow(sample) ||
      meta$queries_attempted != nrow(sample) || meta$requests_made != nrow(sample)
  ) {
    stop("Incomplete or non-single-language query coverage")
  }
  if (anyNA(rows$cell_idx) || any(!rows$cell_idx %in% (seq_len(nrow(sample)) - 1L))) {
    stop("Invalid query-point assignment")
  }
  expected <- sample[rows$cell_idx + 1L, ]
  if (
    anyNA(rows[c("query_center_lat", "query_center_lon")]) ||
      any(abs(rows$query_center_lat - expected$mid_lat) > 1e-7) ||
      any(abs(rows$query_center_lon - expected$mid_long) > 1e-7)
  ) {
    stop("Query-point coordinates disagree with sample order")
  }
  if (anyNA(sample$frame_segments_within_radius) || any(sample$frame_segments_within_radius < 1)) {
    stop("Missing or invalid local density")
  }
  invisible(TRUE)
}

cluster_estimates <- function(outcomes, sample, draws = 2000L, seed = 7L, occupied_only = FALSE) {
  if (draws < 2L || nrow(sample) < 2L) {
    stop("At least two draws and query points required")
  }
  sample <- sample |> dplyr::mutate(cell_idx = dplyr::row_number() - 1L)
  if (anyNA(outcomes$cell_idx) || any(!outcomes$cell_idx %in% sample$cell_idx)) {
    stop("Invalid query-point assignment")
  }
  if (anyNA(sample$frame_segments_within_radius) || any(sample$frame_segments_within_radius < 1)) {
    stop("Missing or invalid local density")
  }
  clusters <- outcomes |>
    dplyr::group_by(cell_idx, group) |>
    dplyr::summarise(n = dplyr::n(), k = sum(confirmed), u = sum(unresolved), .groups = "drop")
  points <- sample$cell_idx
  if (occupied_only) points <- intersect(points, outcomes$cell_idx)
  if (length(points) < 2) stop("Fewer than two supported query points")
  clusters <- tidyr::crossing(cell_idx = points, group = branding_groups) |>
    dplyr::left_join(clusters, by = c("cell_idx", "group"), relationship = "one-to-one") |>
    dplyr::mutate(dplyr::across(c(n, k, u), ~ tidyr::replace_na(.x, 0L))) |>
    dplyr::left_join(dplyr::select(sample, cell_idx, frame_segments_within_radius),
      by = "cell_idx", relationship = "many-to-one"
    ) |>
    dplyr::arrange(group, cell_idx)
  weights <- withr::with_seed(seed, replicate(draws, tabulate(
    sample.int(length(points), length(points), replace = TRUE),
    nbins = length(points)
  )))
  purrr::map_dfr(branding_groups, function(g) {
    d <- dplyr::filter(clusters, group == g)
    purrr::map_dfr(c("unweighted", "density_sensitivity"), function(estimator) {
      w <- if (estimator == "unweighted") rep(1, nrow(d)) else 1 / d$frame_segments_within_radius
      denominator <- as.vector(crossprod(d$n * w, weights))
      boots <- as.vector(crossprod(d$k * w, weights)) / denominator
      supported <- is.finite(boots)
      p <- sum(d$k * w) / sum(d$n * w)
      ci <- if (sum(supported) >= 0.95 * draws && sum(d$n > 0) >= 2 && sum(d$k) > 0) {
        stats::quantile(boots[supported], c(0.025, 0.975), type = 7, names = FALSE)
      } else {
        c(NA_real_, NA_real_)
      }
      tibble::tibble(
        group = g, estimator = estimator, n = sum(d$n), n_points = length(points),
        occupied_points = sum(d$n > 0), confirmed = sum(d$k), unresolved = sum(d$u),
        p = p, identification_upper = sum((d$k + d$u) * w) / sum(d$n * w),
        ci_low = ci[1], ci_high = ci[2], failed_draws = sum(!supported), draws = draws, seed = seed
      )
    })
  })
}

screening_estimates <- function(rows, hits, verdicts, frozen_sample) {
  unmatched <- rows |> dplyr::anti_join(hits, by = "entity_id")
  sample <- frozen_sample |>
    dplyr::semi_join(unmatched, by = c("legacy_normalized" = "adjudication_name")) |>
    dplyr::mutate(item_id = paste0("B:", legacy_normalized)) |>
    dplyr::left_join(dplyr::select(verdicts, item_id, caste_coded),
      by = "item_id", relationship = "many-to-one"
    ) |>
    dplyr::mutate(item_id = paste0("C:", legacy_normalized)) |>
    dplyr::left_join(dplyr::select(verdicts, item_id, genuine),
      by = "item_id", relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      missing = is.na(caste_coded) | (caste_coded & is.na(genuine)),
      hit = !missing & caste_coded & dplyr::coalesce(genuine, FALSE)
    )
  n <- nrow(sample)
  k <- sum(sample$hit)
  ci <- wilson_interval(k, n)
  tibble::tibble(
    n = n, confirmed = k, unresolved = sum(sample$missing), p = if (n) k / n else NA_real_,
    ci_low = if (any(sample$missing)) NA_real_ else ci[1],
    ci_high = if (any(sample$missing)) NA_real_ else ci[2], n_unmatched = nrow(unmatched)
  )
}

validate_estimates <- function(estimates) {
  if (
    anyNA(estimates[c("n", "confirmed", "unresolved", "p", "identification_upper")]) ||
      any(estimates$n <= 0) || any(estimates$confirmed < 0) || any(estimates$unresolved < 0) ||
      any(estimates$confirmed + estimates$unresolved > estimates$n) ||
      any(estimates$p < 0 | estimates$p > estimates$identification_upper) ||
      any(estimates$identification_upper > 1)
  ) {
    stop("Invalid estimate or denominator")
  }
  observed <- !is.na(estimates$ci_low) & !is.na(estimates$ci_high)
  if (
    any(is.na(estimates$ci_low) != is.na(estimates$ci_high)) ||
      any(estimates$ci_low[observed] < 0 | estimates$ci_high[observed] > 1) ||
      any(estimates$ci_low[observed] > estimates$ci_high[observed])
  ) {
    stop("Invalid confidence interval")
  }
  invisible(TRUE)
}
