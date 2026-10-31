test_that("pam_as_count_history checks and labels the counts", {
  y <- matrix(c(0, 2, 5, 1, 0, 3), nrow = 3, dimnames = list(c("a", "b", "c"), NULL))
  h <- pam_as_count_history(y, species = "Sp one")
  expect_s3_class(h, "pam_count_history")
  expect_equal(rownames(h$y), c("a", "b", "c"))
  expect_equal(colnames(h$y), c("1", "2"))
  expect_true(is.integer(h$y))
  expect_equal(h$day[1, ], c(`1` = 0, `2` = 1))
  expect_null(h$effort)
  expect_equal(h$site_covariates$site_id, c("a", "b", "c"))
  expect_equal(h$species, "Sp one")
  # sites are named when the matrix has no row names
  expect_equal(rownames(pam_as_count_history(unname(y))$y), c("site1", "site2", "site3"))
  expect_error(pam_as_count_history(y[0, , drop = FALSE]), "at least one site")
  expect_error(pam_as_count_history(data.frame(a = 1)), "numeric matrix")
  expect_error(pam_as_count_history(y - 1), "whole numbers of 0 or more")
  expect_error(pam_as_count_history(y + 0.5), "whole numbers")
  dup <- y; rownames(dup) <- c("a", "a", "b")
  expect_error(pam_as_count_history(dup), "unique")
  expect_error(pam_as_count_history(y, effort = matrix(1, 2, 2)), "same shape")
  expect_error(pam_as_count_history(y, effort = y * 0 - 1), "negative")
  expect_error(pam_as_count_history(y, occasions = data.frame(occasion = 1)), "one row per column")
  ok <- pam_as_count_history(y, effort = matrix(24, 3, 2), day = matrix(c(0, 0, 0, 7, 7, 7), 3))
  expect_equal(unname(ok$effort[1, ]), c(24, 24))
  expect_equal(unname(ok$day[1, ]), c(0, 7))
})

test_that("site covariates are matched to the sites by name or by position", {
  match_sites <- pamflow:::pam_match_site_covariates
  sites <- c("s1", "s2", "s3")
  expect_equal(match_sites(sites, NULL), data.frame(site_id = sites))
  by_name <- match_sites(sites, data.frame(elev = c(3, 1, 2), site_id = c("s3", "s1", "s2")))
  expect_equal(by_name$site_id, sites)
  expect_equal(by_name$elev, c(1, 2, 3))
  expect_equal(names(by_name), c("site_id", "elev"))
  by_position <- match_sites(sites, data.frame(elev = c(10, 20, 30)))
  expect_equal(by_position$site_id, sites)
  expect_equal(by_position$elev, c(10, 20, 30))
  extra <- match_sites(sites, data.frame(site_id = c(sites, "s4"), elev = 1:4))
  expect_equal(nrow(extra), 3L)
  expect_error(match_sites(sites, data.frame(site_id = c("s1", "s2"), elev = 1:2)), "no row for 1 site")
  expect_error(match_sites(sites, data.frame(site_id = c("s1", "s1", "s2", "s3"), elev = 1:4)), "more than once")
  expect_error(match_sites(sites, data.frame(elev = 1:2)), "one row per site")
  expect_error(match_sites(sites, "x"), "data frame")
})

make_count_example <- function(env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  list(ex = ex, proc = proc, species = unique(proc$clean$scientific_name)[1])
}

test_that("the count history of the example project has the documented shape", {
  r <- make_count_example()
  h <- suppressMessages(pam_count_history(r$ex$cfg, species = r$species))
  expect_s3_class(h, "pam_count_history")
  expect_equal(dim(h$y), c(2L, 2L))
  expect_equal(rownames(h$y), c("G0059", "G0110"))
  expect_equal(colnames(h$y), c("2026-04-05", "2026-04-06"))
  # each site was recorded on one day only
  expect_true(is.na(h$y["G0059", "2026-04-06"]) && is.na(h$y["G0110", "2026-04-05"]))
  expect_equal(sum(h$y, na.rm = TRUE), sum(r$proc$clean$scientific_name == r$species))
  expect_identical(is.na(h$effort), is.na(h$y))
  expect_true(all(abs(h$effort[!is.na(h$effort)] - 6 / 3600) < 1e-9))
  expect_equal(unname(h$day[1, ]), c(0L, 1L))
  expect_equal(h$occasions$bin_start, as.Date(c("2026-04-05", "2026-04-06")))
  expect_equal(h$count, "events")
  expect_match(h$species, r$species, fixed = TRUE)
})

test_that("counting recordings never gives more than counting events", {
  r <- make_count_example()
  events <- suppressMessages(pam_count_history(r$ex$cfg, species = r$species))
  files <- suppressMessages(pam_count_history(r$ex$cfg, species = r$species, count = "files"))
  expect_true(all(files$y <= events$y, na.rm = TRUE))
  expect_equal(files$count, "files")
  expect_identical(is.na(files$y), is.na(events$y))
})

test_that("longer occasions, thresholds and minimum effort change the history as documented", {
  r <- make_count_example()
  one <- suppressMessages(pam_count_history(r$ex$cfg, species = r$species))
  two <- suppressMessages(pam_count_history(r$ex$cfg, species = r$species, bin_days = 2))
  expect_equal(dim(two$y), c(2L, 1L))
  expect_false(anyNA(two$y))
  expect_equal(sum(two$y), sum(one$y, na.rm = TRUE))
  thr <- data.frame(scientific_name = r$species, threshold = 1)
  expected <- sum(r$proc$clean$scientific_name == r$species & r$proc$clean$confidence >= 1)
  run_strict <- function() {
    suppressMessages(pam_count_history(r$ex$cfg, species = r$species, thresholds = thr))
  }
  # a history with no counts at all is allowed, but it warns
  if (expected == 0) {
    expect_warning(strict <- run_strict(), "counts in any surveyed occasion")
  } else {
    strict <- run_strict()
  }
  expect_equal(sum(strict$y, na.rm = TRUE), expected)
  short <- suppressWarnings(suppressMessages(
    pam_count_history(r$ex$cfg, species = r$species, min_effort_hours = 1)))
  expect_true(all(is.na(short$y)))
})

test_that("site covariates are attached in the order of the history", {
  r <- make_count_example()
  cov <- data.frame(site_id = c("G0110", "G0059"), elev = c(110, 59))
  h <- suppressMessages(pam_count_history(r$ex$cfg, species = r$species, site_covariates = cov))
  expect_equal(h$site_covariates$site_id, c("G0059", "G0110"))
  expect_equal(h$site_covariates$elev, c(59, 110))
  expect_error(suppressMessages(pam_count_history(
    r$ex$cfg, species = r$species, site_covariates = data.frame(site_id = "G0059", elev = 1))),
    "no row for 1 site")
})

test_that("pam_count_history needs exactly one known species", {
  r <- make_count_example()
  expect_error(pam_count_history(r$ex$cfg), "single species name")
  expect_error(pam_count_history(r$ex$cfg, species = c("a", "b")), "single species name")
  expect_error(pam_count_history(r$ex$cfg, species = NA_character_), "single species name")
  expect_error(suppressMessages(pam_count_history(r$ex$cfg, species = "no such species")),
               "No detections of")
  expect_error(pam_count_history(r$ex$cfg, species = r$species, count = "x"), "should be one of")
  expect_error(pam_count_history(r$ex$cfg, species = r$species, bin_days = 0), "bin_days")
})
