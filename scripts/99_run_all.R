for (script in c("01_analyze.R", "02_figures.R", "03_report.R")) {
  message("Running ", script)
  source(file.path("scripts", script), local = new.env(parent = globalenv()))
}
