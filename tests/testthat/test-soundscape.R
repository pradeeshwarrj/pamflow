test_that("pam_soundscape_one computes indices on synthetic wave", {
  skip_if_not_installed("soundecology")
  skip_if_not_installed("seewave")

  sr <- 44100
  duration <- 10
  t <- seq(0, duration, length.out = sr * duration)
  sine_wave <- sin(2 * pi * 1000 * t)

  wav_obj <- tuneR::Wave(
    left = as.integer(sine_wave * 32767),
    samp.rate = sr,
    bit = 16
  )

  tmp_wav <- tempfile(fileext = ".wav")
  tuneR::writeWave(wav_obj, tmp_wav)
  on.exit(unlink(tmp_wav), add = TRUE)

  cfg <- list(
    soundscape = list(
      low_stop_hz = 0,
      anthro_range = c(1000, 2000),
      bio_range = c(2000, 11000),
      window_sec = 5,
      sub_window_sec = 5
    )
  )

  res <- pam_soundscape_one(tmp_wav, cfg = cfg)

  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 2)
  expect_true(all(c("aci", "adi", "aeve", "bio", "h", "m", "ndsi") %in% names(res)))
})

test_that("pam_soundscape_summarise calculates timestamps and timezone-aware summaries correctly", {
  raw_dt <- data.table::data.table(
    file_id          = c("GRID1_SITE1_20250101_060000", "GRID1_SITE1_20250101_060000"),
    window_index     = c(1L, 2L),
    window_start_sec = c(0, 600),
    window_end_sec   = c(600, 1200),
    aci              = c(100.5, 102.3),
    adi              = c(1.2, 1.4),
    aeve             = c(0.8, 0.85),
    bio              = c(5.1, 5.3),
    h                = c(0.7, 0.72),
    m                = c(0.1, 0.12),
    ndsi             = c(0.4, 0.45)
  )

  master_dt <- data.table::data.table(
    file_id    = "GRID1_SITE1_20250101_060000",
    grid       = "GRID1",
    site       = "SITE1",
    start_time = as.POSIXct("2025-01-01 00:30:00", tz = "UTC")
  )

  cfg <- list(
    filenames = list(timezone = "Asia/Kolkata"),
    soundscape = list(day_hours = c(6, 17))
  )

  res <- pam_soundscape_summarise(raw_dt, master_dt, cfg)

  expect_type(res, "list")
  expect_true(all(c("hourly", "diel", "site_covariates") %in% names(res)))
  expect_s3_class(res$hourly, "data.table")
  expect_equal(nrow(res$hourly), 1)
  expect_equal(res$hourly$hour[1], 6L)
  expect_s3_class(res$diel, "data.table")
  expect_equal(res$diel$diel_phase[1], "Day")
  expect_s3_class(res$site_covariates, "data.table")
  expect_true("aci_day_mean" %in% names(res$site_covariates))
})
