test_that("pam_period gives the hour, day, Monday-based week or first of the month", {
  d <- as.Date(c("2026-04-10", "2026-04-12", "2026-04-13", "2026-04-30"))   # Fri, Sun, Mon, Thu
  expect_equal(pamflow:::pam_period(d, c(5L, 6L, 7L, 8L), "hour"), c(5L, 6L, 7L, 8L))
  expect_equal(pamflow:::pam_period(d, 0L, "day"), d)
  expect_equal(pamflow:::pam_period(d, 0L, "week"),
               as.Date(c("2026-04-06", "2026-04-06", "2026-04-13", "2026-04-27")))
  expect_equal(pamflow:::pam_period(d, 0L, "month"), rep(as.Date("2026-04-01"), 4))
  expect_error(pamflow:::pam_period(d, 0L, "year"), "must be one of")
})

hourly_master <- function() {
  data.table::data.table(
    site_id = "S1",
    start_time = as.POSIXct(c("2026-04-10 06:50:00", "2026-04-10 23:50:00", "2026-04-10 08:00:00"),
                            tz = "Asia/Kolkata"),
    duration_s = c(1800, 1200, 3600), qc_pass = TRUE, in_deployment = TRUE)
}

test_that("effort is split over the clock hours a recording covers, also across midnight", {
  eff <- pamflow:::pam_hourly_effort(hourly_master(), tz = "Asia/Kolkata")
  at <- function(day, h) eff[date == as.Date(day) & hour == h, effort_hours]
  expect_equal(at("2026-04-10", 6L), 10 / 60)     # 06:50-07:00
  expect_equal(at("2026-04-10", 7L), 20 / 60)     # 07:00-07:20
  expect_equal(at("2026-04-10", 23L), 10 / 60)    # 23:50-24:00
  expect_equal(at("2026-04-11", 0L), 10 / 60)     # 00:00-00:10 next day
  expect_equal(at("2026-04-10", 8L), 1)           # a recording that exactly fills hour 8
  expect_equal(nrow(eff[date == as.Date("2026-04-10") & hour == 9L]), 0L)
  expect_equal(sum(eff$effort_hours), sum(hourly_master()$duration_s) / 3600)
})

test_that("effort in the same hour from several recordings or sites is summed per site", {
  m <- data.table::data.table(
    site_id = c("S1", "S1", "S2"),
    start_time = as.POSIXct(c("2026-04-10 06:00:00", "2026-04-10 06:30:00", "2026-04-10 06:15:00"),
                            tz = "Asia/Kolkata"),
    duration_s = 900, qc_pass = TRUE, in_deployment = TRUE)
  eff <- pamflow:::pam_hourly_effort(m, tz = "Asia/Kolkata")
  expect_equal(eff[site_id == "S1", effort_hours], 0.5)
  expect_equal(eff[site_id == "S2", effort_hours], 0.25)
})

test_that("recordings that fail QC, lie outside a deployment or have no length add no effort", {
  m <- hourly_master()
  m[1, qc_pass := FALSE]
  m[2, in_deployment := FALSE]
  eff <- pamflow:::pam_hourly_effort(m, tz = "Asia/Kolkata")
  expect_equal(sum(eff$effort_hours), 1)
  none <- pamflow:::pam_hourly_effort(m[0], tz = "Asia/Kolkata")
  expect_equal(nrow(none), 0L)
  expect_named(none, c("site_id", "date", "hour", "effort_hours"))
})

make_activity_example <- function(env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  list(ex = ex, proc = proc)
}

test_that("hourly activity pools the sites and counts every cleaned event once", {
  r <- make_activity_example()
  act <- suppressMessages(pam_activity(r$ex$cfg, by = "hour"))
  expect_named(act, c("period", "species", "scientific_name", "n_detections", "n_sites_surveyed",
                      "effort_hours", "n_sites_detected", "sufficient", "detections_per_hour",
                      "relative_activity"), ignore.order = TRUE)
  expect_equal(attr(act, "by"), "hour")
  expect_equal(sort(unique(act$period)), c(6L, 18L))    # G0110 records at 06h, G0059 at 18h
  expect_equal(sum(act$n_detections), nrow(r$proc$clean))
  expect_true(all(abs(act$effort_hours - 6 / 3600) < 1e-9))   # three 2-second files per site
  expect_true(all(act$n_sites_surveyed == 1L))
  expect_equal(nrow(act), 2L * data.table::uniqueN(act$species))
  expect_false(anyDuplicated(act[, .(period, species)]) > 0L)
  expect_equal(act$detections_per_hour, act$n_detections / act$effort_hours)
  expect_true(all(act$relative_activity <= 1, na.rm = TRUE))
  peak <- suppressWarnings(act[, .(top = max(relative_activity, na.rm = TRUE)), by = species])
  expect_true(all(peak$top %in% c(1, -Inf)))
})

