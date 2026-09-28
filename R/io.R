read_records <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  jsonlite::fromJSON(paste0("[", paste(lines, collapse = ","), "]"), simplifyVector = FALSE)
}

write_records <- function(records, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lines <- purrr::map_chr(records, jsonlite::toJSON, auto_unbox = TRUE, null = "null")
  writeLines(lines, path, useBytes = TRUE)
}

read_restaurants <- function(path) {
  records <- read_records(path)
  purrr::map_dfr(records, function(x) {
    tibble::tibble(
      place_id = x$place_id %||% NA_character_, name = x$name %||% NA_character_,
      source = x$source %||% NA_character_, region_id = x$region_id %||% NA_character_,
      lat = x$lat %||% NA_real_, lon = x$lon %||% NA_real_,
      cell_idx = x$cell_idx %||% NA_integer_,
      query_center_lat = x$query_center_lat %||% NA_real_,
      query_center_lon = x$query_center_lon %||% NA_real_,
      archived_normalized = x$name_normalized %||% NA_character_,
      archived_matches = list(x$matches %||% list())
    )
  })
}

`%||%` <- function(x, y) if (is.null(x)) y else x

read_table <- function(path) {
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

write_table <- function(x, name) {
  readr::write_csv(x, file.path("out/tab", paste0(name, ".csv")), na = "")
}

require_columns <- function(x, columns) {
  missing <- setdiff(columns, names(x))
  if (length(missing)) stop("Missing columns: ", paste(missing, collapse = ", "))
}

assert_unique <- function(x, columns) {
  require_columns(x, columns)
  if (anyNA(x[columns]) || anyDuplicated(x[columns])) {
    stop("Missing or duplicate key: ", paste(columns, collapse = ", "))
  }
  invisible(x)
}

read_verdicts <- function(path) {
  purrr::map_dfr(read_records(path), function(x) {
    tibble::tibble(
      item_id = x$item_id, task = x$task,
      genuine = x$verdict$genuine %||% NA,
      caste_coded = x$verdict$caste_coded %||% NA
    )
  }) |>
    dplyr::group_by(item_id) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup()
}
