occasion_matrix <- function(history) {
  as.matrix(history[, setdiff(names(history), "site_id"), with = FALSE])
}

build_example_occupancy <- function(days, env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  suppressMessages(pam_process_detections(ex$cfg))
  if (!is.null(days)) ex$cfg$occupancy$occasion_length_days <- days
  list(ex = ex, occ = suppressMessages(pam_build_occupancy(ex$cfg, force = TRUE)))
}

test_that("one-day occasions (the default) give one column per recording day", {
  r <- build_example_occupancy(NULL)
  h <- r$occ$histories[[1]]
  expect_equal(setdiff(names(h), "site_id"), c("2026-04-05", "2026-04-06"))
  expect_equal(unique(r$occ$summary$n_occasions), 2L)
  expect_equal(nrow(r$occ$effort), 2L)
  # a site is only surveyed on its own day, the other column is NA
  expect_equal(sum(is.na(occasion_matrix(h))), 2L)
})

test_that("a longer occasion merges the days and keeps the effort and detections", {
  one <- build_example_occupancy(1)
  two <- build_example_occupancy(2)
  h <- two$occ$histories[[1]]
  expect_equal(setdiff(names(h), "site_id"), "2026-04-05")
  expect_false(anyNA(h[["2026-04-05"]]))
  expect_equal(unique(two$occ$summary$n_occasions), 1L)
  expect_equal(sum(two$occ$effort$effort_hours), sum(one$occ$effort$effort_hours))
  # every site that was detected on any day is detected in the merged occasion
  det_one <- vapply(one$occ$histories, function(x) sum(rowSums(occasion_matrix(x), na.rm = TRUE) > 0), numeric(1))
  det_two <- vapply(two$occ$histories, function(x) sum(rowSums(occasion_matrix(x), na.rm = TRUE) > 0), numeric(1))
  expect_equal(det_two, det_one)
})

test_that("minimum effort applies to the whole occasion", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  suppressMessages(pam_scan_audio(ex$cfg))
  suppressMessages(pam_process_detections(ex$cfg))
  ex$cfg$occupancy$occasion_length_days <- 2
  ex$cfg$occupancy$min_effort_hours <- 1          # the example sites have 6 seconds each
  occ <- suppressMessages(pam_build_occupancy(ex$cfg, force = TRUE))
  h <- occ$histories[[1]]
  expect_true(all(is.na(h[["2026-04-05"]])))
})

test_that("an invalid occasion length is refused", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  suppressMessages(pam_scan_audio(ex$cfg))
  suppressMessages(pam_process_detections(ex$cfg))
  ex$cfg$occupancy$occasion_length_days <- 1.5
  expect_error(suppressMessages(pam_build_occupancy(ex$cfg, force = TRUE)), "bin_days")
})
