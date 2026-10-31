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

# ── pam_extract_grid ──────────────────────────────────────────────────────────

test_that("pam_extract_grid: named group from a custom pattern is used", {
  pat <- "^(?<site>[A-Z]+)-(?<n>\\d+)\\.wav$"
  expect_equal(pam_extract_grid("ABC-12.wav", pat), "ABC")
})

test_that("pam_extract_grid: pattern that does not match falls back to leading token", {
  expect_equal(pam_extract_grid("X1_rest.wav", "^(?<grid>Z\\d+)_"), "X1")
})

test_that("pam_extract_grid: pattern without a recognised group falls back", {
  expect_equal(pam_extract_grid("ABC-12.wav", "^(?<foo>[A-Z]+)-"), "unassigned")
})

test_that("pam_extract_grid: no underscore and no pattern gives 'unassigned'", {
  expect_equal(pam_extract_grid("recording.wav"), "unassigned")
  expect_equal(pam_extract_grid("recording.wav", ""), "unassigned")
})

test_that("pam_extract_grid: directory components are ignored", {
  expect_equal(pam_extract_grid("some/dir/G0001_x.wav"), "G0001")
})

# ── pam_parse_datetime: other formats and fallbacks ──────────────────────────

test_that("pam_parse_datetime: separators '-' and 'T' are accepted", {
  expect_equal(pam_parse_datetime("rec_20240405-173058.wav"), "20240405_173058")
  expect_equal(pam_parse_datetime("rec_20240405T173058.wav"), "20240405_173058")
})

test_that("pam_parse_datetime: falls back to file modification time", {
  f <- withr::local_tempfile(fileext = ".wav"); writeLines("x", f)
  Sys.setFileTime(f, as.POSIXct("2023-02-03 04:05:06", tz = Sys.timezone()))
  got <- pam_parse_datetime("nodate.wav", file_path = f)
  expect_equal(got, format(file.info(f)$mtime, "%Y%m%d_%H%M%S"))
})

test_that("pam_parse_datetime: with no date and no file returns a current timestamp", {
  expect_match(pam_parse_datetime("nodate.wav"), "^\\d{8}_\\d{6}$")
  expect_match(pam_parse_datetime("nodate.wav", file_path = "/does/not/exist"),
               "^\\d{8}_\\d{6}$")
})

# ── pam_inspect_raw ───────────────────────────────────────────────────────────

std_make_wav <- function(path, dur = 1, sr = 8000L) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  n <- as.integer(dur * sr)
  tuneR::writeWave(tuneR::Wave(left = as.integer(1000 * sin(2 * pi * 440 * seq_len(n) / sr)),
                               samp.rate = sr, bit = 16), path)
}

# raw/ holds a 2 s recording in a subfolder, a 0.2 s memo, a text file, and a corrupt .wav
std_project <- function(root) {
  raw <- file.path(root, "raw")
  std_make_wav(file.path(raw, "sub", "G0059_20240101_120000.wav"), 2)
  std_make_wav(file.path(raw, "G0060_20240101_130000.wav"), 0.2)
  writeLines("log", file.path(raw, "notes.txt"))
  writeLines("not audio", file.path(raw, "broken.wav"))
  list(raw = raw, std = file.path(root, "std"), iso = file.path(root, "iso"))
}

run_std <- function(p, ...) {
  suppressMessages(pam_standardize(cfg = list(), raw_dir = p$raw, standardized_dir = p$std,
                                   isolated_dir = p$iso, min_duration_s = 0.5, ...))
}

test_that("pam_inspect_raw: errors on a missing directory", {
  expect_error(suppressMessages(pam_inspect_raw("/no/such/dir")), "does not exist")
})

test_that("pam_inspect_raw: empty directory returns a typed zero-row table", {
  d <- withr::local_tempdir()
  res <- suppressMessages(pam_inspect_raw(d))
  expect_equal(nrow(res), 0L)
  expect_true(all(c("file_path", "category", "grid", "parsed_datetime") %in% names(res)))
})

