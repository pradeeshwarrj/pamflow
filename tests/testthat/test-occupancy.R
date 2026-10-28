test_that("pam_site_id: single deployment per grid", {
  dt <- data.table::data.table(
    grid = c("G0001", "G0001", "G0002"),
    deployment_id = c("d1", "d1", "d2")
  )
  pamflow:::pam_site_id(dt)
  expect_equal(dt$site_id, c("G0001", "G0001", "G0002"))
})

test_that("pam_site_id: multiple deployments per grid", {
  dt <- data.table::data.table(
    grid = c("G0001", "G0001", "G0002", "G0002"),
    deployment_id = c("d1", "d2", "d3", "d3")
  )
  pamflow:::pam_site_id(dt)
  expect_equal(dt$site_id,
               c("G0001_d1", "G0001_d2", "G0002", "G0002"))
})

test_that("pam_site_id: no deployment_id column", {
  dt <- data.table::data.table(grid = c("G0001", "G0002"))
  pamflow:::pam_site_id(dt)
  expect_equal(dt$site_id, c("G0001", "G0002"))
})

test_that("pam_daily_effort: basic calculation", {
  master <- data.table::data.table(
    site_id = c("G0001", "G0001", "G0001"),
    start_time = as.POSIXct(
      c("2026-04-10 06:00:00",
        "2026-04-10 07:00:00",
        "2026-04-11 06:00:00"),
      tz = "Asia/Kolkata"
    ),
    duration_s = c(3600, 3600, 1800),
    qc_pass = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "Asia/Kolkata",
                                    min_effort_h = 2)
  expect_equal(nrow(eff), 2L)
  # Day 1: 2 h total
  d1 <- eff[occasion_date == as.Date("2026-04-10")]
  expect_equal(d1$effort_hours, 2)
  expect_true(d1$sufficient)
  # Day 2: 0.5 h total
  d2 <- eff[occasion_date == as.Date("2026-04-11")]
  expect_equal(d2$effort_hours, 0.5)
  expect_false(d2$sufficient)
})

test_that("pam_daily_effort: filters out bad recordings", {
  master <- data.table::data.table(
    site_id = c("G0001", "G0001"),
    start_time = as.POSIXct(
      c("2026-04-10 06:00:00", "2026-04-10 07:00:00"),
      tz = "Asia/Kolkata"
    ),
    duration_s = c(3600, 3600),
    qc_pass = c(TRUE, FALSE),
    in_deployment = c(TRUE, TRUE)
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "Asia/Kolkata",
                                    min_effort_h = 2)
  expect_equal(nrow(eff), 1L)
  expect_equal(eff$effort_hours, 1)
  expect_false(eff$sufficient)
})

test_that("pam_daily_effort: midnight crossing", {
  master <- data.table::data.table(
    site_id = "G0001",
    start_time = as.POSIXct("2026-04-10 23:30:00",
                            tz = "Asia/Kolkata"),
    duration_s = 3600,
    qc_pass = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "Asia/Kolkata",
                                    min_effort_h = 0)
  expect_equal(nrow(eff), 2L)
  d1 <- eff[occasion_date == as.Date("2026-04-10")]
  d2 <- eff[occasion_date == as.Date("2026-04-11")]
  expect_equal(d1$effort_hours, 0.5, tolerance = 0.01)
  expect_equal(d2$effort_hours, 0.5, tolerance = 0.01)
})

test_that("pam_detection_matrix: 1/0/NA assignment", {
  effort <- data.table::data.table(
    site_id = c("A", "A", "B", "B"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11",
                              "2026-04-10", "2026-04-11")),
    effort_hours = c(5, 3, 1, 4),
    sufficient = c(TRUE, TRUE, FALSE, TRUE)
  )
  events <- data.table::data.table(
    site_id = c("A", "B"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11")),
    confidence = c(0.8, 0.6)
  )
  wide <- pamflow:::pam_detection_matrix(events, effort,
                                         threshold = 0.5)
  expect_equal(nrow(wide), 2L)
  # Site A, day 1: detected
  expect_equal(wide[site_id == "A", as.character(as.Date("2026-04-10")),
                    with = FALSE][[1]], 1L)
  # Site A, day 2: surveyed, not detected
  expect_equal(wide[site_id == "A", as.character(as.Date("2026-04-11")),
                    with = FALSE][[1]], 0L)
  # Site B, day 1: insufficient effort -> NA
  expect_true(is.na(wide[site_id == "B",
                         as.character(as.Date("2026-04-10")),
                         with = FALSE][[1]]))
  # Site B, day 2: detected
  expect_equal(wide[site_id == "B", as.character(as.Date("2026-04-11")),
                    with = FALSE][[1]], 1L)
})

