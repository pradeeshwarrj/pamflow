test_that("bin_days must be a single whole number of days", {
  expect_equal(pamflow:::pam_check_bin_days(7), 7L)
  expect_error(pamflow:::pam_check_bin_days(0), "bin_days")
  expect_error(pamflow:::pam_check_bin_days(1.5), "bin_days")
  expect_error(pamflow:::pam_check_bin_days(NA), "bin_days")
  expect_error(pamflow:::pam_check_bin_days(c(1, 2)), "bin_days")
})

test_that("pam_bin_start puts every date in the bin that starts on or before it", {
  origin <- as.Date("2026-04-10")
  dates <- as.Date(c("2026-04-10", "2026-04-11", "2026-04-12", "2026-04-16", "2026-04-17"))
  expect_equal(pamflow:::pam_bin_start(dates, origin, 1L), dates)
  expect_equal(pamflow:::pam_bin_start(dates, origin, 2L),
               as.Date(c("2026-04-10", "2026-04-10", "2026-04-12", "2026-04-16", "2026-04-16")))
  expect_equal(pamflow:::pam_bin_start(dates, origin, 7L),
               as.Date(c("2026-04-10", "2026-04-10", "2026-04-10", "2026-04-10", "2026-04-17")))
})

make_master <- function() {
  data.table::data.table(
    site_id = c("S1", "S1", "S1", "S2"),
    start_time = as.POSIXct(c("2026-04-10 06:00:00", "2026-04-11 06:00:00",
                              "2026-04-12 06:00:00", "2026-04-11 06:00:00"),
                            tz = "Asia/Kolkata"),
    duration_s = 3600, qc_pass = TRUE, in_deployment = TRUE)
}

test_that("effort is summed into bins that share the same edges at every site", {
  eff <- pamflow:::pam_effort_bins(make_master(), bin_days = 2L, tz = "Asia/Kolkata",
                                   min_effort_h = 1.5)
  expect_equal(attr(eff, "origin"), as.Date("2026-04-10"))
  s1 <- eff[site_id == "S1"]
  expect_equal(s1$bin_start, as.Date(c("2026-04-10", "2026-04-12")))
  expect_equal(s1$bin_end, as.Date(c("2026-04-11", "2026-04-13")))
  expect_equal(s1$effort_hours, c(2, 1))
  expect_equal(s1$n_days, c(2L, 1L))
  expect_equal(s1$sufficient, c(TRUE, FALSE))
  s2 <- eff[site_id == "S2"]
  expect_equal(s2$bin_start, as.Date("2026-04-10"))   # same edges as S1
  expect_equal(s2$effort_hours, 1)
})

test_that("one-day bins reproduce the daily effort of the occupancy stage", {
  daily <- pamflow:::pam_daily_effort(make_master(), tz = "Asia/Kolkata", min_effort_h = 1)
  bins <- pamflow:::pam_effort_bins(make_master(), bin_days = 1L, tz = "Asia/Kolkata",
                                    min_effort_h = 1)
  expect_equal(bins$effort_hours, daily$effort_hours)
  expect_equal(bins$bin_start, daily$occasion_date)
  expect_equal(bins$sufficient, daily$sufficient)
})

test_that("recordings that fail QC or lie outside a deployment add no effort", {
  m <- make_master()
  m[2, qc_pass := FALSE]
  m[3, in_deployment := FALSE]
  eff <- pamflow:::pam_effort_bins(m, bin_days = 1L, tz = "Asia/Kolkata", min_effort_h = 0)
  expect_equal(nrow(eff[site_id == "S1"]), 1L)
  none <- pamflow:::pam_effort_bins(m[0], bin_days = 1L, tz = "Asia/Kolkata")
  expect_equal(nrow(none), 0L)
  expect_named(none, c("site_id", "bin_start", "bin_end", "effort_hours", "n_days", "sufficient"))
})

# Example project with the scan and cleaning already done
make_ready_example <- function(env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  list(ex = ex, proc = proc)
}

