test_that("pam_parse_datetime handles ISO strings, digit patterns, and fallbacks", {
  # 1. ISO timestamp format
  dt_iso <- pam_parse_datetime("G0059_20260405_173058.wav")
  expect_equal(dt_iso, "20260405_173058")

  # 2. 14 digit format
  dt_14 <- pam_parse_datetime("REC_20240405173058.flac")
  expect_equal(dt_14, "20240405_173058")

  # 3. 12 digit format (Swift/SongMeter)
  dt_12 <- pam_parse_datetime("Swift_240405173058.wav")
  expect_equal(dt_12, "20240405_173058")
})

test_that("pam_extract_grid parses leading grid and site identifiers", {
  expect_equal(pam_extract_grid("G0059_20260405_173058.wav"), "G0059")
  expect_equal(pam_extract_grid("SiteA_20240101_120000.flac"), "SiteA")
  expect_equal(pam_extract_grid("SM4-01_20240101_120000.wav"), "SM4-01")
})

test_that("pam_inspect_raw and pam_standardize classify and process audio and non-audio files", {
  tmp_dir <- testthat::test_path("tmp_stage00")
  raw_dir <- file.path(tmp_dir, "raw")
  std_dir <- file.path(tmp_dir, "standardized")
  iso_dir <- file.path(tmp_dir, "isolated")

  on.exit(fs::dir_delete(tmp_dir), add = TRUE)
  fs::dir_create(raw_dir)

  # Create synthetic test WAV file (1 sec tone)
  wav_path <- file.path(raw_dir, "G0059_20240101_120000.wav")
  sr <- 44100
  t <- seq(0, 1, length.out = sr)
  sine_wave <- tuneR::Wave(
    left = as.integer(sin(2 * pi * 440 * t) * 32767),
    samp.rate = sr,
    bit = 16
  )
  tuneR::writeWave(sine_wave, wav_path)

  # Create non-audio log file
  txt_path <- file.path(raw_dir, "sensor_log.txt")
  writeLines("Sensor active", txt_path)

  # 1. Inspect raw directory
  inspect_dt <- pam_inspect_raw(raw_dir, min_duration_s = 5)
  expect_equal(nrow(inspect_dt), 2)
  expect_true("g0059_20240101_120000.wav" %in% tolower(inspect_dt$filename))
  expect_equal(sum(inspect_dt$category == "isolated_non_audio"), 1)
  expect_equal(sum(inspect_dt$category == "isolated_memo"), 1)

  # 2. Run Dry-Run standardization
  log_dry <- pam_standardize(
    raw_dir = raw_dir,
    standardized_dir = std_dir,
    isolated_dir = iso_dir,
    dry_run = TRUE,
    target_format = "flac",
    min_duration_s = 0.5,
    organize_folders = "grid"
  )

  expect_true(nrow(log_dry) >= 2)
  expect_true(any(grepl("PLANNED", log_dry$action)))

  # 3. Run Live standardization
  log_live <- pam_standardize(
    raw_dir = raw_dir,
    standardized_dir = std_dir,
    isolated_dir = iso_dir,
    dry_run = FALSE,
    target_format = "flac",
    min_duration_s = 0.5,
    organize_folders = "grid"
  )

  expect_true(file.exists(file.path(iso_dir, "non_audio", "sensor_log.txt")))
  expect_true(file.exists(file.path(std_dir, "G0059", "G0059_20240101_120000.flac")))
})
