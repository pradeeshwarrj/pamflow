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

# ── to_scalar_num ─────────────────────────────────────────────────────────────

test_that("to_scalar_num: NULL returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(NULL), NA_real_)
})

test_that("to_scalar_num: a list returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(list(1, 2)), NA_real_)
})

test_that("to_scalar_num: a matrix returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(matrix(1:4, 2, 2)), NA_real_)
})

test_that("to_scalar_num: a data.frame returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(data.frame(x = 1)), NA_real_)
})

test_that("to_scalar_num: length > 1 vector returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(c(1, 2)), NA_real_)
})

test_that("to_scalar_num: NA returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(NA), NA_real_)
})

test_that("to_scalar_num: NaN returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num(NaN), NA_real_)
})

test_that("to_scalar_num: a valid numeric scalar is returned as-is", {
  expect_equal(pamflow:::to_scalar_num(3.14), 3.14)
})

test_that("to_scalar_num: a numeric-looking string is coerced", {
  expect_equal(pamflow:::to_scalar_num("42"), 42)
})

test_that("to_scalar_num: a non-numeric string returns NA_real_", {
  expect_identical(pamflow:::to_scalar_num("abc"), NA_real_)
})

# ── get_soundeco_val ──────────────────────────────────────────────────────────

test_that("get_soundeco_val: NULL input returns NA_real_", {
  expect_identical(pamflow:::get_soundeco_val(NULL, "a"), NA_real_)
})

test_that("get_soundeco_val: non-list input returns NA_real_", {
  expect_identical(pamflow:::get_soundeco_val(42, "a"), NA_real_)
})

test_that("get_soundeco_val: matching candidate name returns its value", {
  res <- list(aci = 12.5, bio = 8.0)
  expect_equal(pamflow:::get_soundeco_val(res, c("aci")), 12.5)
})

test_that("get_soundeco_val: second candidate name used when first is absent", {
  res <- list(bio = 8.0)
  expect_equal(pamflow:::get_soundeco_val(res, c("aci", "bio")), 8.0)
})

test_that("get_soundeco_val: falls through to first valid value when no candidate matches", {
  res <- list(x = 99.9)
  expect_equal(pamflow:::get_soundeco_val(res, c("aci")), 99.9)
})

test_that("get_soundeco_val: all NA/NULL values return NA_real_", {
  res <- list(a = NA, b = NULL, c = "xyz")
  expect_identical(pamflow:::get_soundeco_val(res, c("aci")), NA_real_)
})

# ── pam_soundscape_export_env ─────────────────────────────────────────────────

test_that("pam_soundscape_export_env: functions are in the returned environment", {
  f1  <- function(x) x + 1
  f2  <- function(x) x * 2
  env <- pamflow:::pam_soundscape_export_env(list(f1 = f1, f2 = f2))
  expect_true(is.environment(env))
  expect_true(exists("f1", envir = env, inherits = FALSE))
  expect_true(exists("f2", envir = env, inherits = FALSE))
})

test_that("pam_soundscape_export_env: functions' environments are re-parented to the export env", {
  f1  <- function(x) x
  env <- pamflow:::pam_soundscape_export_env(list(f1 = f1))
  expect_identical(environment(env$f1), env)
})

test_that("pam_soundscape_export_env: parent of exported env is baseenv()", {
  env <- pamflow:::pam_soundscape_export_env(list(f = function() NULL))
  expect_identical(parent.env(env), baseenv())
})

test_that("pam_soundscape_export_env: functions can call each other via shared env", {
  double <- function(x) x * 2
  quad   <- function(x) double(x) * 2
  env    <- pamflow:::pam_soundscape_export_env(list(double = double, quad = quad))
  expect_equal(env$quad(3), 12)
})

# ── pam_soundscape_summarise: edge cases and extra branches ───────────────────

test_that("pam_soundscape_summarise: aborts on empty raw_dt", {
  expect_error(
    pamflow:::pam_soundscape_summarise(data.table::data.table(), data.table::data.table(file_id = "x")),
    "empty or NULL"
  )
})

test_that("pam_soundscape_summarise: aborts on empty master_dt", {
  raw <- data.table::data.table(
    file_id = "rec001", window_start_sec = 0, aci = 1.2
  )
  expect_error(
    pamflow:::pam_soundscape_summarise(raw, data.table::data.table()),
    "empty or NULL"
  )
})

test_that("pam_soundscape_summarise: aborts when master has no id column", {
  raw <- data.table::data.table(
    file_id = "rec001", window_start_sec = 0, aci = 1.2
  )
  master_bad <- data.table::data.table(
    start_time = as.POSIXct("2024-01-01 06:00:00", tz = "UTC"),
    grid = "GRID1"
    # no file_id, file_name, or filename
  )
  expect_error(
    pamflow:::pam_soundscape_summarise(raw, master_bad),
    "file_id.*file_name.*filename"
  )
})

