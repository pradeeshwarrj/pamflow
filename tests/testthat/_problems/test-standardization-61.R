# Extracted from test-standardization.R:61

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "pamflow", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
tmp_dir <- testthat::test_path("tmp_stage00")
raw_dir <- file.path(tmp_dir, "raw")
std_dir <- file.path(tmp_dir, "standardized")
iso_dir <- file.path(tmp_dir, "isolated")
on.exit(fs::dir_delete(tmp_dir), add = TRUE)
fs::dir_create(raw_dir)
wav_path <- file.path(raw_dir, "G0059_20240101_120000.wav")
sr <- 44100
t <- seq(0, 1, length.out = sr)
sine_wave <- tuneR::Wave(
    left = as.integer(sin(2 * pi * 440 * t) * 32767),
    samp.rate = sr,
    bit = 16
  )
tuneR::writeWave(sine_wave, wav_path)
txt_path <- file.path(raw_dir, "sensor_log.txt")
writeLines("Sensor active", txt_path)
inspect_dt <- pam_inspect_raw(raw_dir, min_duration_s = 5)
expect_equal(nrow(inspect_dt), 2)
expect_true("g0059_20240101_120000.wav" %in% tolower(inspect_dt$filename))
expect_equal(sum(inspect_dt$category == "isolated_non_audio"), 1)
expect_equal(sum(inspect_dt$category == "isolated_memo"), 1)
log_dry <- pam_standardize(
    raw_dir = raw_dir,
    standardized_dir = std_dir,
    isolated_dir = iso_dir,
    dry_run = TRUE,
    target_format = "flac",
    min_duration_s = 0.5,
    organize_folders = "grid"
  )
