# test-logging.R
# Tests for pam_log() and pam_run_stage().

# ── pam_log ───────────────────────────────────────────────────────────────────

test_that("pam_log: writes log line to file", {
  log_dir <- withr::local_tempdir()
  suppressMessages(
    pam_log("INFO", "hello world", stage = "test", log_dir = log_dir, echo = FALSE)
  )
  log_file <- file.path(log_dir, "test.log")
  expect_true(file.exists(log_file))
  content <- readLines(log_file)
  expect_length(content, 1L)
  expect_match(content, "\\[INFO\\]")
  expect_match(content, "hello world")
  expect_match(content, "\\[test\\]")
})

test_that("pam_log: creates log_dir if it doesn't exist", {
  tmp <- tempfile()    # does not exist yet
  suppressMessages(
    pam_log("WARN", "dir test", stage = "s", log_dir = tmp, echo = FALSE)
  )
  expect_true(dir.exists(tmp))
  unlink(tmp, recursive = TRUE)
})

test_that("pam_log: skips file when log_dir is NULL", {
  # Should not error; returns invisibly
  expect_no_error(
    suppressMessages(pam_log("ERROR", "no file", log_dir = NULL, echo = FALSE))
  )
})

test_that("pam_log: returns the formatted line invisibly", {
  line <- suppressMessages(
    pam_log("INFO", "check return", log_dir = NULL, echo = FALSE)
  )
  expect_type(line, "character")
  expect_match(line, "check return")
})

test_that("pam_log: level arg is validated", {
  expect_error(
    pam_log("DEBUG", "bad level", log_dir = NULL, echo = FALSE)
  )
})

# ── pam_run_stage ─────────────────────────────────────────────────────────────

test_that("pam_run_stage: success path returns status=ok and result", {
  cfg <- list(paths = list(logs = withr::local_tempdir()))
  fn  <- function(cfg, ...) 42L

  out <- suppressMessages(pam_run_stage("test_ok", fn, cfg))

  expect_equal(out$status, "ok")
  expect_equal(out$result, 42L)
  expect_s3_class(out$duration, "difftime")
  expect_equal(length(out$warnings), 0L)
})

test_that("pam_run_stage: error path returns status=failed and NULL result", {
  cfg <- list(paths = list(logs = withr::local_tempdir()))
  fn  <- function(cfg, ...) stop("boom")

  out <- suppressMessages(pam_run_stage("test_fail", fn, cfg))

  expect_equal(out$status, "failed")
  expect_null(out$result)
  expect_s3_class(out$duration, "difftime")
})

test_that("pam_run_stage: warnings are captured and muffled", {
  cfg <- list(paths = list(logs = withr::local_tempdir()))
  fn  <- function(cfg, ...) {
    warning("w1")
    warning("w2")
    "done"
  }

  out <- suppressMessages(pam_run_stage("test_warns", fn, cfg))

  expect_equal(out$status, "ok")
  expect_equal(out$result, "done")
  expect_equal(length(out$warnings), 2L)
  expect_match(out$warnings[1], "w1")
  expect_match(out$warnings[2], "w2")
})

test_that("pam_run_stage: error is logged to file", {
  log_dir <- withr::local_tempdir()
  cfg <- list(paths = list(logs = log_dir))
  fn  <- function(cfg, ...) stop("fatal error text")

  suppressMessages(pam_run_stage("test_log", fn, cfg))

  log_file <- file.path(log_dir, "test_log.log")
  expect_true(file.exists(log_file))
  content <- paste(readLines(log_file), collapse = "\n")
  expect_match(content, "\\[ERROR\\]")
  expect_match(content, "fatal error text")
})

test_that("pam_run_stage: extra arguments are passed to fn", {
  cfg <- list(paths = list(logs = withr::local_tempdir()))
  fn  <- function(cfg, multiplier = 1) multiplier * 7L

  out <- suppressMessages(pam_run_stage("test_dots", fn, cfg, multiplier = 6L))

  expect_equal(out$result, 42L)
})