test_that("pam_soundscape_summarise: uses filename column when file_id absent", {
  raw <- data.table::data.table(
    file_id          = "rec001",
    window_start_sec = c(0, 60),
    aci              = c(1.2, 1.5),
    h                = c(0.8, 0.7)
  )
  master <- data.table::data.table(
    filename   = "rec001.wav",
    start_time = as.POSIXct("2024-01-01 06:00:00", tz = "UTC"),
    grid       = "G1"
  )
  res <- pamflow:::pam_soundscape_summarise(raw, master)
  expect_named(res, c("hourly", "diel", "site_covariates"), ignore.order = TRUE)
  expect_s3_class(res$hourly, "data.table")
})

test_that("pam_soundscape_summarise: night hours produce Night diel_phase", {
  raw <- data.table::data.table(
    file_id          = "rec001",
    window_start_sec = 0,
    aci              = 2.0
  )
  # start_time at 22:00 UTC → should be Night with default day_hours=6:17
  master <- data.table::data.table(
    file_id    = "rec001",
    start_time = as.POSIXct("2024-01-01 22:00:00", tz = "UTC"),
    grid       = "G1"
  )
  res <- pamflow:::pam_soundscape_summarise(raw, master)
  expect_true("Night" %in% res$diel$diel_phase)
})

test_that("pam_soundscape_summarise: site_covariates has day/night mean columns", {
  raw <- data.table::data.table(
    file_id          = c("r1", "r2"),
    window_start_sec = c(0, 0),
    aci              = c(1.1, 2.2)
  )
  master <- data.table::data.table(
    file_id    = c("r1", "r2"),
    start_time = as.POSIXct(c("2024-01-01 08:00:00",
                               "2024-01-01 21:00:00"), tz = "UTC"),
    grid       = c("G1", "G1")
  )
  res <- pamflow:::pam_soundscape_summarise(raw, master)
  cov <- res$site_covariates
  expect_true("aci_day_mean" %in% names(cov))
  expect_true("aci_night_mean" %in% names(cov))
})

# ── pam_soundscape_out_dir ────────────────────────────────────────────────────

test_that("pam_soundscape_out_dir: uses paths$soundscape and run_id", {
  cfg <- list(paths = list(soundscape = "/out/sc"), run_id = "r7")
  expect_equal(pamflow:::pam_soundscape_out_dir(cfg), file.path("/out/sc", "r7"))
})

test_that("pam_soundscape_out_dir: falls back to data$soundscape", {
  cfg <- list(data = list(soundscape = "/d/sc"), soundscape = list(run_id = "rX"))
  expect_equal(pamflow:::pam_soundscape_out_dir(cfg), file.path("/d/sc", "rX"))
})

test_that("pam_soundscape_out_dir: defaults to <project_root>/data/soundscape/run01", {
  cfg <- list(paths = list(project_root = "/proj"))
  expect_equal(pamflow:::pam_soundscape_out_dir(cfg),
               file.path("/proj", "data", "soundscape", "run01"))
})

test_that("pam_soundscape_out_dir: NULL cfg uses current directory", {
  expect_equal(pamflow:::pam_soundscape_out_dir(NULL),
               file.path(".", "data", "soundscape", "run01"))
})

# ── pam_soundscape_batch (pam_soundscape_one stubbed) ─────────────────────────

make_sc_cfg <- function(tmp) {
  list(paths = list(soundscape = tmp, logs = file.path(tmp, "logs")),
       run_id = "r1", soundscape = list(workers = 1))
}

stub_sc_one <- function(audio_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL) {
  data.table::data.table(
    file_id = tools::file_path_sans_ext(basename(audio_path)),
    window_index = 1L, window_start_sec = 0, window_end_sec = 60, aci = 1.5
  )
}

test_that("pam_soundscape_batch: processes files, writes raw csv and checkpoint", {
  tmp <- withr::local_tempdir()
  testthat::local_mocked_bindings(pam_soundscape_one = stub_sc_one, .package = "pamflow")
  res <- suppressMessages(pam_soundscape_batch(c("/x/a.wav", "/x/b.wav"), make_sc_cfg(tmp)))
  expect_equal(sort(res$file_id), c("a", "b"))
  out <- file.path(tmp, "r1")
  expect_true(file.exists(file.path(out, "soundscape_raw.csv")))
  expect_equal(readLines(file.path(out, "done.txt")), c("a.wav", "b.wav"))
})

test_that("pam_soundscape_batch: resumes without reprocessing completed files", {
  tmp <- withr::local_tempdir()
  calls <- 0L
  counting <- function(audio_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL) {
    calls <<- calls + 1L
    stub_sc_one(audio_path)
  }
  testthat::local_mocked_bindings(pam_soundscape_one = counting, .package = "pamflow")
  files <- c("/x/a.wav", "/x/b.wav")
  suppressMessages(pam_soundscape_batch(files, make_sc_cfg(tmp)))
  expect_equal(calls, 2L)
  res <- suppressMessages(pam_soundscape_batch(files, make_sc_cfg(tmp)))
  expect_equal(calls, 2L)
  expect_equal(nrow(res), 2L)
})

