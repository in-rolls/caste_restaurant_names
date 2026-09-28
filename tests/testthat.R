source("scripts/00_setup.R")
testthat::test_dir("tests/testthat", stop_on_failure = TRUE)
