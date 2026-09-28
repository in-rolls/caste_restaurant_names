source("scripts/00_setup.R")
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: Rscript scripts/match_collection.R raw_collection.jsonl output_basepath")
}
rows <- read_restaurants(args[1]) |>
  normalize_restaurants(read_table("data/reference/normalization.csv"))
dictionary <- read_table("data/reference/dictionary.csv")
for (region in sort(unique(rows$region_id))) {
  entities <- rows |>
    filter(region_id == region) |>
    link_sources()
  hits <- match_names(entities, dictionary)
  export_matches(entities, hits, paste0(args[2], "_region_", region, "_matches.jsonl"))
}
