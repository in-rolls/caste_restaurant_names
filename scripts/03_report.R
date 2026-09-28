if (!file.exists("out/tab/estimates.csv")) stop("Run make analysis first")
rmarkdown::render("README.Rmd", quiet = TRUE, envir = new.env(parent = globalenv()))
rmarkdown::render("docs/methods.Rmd",
  quiet = TRUE, knit_root_dir = getwd(),
  envir = new.env(parent = globalenv())
)