test_that("pam_occasion_covariates: julian date", {
  effort <- data.table::data.table(
    site_id = c("A", "A", "A"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11",
                              "2026-04-13")),
    effort_hours = c(5, 3, 4),
    sufficient = c(TRUE, TRUE, TRUE)
  )
  cov <- pamflow:::pam_occasion_covariates(effort)
  expect_equal(cov$julian_date, c(1L, 2L, 4L))
})

# ── pam_site_covariates ───────────────────────────────────────────────────────

test_that("pam_site_covariates: merges effort totals per site", {
  master <- data.table::data.table(
    site_id       = c("G0001", "G0001", "G0002"),
    grid          = c("G0001", "G0001", "G0002"),
    deployment_id = c("d1",    "d1",    "d2"),
    latitude      = c(12.34,   12.34,   12.50),
    longitude     = c(77.56,   77.56,   77.60)
  )
  effort <- data.table::data.table(
    site_id       = c("G0001", "G0001", "G0002"),
    occasion_date = as.Date(c("2026-04-10", "2026-04-11", "2026-04-10")),
    effort_hours  = c(5, 4, 3),
    sufficient    = c(TRUE, TRUE, TRUE)
  )
  cov <- pamflow:::pam_site_covariates(master, effort)

  expect_s3_class(cov, "data.table")
  expect_equal(nrow(cov), 2L)   # 2 unique sites
  g1 <- cov[site_id == "G0001"]
  g2 <- cov[site_id == "G0002"]
  expect_equal(g1$total_effort_hours,   9)
  expect_equal(g1$n_occasions_surveyed, 2L)
  expect_equal(g2$total_effort_hours,   3)
  expect_equal(g2$n_occasions_surveyed, 1L)
})

test_that("pam_site_covariates: site with no effort rows gets zeros", {
  master <- data.table::data.table(
    site_id = "G0099", grid = "G0099", deployment_id = "d99",
    latitude = 12.0, longitude = 77.0
  )
  effort <- data.table::data.table(
    site_id = character(), occasion_date = as.Date(character()),
    effort_hours = numeric(), sufficient = logical()
  )
  cov <- pamflow:::pam_site_covariates(master, effort)

  expect_equal(nrow(cov), 1L)
  expect_equal(cov$total_effort_hours,   0)
  expect_equal(cov$n_occasions_surveyed, 0L)
})

# ── pam_build_occupancy (orchestrator) ───────────────────────────────────────

test_that("pam_build_occupancy: skips rebuild when outputs exist and force = FALSE", {
  tmp <- withr::local_tempdir()
  occ_dir <- file.path(tmp, "occupancy", "run01")
  dir.create(occ_dir, recursive = TRUE)
  # Pre-create the summary sentinel that signals a complete run
  writeLines("done", file.path(occ_dir, "occupancy_summary.csv"))

  cfg <- list(
    paths = list(
      metadata   = tmp,
      detections = tmp,
      occupancy  = file.path(tmp, "occupancy"),
      logs       = file.path(tmp, "logs")
    ),
    filenames  = list(timezone = "Asia/Kolkata"),
    occupancy  = list(run_id = "run01", min_effort_hours = 2, min_detections = 1),
    processing = list(min_confidence = 0.5,
                      species_thresholds_file = NULL)
  )

  result <- pam_build_occupancy(cfg, run_id = "run01", force = FALSE)
  expect_null(result)   # returns invisible(NULL) when skipped
})

