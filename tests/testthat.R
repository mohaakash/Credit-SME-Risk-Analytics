# Master test runner for the Consumer Credit Risk Analytics project

library(testthat)

testthat::test_dir("tests/testthat", reporter = "progress")