test_that("the detection table counts every cleaned event once and matches effort", {
  r <- make_ready_example()
  tab <- suppressMessages(pam_detection_table(r$ex$cfg))
  expect_named(tab, c("site_id", "bin_start", "bin_end", "species", "scientific_name",
                      "n_detections", "n_files", "max_confidence", "effort_hours", "n_days",
                      "sufficient", "detections_per_hour"))
  expect_equal(sum(tab$n_detections), nrow(r$proc$clean))
  expect_equal(attr(tab, "bin_days"), 1L)
  # one surveyed site-bin per site-day with recordings; every species has a row in each
  n_bins <- nrow(unique(tab[, .(site_id, bin_start)]))
  expect_equal(n_bins, 2L)
  expect_equal(nrow(tab), n_bins * data.table::uniqueN(tab$species))
  expect_false(anyDuplicated(tab[, .(site_id, bin_start, species)]) > 0L)
  expect_true(all(tab$effort_hours > 0))
  expect_equal(tab$detections_per_hour, tab$n_detections / tab$effort_hours)
  expect_true(all(tab$n_files <= tab$n_detections))
  expect_true(all(tab$sufficient))
})

test_that("complete = FALSE keeps only rows with detections", {
  r <- make_ready_example()
  full <- suppressMessages(pam_detection_table(r$ex$cfg))
  sparse <- suppressMessages(pam_detection_table(r$ex$cfg, complete = FALSE))
  expect_true(all(sparse$n_detections > 0L))
  expect_equal(sum(sparse$n_detections), sum(full$n_detections))
  expect_equal(nrow(sparse), nrow(full[n_detections > 0L]))
})

test_that("longer bins merge days and keep the totals", {
  r <- make_ready_example()
  one <- suppressMessages(pam_detection_table(r$ex$cfg, bin_days = 1))
  two <- suppressMessages(pam_detection_table(r$ex$cfg, bin_days = 2))
  expect_equal(attr(two, "bin_days"), 2L)
  expect_equal(unique(two$bin_start), as.Date("2026-04-05"))
  expect_equal(sum(two$n_detections), sum(one$n_detections))
  expect_equal(sum(unique(two[, .(site_id, effort_hours)])$effort_hours),
               sum(unique(one[, .(site_id, bin_start, effort_hours)])$effort_hours))
  expect_error(pam_detection_table(r$ex$cfg, bin_days = 0), "bin_days")
})

test_that("the bin length defaults to the occupancy setting of the config", {
  r <- make_ready_example()
  r$ex$cfg$occupancy$occasion_length_days <- 2
  tab <- suppressMessages(pam_detection_table(r$ex$cfg))
  expect_equal(attr(tab, "bin_days"), 2L)
})

test_that("a minimum effort flags short bins without dropping them", {
  r <- make_ready_example()
  tab <- suppressMessages(pam_detection_table(r$ex$cfg, min_effort_hours = 1))
  expect_false(any(tab$sufficient))
  expect_equal(sum(tab$n_detections), nrow(r$proc$clean))
  expect_error(pam_detection_table(r$ex$cfg, min_effort_hours = -1), "min_effort_hours")
})

test_that("species thresholds remove events but keep the rows", {
  r <- make_ready_example()
  base <- suppressMessages(pam_detection_table(r$ex$cfg))
  thr <- data.frame(scientific_name = unique(base$scientific_name), threshold = 1)
  strict <- suppressMessages(pam_detection_table(r$ex$cfg, thresholds = thr))
  expect_equal(sum(strict$n_detections), sum(r$proc$clean$confidence >= 1))
  expect_equal(nrow(strict), nrow(base))
  none <- suppressMessages(pam_detection_table(r$ex$cfg, thresholds = thr[0, ]))
  expect_equal(sum(none$n_detections), sum(base$n_detections))
})

test_that("write = TRUE saves the table and nothing is written by default", {
  r <- make_ready_example()
  path <- file.path(r$ex$cfg$paths$outputs, "run01", "detection_table.csv")
  suppressMessages(pam_detection_table(r$ex$cfg))
  expect_false(file.exists(path))
  tab <- suppressMessages(pam_detection_table(r$ex$cfg, write = TRUE))
  expect_true(file.exists(path))
  expect_equal(nrow(data.table::fread(path)), nrow(tab))
})

test_that("missing inputs give clear errors", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  expect_error(pam_detection_table(ex$cfg), "audio_master.csv|detections_clean.csv")
  suppressMessages(pam_scan_audio(ex$cfg))
  expect_error(pam_detection_table(ex$cfg), "detections_clean.csv not found")
  expect_error(pam_detection_table(ex$cfg, extra_by = "nope"), "detections_clean.csv|nope")
})