test_that("day, week and month activity group the same events differently", {
  r <- make_activity_example()
  n <- nrow(r$proc$clean)
  day <- suppressMessages(pam_activity(r$ex$cfg, by = "day"))
  expect_equal(sort(unique(day$period)), as.Date(c("2026-04-05", "2026-04-06")))
  week <- suppressMessages(pam_activity(r$ex$cfg, by = "week"))
  expect_equal(sort(unique(week$period)), as.Date(c("2026-03-30", "2026-04-06")))   # Mondays
  month <- suppressMessages(pam_activity(r$ex$cfg, by = "month"))
  expect_equal(unique(month$period), as.Date("2026-04-01"))
  expect_true(all(month$n_sites_surveyed == 2L))
  expect_true(all(abs(month$effort_hours - 12 / 3600) < 1e-9))
  for (tab in list(day, week, month)) expect_equal(sum(tab$n_detections), n)
})

test_that("by_site keeps one row per site and period and drops the site counts", {
  r <- make_activity_example()
  act <- suppressMessages(pam_activity(r$ex$cfg, by = "day", by_site = TRUE))
  expect_true("site_id" %in% names(act))
  expect_false(any(c("n_sites_surveyed", "n_sites_detected") %in% names(act)))
  expect_equal(sort(unique(act$site_id)), c("G0059", "G0110"))
  expect_equal(nrow(act), 2L * data.table::uniqueN(act$species))
  expect_equal(sum(act$n_detections), nrow(r$proc$clean))
})

test_that("species selection, thresholds and minimum effort behave as documented", {
  r <- make_activity_example()
  all_act <- suppressMessages(pam_activity(r$ex$cfg, by = "hour"))
  one <- all_act$scientific_name[1]
  sel <- suppressMessages(pam_activity(r$ex$cfg, by = "hour", species = toupper(one)))
  expect_equal(unique(sel$scientific_name), one)
  expect_equal(sum(sel$n_detections), sum(all_act[scientific_name == one]$n_detections))
  expect_error(pam_activity(r$ex$cfg, species = "no such species"), "No detections")

  thr <- data.frame(scientific_name = unique(all_act$scientific_name), threshold = 1)
  strict <- suppressMessages(pam_activity(r$ex$cfg, by = "hour", thresholds = thr))
  expect_equal(sum(strict$n_detections), sum(r$proc$clean$confidence >= 1))
  expect_equal(nrow(strict), nrow(all_act))

  short <- suppressMessages(pam_activity(r$ex$cfg, by = "hour", min_effort_hours = 1))
  expect_false(any(short$sufficient))
  expect_true(all(is.na(short$detections_per_hour)))
  expect_equal(sum(short$n_detections), sum(all_act$n_detections))
})

test_that("pam_activity validates its arguments and writes only on request", {
  r <- make_activity_example()
  expect_error(pam_activity(r$ex$cfg, by = "year"), "should be one of")
  expect_error(pam_activity(r$ex$cfg, by_site = NA), "by_site")
  expect_error(pam_activity(r$ex$cfg, min_effort_hours = -1), "min_effort_hours")
  path <- file.path(r$ex$cfg$paths$outputs, "run01", "activity_hour.csv")
  suppressMessages(pam_activity(r$ex$cfg, by = "hour"))
  expect_false(file.exists(path))
  act <- suppressMessages(pam_activity(r$ex$cfg, by = "hour", write = TRUE))
  expect_true(file.exists(path))
  expect_equal(nrow(data.table::fread(path)), nrow(act))
})

test_that("pam_plot_activity draws pooled tables and refuses other input", {
  r <- make_activity_example()
  act <- suppressMessages(pam_activity(r$ex$cfg, by = "hour"))
  expect_s3_class(pam_plot_activity(act), "ggplot")
  expect_s3_class(pam_plot_activity(act, relative = TRUE), "ggplot")
  expect_s3_class(pam_plot_activity(act, species = act$scientific_name[1]), "ggplot")
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(pam_plot_activity(act))))
  day <- suppressMessages(pam_activity(r$ex$cfg, by = "day"))
  expect_s3_class(pam_plot_activity(day), "ggplot")
  expect_false("value" %in% names(act))                  # the table is not changed
  expect_error(pam_plot_activity(act, species = "none"), "None of the requested")
  expect_error(pam_plot_activity(data.frame(a = 1)), "pam_activity")
  site <- suppressMessages(pam_activity(r$ex$cfg, by = "day", by_site = TRUE))
  expect_error(pam_plot_activity(site), "pooled")
})