test_that("pam_build_occupancy: errors informatively when audio_master.csv missing", {
  tmp <- withr::local_tempdir()
  cfg <- list(
    paths = list(
      metadata   = tmp,
      detections = tmp,
      occupancy  = file.path(tmp, "occupancy"),
      logs       = file.path(tmp, "logs")
    ),
    filenames  = list(timezone = "Asia/Kolkata"),
    occupancy  = list(run_id = "run01", min_effort_hours = 2, min_detections = 1),
    processing = list(min_confidence = 0.5,
                      species_thresholds_file = NULL)
  )
  expect_error(
    pam_build_occupancy(cfg, run_id = "run01", force = TRUE),
    "audio_master.csv not found"
  )
})

# ── additional edge cases ─────────────────────────────────────────────────────

test_that("pam_site_id: adds site_id even when all rows have qc_pass FALSE", {
  dt <- data.table::data.table(
    grid          = "G1",
    deployment_id = "d1",
    qc_pass       = FALSE
  )
  pamflow:::pam_site_id(dt)
  expect_true("site_id" %in% names(dt))
  expect_equal(nrow(dt), 1L)
})

test_that("pam_daily_effort: recording below min_effort_h is flagged insufficient", {
  m <- data.table::data.table(
    site_id       = "G1_R1",
    start_time    = as.POSIXct("2024-01-01 06:00:00", tz = "UTC"),
    duration_s    = 3600,     # 1 hour — below 2 h threshold
    qc_pass       = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(m, tz = "UTC", min_effort_h = 2)
  expect_false(eff$sufficient[1])
})

test_that("pam_detection_matrix: detection below threshold becomes 0 not 1", {
  effort <- data.table::data.table(
    site_id       = "G1_R1",
    occasion_date = as.Date("2024-01-01"),
    effort_hours  = 8,
    sufficient    = TRUE
  )
  events <- data.table::data.table(
    site_id       = "G1_R1",
    occasion_date = as.Date("2024-01-01"),
    confidence    = 0.3    # below default threshold of 0.5
  )
  wide <- pamflow:::pam_detection_matrix(events, effort, threshold = 0.5)
  expect_equal(wide[site_id == "G1_R1", "2024-01-01", with = FALSE][[1]], 0L)
})

test_that("pam_detection_matrix: insufficient effort day is NA", {
  effort <- data.table::data.table(
    site_id       = "G1_R1",
    occasion_date = as.Date("2024-01-01"),
    effort_hours  = 0.5,
    sufficient    = FALSE
  )
  events <- data.table::data.table(
    site_id       = character(),
    occasion_date = as.Date(character()),
    confidence    = numeric()
  )
  wide <- pamflow:::pam_detection_matrix(events, effort, threshold = 0.5)
  expect_true(is.na(wide[site_id == "G1_R1", "2024-01-01", with = FALSE][[1]]))
})

test_that("pam_occasion_covariates: empty effort returns table with julian_date column", {
  eff_empty <- data.table::data.table(
    site_id       = character(),
    occasion_date = as.Date(character()),
    effort_hours  = numeric(),
    sufficient    = logical()
  )
  cov <- pamflow:::pam_occasion_covariates(eff_empty)
  expect_true("julian_date" %in% names(cov))
  expect_equal(nrow(cov), 0L)
})

# ── pam_daily_effort: midnight-crossing branch ───────────────────────────────

test_that("pam_daily_effort: midnight-crossing recording is split across two days", {
  # 23:30 start, 3600 s duration → crosses midnight in UTC
  master <- data.table::data.table(
    site_id       = "G1_R1",
    start_time    = as.POSIXct("2024-01-01 23:30:00", tz = "UTC"),
    duration_s    = 3600,   # spans into 2024-01-02
    qc_pass       = TRUE,
    in_deployment = TRUE
  )
  eff <- pamflow:::pam_daily_effort(master, tz = "UTC", min_effort_h = 0)
  expect_equal(nrow(eff), 2L)
  dates <- sort(eff$occasion_date)
  expect_equal(dates, as.Date(c("2024-01-01", "2024-01-02")))
  expect_equal(sum(eff$effort_hours), 1.0, tolerance = 1e-6)
})

# ── pam_site_covariates: optional coordinate columns ─────────────────────────

test_that("pam_site_covariates: includes latitude/longitude when present", {
  master <- data.table::data.table(
    site_id       = c("G1", "G1"),
    grid          = c("G1", "G1"),
    deployment_id = c("D1", "D1"),
    latitude      = c(12.5, 12.5),
    longitude     = c(77.5, 77.5),
    qc_pass       = TRUE,
    in_deployment = TRUE
  )
  effort <- data.table::data.table(
    site_id       = "G1",
    occasion_date = as.Date("2024-01-01"),
    effort_hours  = 4.0,
    sufficient    = TRUE
  )
  cov <- pamflow:::pam_site_covariates(master, effort)
  expect_true("latitude" %in% names(cov))
  expect_true("longitude" %in% names(cov))
  expect_equal(cov$latitude[1], 12.5)
})

test_that("pam_site_covariates: total_effort_hours and n_occasions_surveyed are summed", {
  master <- data.table::data.table(
    site_id = "G1", grid = "G1", deployment_id = "D1"
  )
  effort <- data.table::data.table(
    site_id       = c("G1", "G1"),
    occasion_date = as.Date(c("2024-01-01", "2024-01-02")),
    effort_hours  = c(3.0, 5.0),
    sufficient    = c(TRUE, TRUE)
  )
  cov <- pamflow:::pam_site_covariates(master, effort)
  expect_equal(cov$total_effort_hours, 8.0)
  expect_equal(cov$n_occasions_surveyed, 2L)
})

# ── pam_detection_matrix: multi-species events ───────────────────────────────

test_that("pam_detection_matrix: two sites produce two rows", {
  effort <- data.table::data.table(
    site_id       = c("S1", "S2"),
    occasion_date = as.Date(c("2024-01-01", "2024-01-01")),
    effort_hours  = c(4.0, 4.0),
    sufficient    = c(TRUE, TRUE)
  )
  events <- data.table::data.table(
    site_id       = "S1",
    occasion_date = as.Date("2024-01-01"),
    confidence    = 0.9
  )
  wide <- pamflow:::pam_detection_matrix(events, effort, threshold = 0.5)
  expect_equal(nrow(wide), 2L)
  expect_equal(wide[site_id == "S1", "2024-01-01", with = FALSE][[1]], 1L)
  expect_equal(wide[site_id == "S2", "2024-01-01", with = FALSE][[1]], 0L)
})

# ── pam_build_occupancy: full orchestration with stub inputs ──────────────────

# Builds a minimal project on disk: 1 site, 2 days x 3 one-hour recordings,
# and detections for "Aus bus" (12) and "Bus cus" (2).
make_occ_project <- function(tmp, det_cols = c("filename", "species", "confidence",
                                               "detection_datetime"),
                             thresh_file = NULL) {
  meta_dir <- file.path(tmp, "metadata")
  det_dir  <- file.path(tmp, "detections", "run01", "processed")
  dir.create(meta_dir, recursive = TRUE)
  dir.create(det_dir, recursive = TRUE)

  starts <- c(paste0("2024-03-01T0", 3:5, ":00:00Z"),
              paste0("2024-03-02T0", 3:5, ":00:00Z"))
  master <- data.table::data.table(
    file_name     = paste0("f", 1:6, ".wav"),
    grid          = "G1",
    deployment_id = 1L,
    start_time    = starts,
    duration_s    = 3600,
    qc_pass       = TRUE,
    in_deployment = TRUE
  )
  data.table::fwrite(master, file.path(meta_dir, "audio_master.csv"))

  det <- data.table::data.table(
    filename           = c(rep(paste0("f", 1:6, ".wav"), 2), "f1.wav", "f2.wav"),
    species            = c(rep("Aus bus", 12), "Bus cus", "Bus cus"),
    confidence         = 0.9,
    detection_datetime = c(rep(c(paste("2024-03-01", c("08:45:00", "09:45:00", "10:45:00")),
                                 paste("2024-03-02", c("08:45:00", "09:45:00", "10:45:00"))), 2),
                           "2024-03-01 08:50:00", "2024-03-01 09:50:00")
  )
  if (!"detection_datetime" %in% det_cols) {
    det[, detection_datetime := NULL]
  }
  data.table::fwrite(det, file.path(det_dir, "detections_clean.csv"))

  list(
    paths = list(
      metadata     = meta_dir,
      detections   = file.path(tmp, "detections"),
      occupancy    = file.path(tmp, "occupancy"),
      logs         = file.path(tmp, "logs"),
      project_root = tmp
    ),
    filenames  = list(timezone = "Asia/Kolkata"),
    occupancy  = list(run_id = "run01", min_effort_hours = 2, min_detections = 10),
    processing = list(min_confidence = 0.5, species_thresholds_file = thresh_file)
  )
}

test_that("pam_build_occupancy: builds histories, covariates and summary on disk", {
  tmp <- withr::local_tempdir()
  cfg <- make_occ_project(tmp)
  res <- suppressMessages(pam_build_occupancy(cfg, run_id = "run01", force = TRUE))

  occ_dir <- file.path(tmp, "occupancy", "run01")
  expect_true(file.exists(file.path(occ_dir, "detection_history_Aus_bus.csv")))
  expect_true(file.exists(file.path(occ_dir, "occasion_covariates.csv")))
  expect_true(file.exists(file.path(occ_dir, "site_covariates.csv")))
  expect_true(file.exists(file.path(occ_dir, "occupancy_summary.csv")))
  # Species below min_detections gets no history
  expect_false(file.exists(file.path(occ_dir, "detection_history_Bus_cus.csv")))

  expect_named(res, c("histories", "effort", "site_covariates", "summary"))
  expect_equal(names(res$histories), "Aus bus")
  expect_equal(res$summary$n_sites, 1L)
  expect_equal(res$summary$n_occasions, 2L)
  expect_equal(res$summary$n_sites_detected, 1L)
  expect_equal(res$summary$naive_occupancy, 1)
  expect_equal(res$summary$threshold_used, 0.5)
  expect_equal(res$site_covariates$total_effort_hours, 6)
})

test_that("pam_build_occupancy: per-species threshold file overrides global threshold", {
  tmp <- withr::local_tempdir()
  thr <- file.path(tmp, "thr.csv")
  data.table::fwrite(data.table::data.table(scientific_name = "Aus bus", threshold = 0.95), thr)
  cfg <- make_occ_project(tmp, thresh_file = thr)
  res <- suppressMessages(pam_build_occupancy(cfg, run_id = "run01", force = TRUE))
  expect_equal(res$summary$threshold_used, 0.95)
  expect_equal(res$summary$n_sites_detected, 0L)
  expect_equal(res$summary$naive_occupancy, 0)
})

test_that("pam_build_occupancy: missing thresholds file falls back to global threshold", {
  tmp <- withr::local_tempdir()
  cfg <- make_occ_project(tmp, thresh_file = file.path(tmp, "nope.csv"))
  res <- suppressMessages(pam_build_occupancy(cfg, run_id = "run01", force = TRUE))
  expect_equal(res$summary$threshold_used, 0.5)
})

test_that("pam_build_occupancy: returns NULL when no species meet min_detections", {
  tmp <- withr::local_tempdir()
  cfg <- make_occ_project(tmp)
  cfg$occupancy$min_detections <- 100
  res <- suppressMessages(pam_build_occupancy(cfg, run_id = "run01", force = TRUE))
  expect_null(res)
  expect_false(file.exists(file.path(tmp, "occupancy", "run01", "occupancy_summary.csv")))
})

test_that("pam_build_occupancy: errors when detections_clean.csv is missing", {
  tmp <- withr::local_tempdir()
  cfg <- make_occ_project(tmp)
  unlink(file.path(tmp, "detections", "run01", "processed", "detections_clean.csv"))
  expect_error(suppressMessages(pam_build_occupancy(cfg, run_id = "run01", force = TRUE)),
               "detections_clean.csv not found")
})

test_that("pam_build_occupancy: errors when detections lack any timestamp column", {
  tmp <- withr::local_tempdir()
  cfg <- make_occ_project(tmp, det_cols = c("filename", "species", "confidence"))
  expect_error(suppressMessages(pam_build_occupancy(cfg, run_id = "run01", force = TRUE)),
               "detection_datetime")
})
