# CRAN policy: no function writes to the working directory or home filespace by
# default, and nothing is assigned outside a function's own environment.

test_that("pam_config_read() needs an explicit, existing path", {
  expect_error(pam_config_read(), "path")
  expect_error(pam_load_config(), "path")
  expect_error(pam_config_read(NULL), "path")
  expect_error(pam_config_read(file.path(tempdir(), "no_such_config.yml")), "not found")
})

test_that("a relative project_root is resolved against the config file's folder", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "config"))
  cfg_file <- file.path(root, "config", "config.yml")
  writeLines(c("paths:", "  project_root: \"..\""), cfg_file)
  withr::local_dir(tempdir())   # the working directory must not matter
  cfg <- pam_config_read(cfg_file)
  expect_equal(normalizePath(cfg$paths$project_root, winslash = "/"),
               normalizePath(root, winslash = "/"))
  expect_true(startsWith(cfg$paths$detections, cfg$paths$project_root))
})

test_that("the template's default project_root is the folder above config/", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "config"))
  cfg_file <- file.path(root, "config", "config.yml")
  file.copy(system.file("extdata", "config_template.yml", package = "pamflow"), cfg_file)
  cfg <- pam_config_read(cfg_file)
  expect_equal(normalizePath(cfg$paths$project_root, winslash = "/"),
               normalizePath(root, winslash = "/"))
})

test_that("pam_standardize() has no default output folders", {
  raw <- withr::local_tempdir()
  expect_error(suppressMessages(pam_standardize()), "raw_dir")
  expect_error(suppressMessages(pam_standardize(raw_dir = raw)), "output folders")
  expect_error(suppressMessages(pam_standardize(raw_dir = raw, standardized_dir = raw)),
               "output folders")
  # a dry run writes nothing, so it needs no output folders
  expect_no_error(suppressMessages(pam_standardize(raw_dir = raw, dry_run = TRUE)))
})

test_that("soundscape outputs need a project_root (no '.' fallback)", {
  expect_error(pam_soundscape_out_dir(list()), "project_root")
  skip_if_not_installed("rmarkdown")
  expect_error(suppressMessages(pam_soundscape_report(list(paths = list(logs = tempdir())))),
               "project_root")
})

test_that("the package code has no `<<-` and no assignment into globalenv()", {
  r_dir <- testthat::test_path("..", "..", "R")
  skip_if_not(dir.exists(r_dir), "package sources not available")
  code <- unlist(lapply(list.files(r_dir, pattern = "[.]R$", full.names = TRUE), readLines, warn = FALSE))
  code <- sub("#.*$", "", code)
  expect_false(any(grepl("<<-", code, fixed = TRUE)))
  expect_false(any(grepl("globalenv()", code, fixed = TRUE)))
  expect_false(any(grepl("set.seed(", code, fixed = TRUE)))
})
