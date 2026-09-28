suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(ggplot2)
})
if (!file.exists("data/reference/dictionary.csv")) stop("Run from the repository root")
for (file in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(file)
for (directory in c("out/tab", "out/fig", "out/matches")) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
}