test_that("pam_inspect_raw: classifies recordings, memos, non-audio and corrupt files", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  res <- suppressMessages(pam_inspect_raw(p$raw, min_duration_s = 0.5))
  cats <- setNames(res$category, res$filename)
  expect_equal(cats[["G0059_20240101_120000.wav"]], "standardizable")
  expect_equal(cats[["G0060_20240101_130000.wav"]], "isolated_memo")
  expect_equal(cats[["notes.txt"]], "isolated_non_audio")
  expect_equal(cats[["broken.wav"]], "corrupt")
  expect_equal(res[filename == "G0059_20240101_120000.wav", parsed_datetime], "20240101_120000")
  expect_equal(res[filename == "G0059_20240101_120000.wav", rel_path],
               "sub/G0059_20240101_120000.wav")
})

test_that("pam_inspect_raw: recursive = FALSE ignores subfolders", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  res <- suppressMessages(pam_inspect_raw(p$raw, recursive = FALSE, min_duration_s = 0.5))
  expect_false("G0059_20240101_120000.wav" %in% res$filename)
  expect_equal(nrow(res), 3L)
})

# ── pam_standardize ───────────────────────────────────────────────────────────

test_that("pam_standardize: dry run plans every action and touches no disk", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  log <- run_std(p, dry_run = TRUE, target_format = "flac")
  expect_setequal(log$action, c("PLANNED_TRANSCODE", "PLANNED_ISOLATE_MEMO",
                                "PLANNED_ISOLATE_NON_AUDIO", "PLANNED_ISOLATE_CORRUPT"))
  expect_equal(log[category == "corrupt", status], "WARN")
  expect_false(dir.exists(p$std))
  expect_false(dir.exists(p$iso))
})

test_that("pam_standardize: each organize_folders layout builds the expected destination", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  dest <- function(org) {
    run_std(p, dry_run = TRUE, target_format = "flac",
            organize_folders = org)[category == "standardizable", dest_path]
  }
  f <- "G0059_20240101_120000.flac"
  expect_equal(dest("grid"), file.path(p$std, "G0059", f))
  expect_equal(dest("grid_date"), file.path(p$std, "G0059", "2024", "01", "01", f))
  expect_equal(dest("date"), file.path(p$std, "2024", "01", "01", f))
  expect_equal(dest("preserve"), file.path(p$std, "sub", f))
  expect_equal(dest("flat"), file.path(p$std, f))
})

test_that("pam_standardize: prefix replaces the grid-based file name", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  log <- run_std(p, dry_run = TRUE, target_format = "flac", prefix = "PRE")
  expect_equal(basename(log[category == "standardizable", dest_path]), "PRE_20240101_120000.flac")
})

test_that("pam_standardize: rename_strategy 'keep' retains the original name; unassigned grid folder", {
  skip_if_not_installed("tuneR")
  root <- withr::local_tempdir()
  raw <- file.path(root, "raw")
  std_make_wav(file.path(raw, "rec1.wav"), 2)
  log <- suppressMessages(pam_standardize(
    cfg = list(), raw_dir = raw, standardized_dir = file.path(root, "std"),
    isolated_dir = file.path(root, "iso"), dry_run = TRUE, target_format = "flac",
    rename_strategy = "keep", min_duration_s = 0.5))
  expect_equal(log$dest_path, file.path(root, "std", "unassigned", "rec1.flac"))
})

test_that("pam_standardize: isolate flags FALSE leave non-audio and memos in place", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  log <- run_std(p, dry_run = TRUE, isolate_non_audio = FALSE, isolate_short = FALSE)
  expect_equal(log[category == "isolated_non_audio", action], "SKIPPED")
  expect_equal(log[category == "isolated_memo", action], "SKIPPED")
  expect_true(is.na(log[category == "isolated_memo", dest_path]))
})

