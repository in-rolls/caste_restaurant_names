surname_candidates <- function(rows, lookup, threshold = 0.8, min_carriers = 10000) {
  require_columns(lookup, c("last_name", "p_sc", "p_st", "n"))
  names <- lookup |>
    dplyr::filter(p_sc + p_st >= threshold, n >= min_carriers) |>
    dplyr::transmute(term = normalize_name(last_name)) |>
    dplyr::filter(nchar(term) >= 4) |>
    dplyr::distinct()
  purrr::map_dfr(names$term, function(term) {
    rows |>
      dplyr::filter(stringr::str_detect(name_normalized, boundary_pattern(term))) |>
      dplyr::transmute(region_id, entity_id, name, term = term)
  })
}

historical_summary <- function(path) {
  data <- read_table(path)
  if (anyNA(data[c("year", "city", "name", "marker", "segment", "source_line")])) {
    stop("Historical coding or source-line reference missing")
  }
  data |>
    dplyr::mutate(
      identity = marker %in% c(
        "hindu_label", "vilas_bhavan", "caste_surname",
        "communal_label", "regional_place", "military_label", "caste_label"
      ),
      explicit_caste = marker %in% c("caste_surname", "caste_label")
    ) |>
    dplyr::group_by(year, city, segment) |>
    dplyr::summarise(
      n = dplyr::n(), identity = sum(identity), explicit_caste = sum(explicit_caste),
      p_identity = identity / n, p_explicit_caste = explicit_caste / n, .groups = "drop"
    )
}