test_that("pam_soundscape_batch: failed file is skipped and not checkpointed", {
  tmp <- withr::local_tempdir()
  flaky <- function(audio_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL) {
    if (basename(audio_path) == "bad.wav") stop("boom")
    stub_sc_one(audio_path)
  }
  testthat::local_mocked_bindings(pam_soundscape_one = flaky, .package = "pamflow")
  res <- suppressMessages(pam_soundscape_batch(c("/x/good.wav", "/x/bad.wav"), make_sc_cfg(tmp)))
  expect_equal(res$file_id, "good")
  expect_equal(readLines(file.path(tmp, "r1", "done.txt")), "good.wav")
})

test_that("pam_soundscape_batch: test_n limits the number of files processed", {
  tmp <- withr::local_tempdir()
  testthat::local_mocked_bindings(pam_soundscape_one = stub_sc_one, .package = "pamflow")
  res <- suppressMessages(
    pam_soundscape_batch(paste0("/x/f", 1:5, ".wav"), make_sc_cfg(tmp), test_n = 2)
  )
  expect_equal(nrow(res), 2L)
})

test_that("pam_soundscape_batch: stale done.txt without raw csv is reset", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "r1")
  dir.create(out, recursive = TRUE)
  writeLines("a.wav", file.path(out, "done.txt"))
  testthat::local_mocked_bindings(pam_soundscape_one = stub_sc_one, .package = "pamflow")
  res <- suppressMessages(pam_soundscape_batch("/x/a.wav", make_sc_cfg(tmp)))
  expect_equal(res$file_id, "a")
})

test_that("pam_soundscape_batch: invalid worker setting falls back to one core", {
  tmp <- withr::local_tempdir()
  cfg <- make_sc_cfg(tmp)
  cfg$soundscape$workers <- "not-a-number"
  testthat::local_mocked_bindings(pam_soundscape_one = stub_sc_one, .package = "pamflow")
  res <- suppressWarnings(suppressMessages(pam_soundscape_batch("/x/a.wav", cfg)))
  expect_equal(nrow(res), 1L)
})

# ── pam_soundscape_run: input discovery and error paths ───────────────────────

make_run_cfg <- function(tmp) {
  list(paths = list(metadata = file.path(tmp, "meta"), project_root = tmp,
                    logs = file.path(tmp, "logs"), soundscape = file.path(tmp, "sc")),
       run_id = "r1", filenames = list(timezone = "Asia/Kolkata"))
}

write_run_master <- function(tmp) {
  dir.create(file.path(tmp, "meta"), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(
    data.table::data.table(file_id = "a", grid = "G1", start_time = "2024-03-01T03:00:00Z"),
    file.path(tmp, "meta", "audio_master.csv")
  )
}

test_that("pam_soundscape_run: errors when master metadata is missing", {
  tmp <- withr::local_tempdir()
  expect_error(suppressMessages(pam_soundscape_run(make_run_cfg(tmp))),
               "Master metadata table")
})

test_that("pam_soundscape_run: errors when audio directory is missing", {
  tmp <- withr::local_tempdir()
  write_run_master(tmp)
  cfg <- make_run_cfg(tmp)
  cfg$paths$audio_standardized <- file.path(tmp, "nonexistent")
  expect_error(suppressMessages(pam_soundscape_run(cfg)), "Audio input directory not found")
})

test_that("pam_soundscape_run: errors when audio directory has no audio files", {
  tmp <- withr::local_tempdir()
  write_run_master(tmp)
  cfg <- make_run_cfg(tmp)
  aud <- file.path(tmp, "aud"); dir.create(aud)
  cfg$paths$audio_standardized <- aud
  expect_error(suppressMessages(pam_soundscape_run(cfg)), "No WAV/FLAC files")
})

test_that("pam_soundscape_run: errors when batch returns zero rows", {
  tmp <- withr::local_tempdir()
  write_run_master(tmp)
  cfg <- make_run_cfg(tmp)
  cfg$paths$audio_standardized <- tmp
  testthat::local_mocked_bindings(
    pam_list_audio = function(...) "/x/a.wav",
    pam_soundscape_batch = function(...) data.table::data.table(),
    .package = "pamflow"
  )
  expect_error(suppressMessages(pam_soundscape_run(cfg)), "0 rows")
})

test_that("pam_soundscape_run: writes hourly, diel and site summary CSVs", {
  tmp <- withr::local_tempdir()
  write_run_master(tmp)
  cfg <- make_run_cfg(tmp)
  cfg$paths$audio_standardized <- tmp
  raw <- data.table::data.table(file_id = "a", window_index = 1L, window_start_sec = 0,
                                window_end_sec = 60, aci = 1.2, adi = 2.0)
  testthat::local_mocked_bindings(
    pam_list_audio = function(...) "/x/a.wav",
    pam_soundscape_batch = function(...) raw,
    .package = "pamflow"
  )
  res <- suppressMessages(pam_soundscape_run(cfg))
  expect_named(res, c("raw", "hourly", "diel", "site_covariates"))
  out <- file.path(tmp, "sc", "r1")
  expect_true(file.exists(file.path(out, "soundscape_hourly.csv")))
  expect_true(file.exists(file.path(out, "soundscape_diel_summary.csv")))
  expect_true(file.exists(file.path(out, "soundscape_site_covariates.csv")))
})