test_that("pam_standardize: live run copies compliant files and isolates the rest", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  log <- run_std(p, dry_run = FALSE, target_format = "wav", target_hz = 8000, channels = 1)
  expect_equal(log[category == "standardizable", action], "COPIED_COMPLIANT")
  expect_true(file.exists(file.path(p$std, "G0059", "G0059_20240101_120000.wav")))
  expect_true(file.exists(file.path(p$iso, "non_audio", "notes.txt")))
  expect_true(file.exists(file.path(p$iso, "memos", "G0060_20240101_130000.wav")))
  expect_true(file.exists(file.path(p$iso, "corrupt", "broken.wav")))
  expect_true(file.exists(file.path(p$std, "standardization_log.csv")))
  expect_true(file.exists(file.path(p$raw, "notes.txt")))     # originals untouched
})

test_that("pam_standardize: a failed transcode is logged as an error and does not abort", {
  skip_if_not_installed("tuneR")
  skip_if_not_installed("av")
  p <- std_project(withr::local_tempdir())
  testthat::local_mocked_bindings(
    av_audio_convert = function(...) stop("ffmpeg missing"), .package = "av")
  log <- run_std(p, dry_run = FALSE, target_format = "flac")
  expect_equal(log[category == "standardizable", action], "FAILED_TRANSCODE")
  expect_equal(log[category == "standardizable", status], "ERROR")
  expect_true(file.exists(file.path(p$std, "standardization_log.csv")))
})

test_that("pam_standardize: settings are read from cfg when arguments are omitted", {
  skip_if_not_installed("tuneR")
  p <- std_project(withr::local_tempdir())
  cfg <- list(
    paths = list(audio_raw = p$raw, audio_standardized = p$std, audio_isolated = p$iso),
    standardization = list(dry_run = TRUE, target_format = "WAV", target_hz = 8000,
                           min_duration_s = 0.5, organize_folders = "flat"),
    filenames = list(timezone = "UTC"))
  log <- suppressMessages(pam_standardize(cfg = cfg))
  expect_equal(log[category == "standardizable", action], "PLANNED_COPY_COMPLIANT")
  expect_equal(log[category == "standardizable", dest_path],
               file.path(p$std, "G0059_20240101_120000.wav"))
})

test_that("pam_standardize: an empty raw folder returns the empty inspection table", {
  d <- withr::local_tempdir()
  res <- suppressMessages(pam_standardize(cfg = list(), raw_dir = d,
                                          standardized_dir = file.path(d, "s"),
                                          isolated_dir = file.path(d, "i")))
  expect_equal(nrow(res), 0L)
})

test_that("the standardization app scans a folder, shows the numbers and runs a dry run", {
  skip_if_not_installed("shiny")
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  dest <- withr::local_tempdir()
  tz <- ex$cfg$filenames$timezone

  shiny::testServer(pam_standardization_app(ex$cfg, raw_dir = ex$audio_dir), {
    expect_match(console_text(), "Ready", fixed = TRUE)
    expect_equal(nrow(inspect_data()), 0L)
    session$setInputs(raw_path = ex$audio_dir, min_dur = 1, tz = tz, btn_scan = 1)
    expect_equal(nrow(inspect_data()), 6L)
    expect_match(as.character(output$stat_total_files$html), ">6<", fixed = TRUE)
    expect_match(as.character(output$stat_standardizable$html), "pam-stat-num", fixed = TRUE)
    expect_match(as.character(output$stat_corrupt$html), ">0<", fixed = TRUE)

    session$setInputs(std_path = file.path(dest, "std"), iso_path = file.path(dest, "iso"),
                      prefix = "", target_format = "wav", target_hz = 8000, channels = "1",
                      organize_folders = "grid", rename_strategy = "auto",
                      isolate_non_audio = TRUE, isolate_short = TRUE, btn_dry_run = 1)
    expect_match(console_text(), "^Dry run finished\\. Planned actions: 6\\.")
    expect_equal(nrow(log_data()), 6L)
  })
})

test_that("the standardization app reports a missing folder in its log", {
  skip_if_not_installed("shiny")
  shiny::testServer(pam_standardization_app(list(), raw_dir = tempdir()), {
    session$setInputs(raw_path = file.path(tempdir(), "no_such_folder_xyz"), min_dur = 1,
                      tz = "UTC", btn_scan = 1)
    expect_match(console_text(), "the raw folder does not exist", fixed = TRUE)
  })
})
