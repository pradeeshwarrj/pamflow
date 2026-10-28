pat <- "^(?<grid>G\\d{4})_(?<date>\\d{8})_(?<time>\\d{6})\\.wav$"

test_that("filenames parse to local start time", {
  dt <- pam_parse_filenames("x/G0059_20260405_182425.wav", pat, "Asia/Kolkata")
  expect_equal(dt$grid, "G0059")
  expect_equal(format(dt$start_time, "%Y-%m-%d %H:%M:%S"), "2026-04-05 18:24:25")
  expect_true(dt$valid_name)
})

test_that("bad filenames are flagged, not dropped", {
  dt <- pam_parse_filenames(c("bad.wav", "G0059_20269999_182425.wav"), pat, "Asia/Kolkata")
  expect_equal(nrow(dt), 2)
  expect_false(any(dt$valid_name))
})

test_that("headers are read and corrupted files flagged", {
  d <- tempfile(); dir.create(d)
  good <- file.path(d, "good.wav"); bad <- file.path(d, "bad.wav")
  sr <- 8000
  w <- tuneR::Wave(left = as.integer(1000 * sin(2 * pi * 440 * seq_len(2 * sr) / sr)),
                   samp.rate = sr, bit = 16)
  tuneR::writeWave(w, good)
  writeLines("not audio", bad)
  info <- pam_audio_info(c(good, bad))
  expect_equal(info[file_path == good, duration_s], 2)
  expect_true(info[file_path == good, readable])
  expect_false(info[file_path == bad, readable])
})

# ── helpers ──────────────────────────────────────────────────────────────────

# Minimal cfg used by pam_read_deployments / pam_add_qc
make_dep_cfg <- function(sheet_path) {
  list(
    paths = list(deployment_sheet = sheet_path),
    deployments = list(
      has_header = FALSE,
      grid_prefix = "G",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
      default_recovery_time = "18:00",
      columns = list(
        "grid", "deployment_id",
        "deploy_date", "deploy_time",
        "retrieve_date", "retrieve_time",
        "recorder", "latitude", "longitude"
      )
    ),
    filenames = list(timezone = "Asia/Kolkata")
  )
}

make_qc_cfg <- function() {
  list(qc = list(gap_tolerance_s = 5, header_chunk_size = 500),
       audio = list(min_duration_s = 5))
}

# Write a minimal deployment CSV (no header) and return the path
write_dep_csv <- function(rows, dir = tempdir()) {
  path <- tempfile(tmpdir = dir, fileext = ".csv")
  writeLines(rows, path)
  path
}

# Build a minimal master data.table with all columns pam_add_qc expects
make_master <- function(grids, starts, durations_s,
                        readable = TRUE, valid_name = TRUE,
                        sr = 44100, bits = 16, channels = 1,
                        file_size_b = NULL) {
  n <- length(grids)
  if (is.null(file_size_b)) {
    file_size_b <- 44 + durations_s * sr * channels * bits / 8
  }
  data.table::data.table(
    file_path  = paste0("x/", grids, "_", seq_len(n), ".wav"),
    file_name  = paste0(grids, "_", seq_len(n), ".wav"),
    grid       = grids,
    start_time = as.POSIXct(starts, tz = "Asia/Kolkata"),
    duration_s = durations_s,
    readable   = readable,
    valid_name = valid_name,
    sample_rate = sr,
    bits       = bits,
    channels   = channels,
    file_size_b = file_size_b
  )
}

# ── pam_read_deployments ──────────────────────────────────────────────────────

test_that("pam_read_deployments: happy path parses dates and prefixes grid", {
  csv <- write_dep_csv(c(
    "59,dep001,2026-04-01,06:00,2026-04-15,18:00,SM4,12.34,77.56",
    "60,dep002,2026-04-02,06:00,2026-04-16,18:00,SM4,12.35,77.57"
  ))
  cfg <- make_dep_cfg(csv)
  dep <- pam_read_deployments(cfg)

  expect_s3_class(dep, "data.table")
  expect_equal(dep$grid, c("G0059", "G0060"))
  expect_equal(dep$deployment_id, c("dep001", "dep002"))
  # POSIXct columns exist and are in IST (UTC+5:30)
  expect_s3_class(dep$deploy_start, "POSIXct")
  expect_s3_class(dep$retrieve_end, "POSIXct")
  expect_equal(format(dep$deploy_start[1], "%Y-%m-%d %H:%M"), "2026-04-01 06:00")
  expect_equal(format(dep$retrieve_end[1], "%Y-%m-%d %H:%M"), "2026-04-15 18:00")
  # coordinates coerced to numeric
  expect_type(dep$latitude, "double")
  expect_false(any(dep$recovery_time_missing))
})

test_that("pam_read_deployments: blank recovery time filled with default", {
  csv <- write_dep_csv(
    "59,dep001,2026-04-01,06:00,2026-04-15,,SM4,12.34,77.56"
  )
  cfg <- make_dep_cfg(csv)
  dep <- pam_read_deployments(cfg)

  expect_true(dep$recovery_time_missing[1])
  expect_equal(format(dep$retrieve_end[1], "%H:%M"), "18:00")
})

test_that("pam_read_deployments: missing sheet errors informatively", {
  cfg <- make_dep_cfg("/nonexistent/path.csv")
  expect_error(pam_read_deployments(cfg), "not found")
})

# ── pam_check_deployments ────────────────────────────────────────────────────

test_that("pam_check_deployments: clean table returns zero rows", {
  dep <- data.table::data.table(
    deployment_id = c("d1", "d2"),
    grid = c("G0001", "G0002"),
    deploy_start  = as.POSIXct(c("2026-04-01 06:00", "2026-04-01 06:00"),
                               tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct(c("2026-04-15 18:00", "2026-04-15 18:00"),
                               tz = "Asia/Kolkata"),
    recovery_time_missing = c(FALSE, FALSE)
  )
  issues <- pam_check_deployments(dep)
  expect_equal(nrow(issues), 0L)
})

test_that("pam_check_deployments: overlap within grid detected", {
  dep <- data.table::data.table(
    deployment_id = c("d1", "d2"),
    grid = c("G0001", "G0001"),
    deploy_start  = as.POSIXct(c("2026-04-01", "2026-04-10"),
                               tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct(c("2026-04-15", "2026-04-20"),
                               tz = "Asia/Kolkata"),
    recovery_time_missing = c(FALSE, FALSE)
  )
  issues <- pam_check_deployments(dep)
  expect_true(any(grepl("overlaps", issues$issue)))
  expect_true("d2" %in% issues$deployment_id)
})

test_that("pam_check_deployments: recovery before deployment flagged", {
  dep <- data.table::data.table(
    deployment_id = "d1",
    grid = "G0001",
    deploy_start  = as.POSIXct("2026-04-15", tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct("2026-04-01", tz = "Asia/Kolkata"),
    recovery_time_missing = FALSE
  )
  issues <- pam_check_deployments(dep)
  expect_true(any(grepl("recovery before", issues$issue)))
})

test_that("pam_check_deployments: missing recover end flagged", {
  dep <- data.table::data.table(
    deployment_id = "d1",
    grid = "G0001",
    deploy_start  = as.POSIXct("2026-04-01", tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct(NA, tz = "Asia/Kolkata"),
    recovery_time_missing = TRUE
  )
  issues <- pam_check_deployments(dep)
  expect_true(any(grepl("recovery date missing", issues$issue)))
})

# ── pam_add_qc ───────────────────────────────────────────────────────────────

test_that("pam_add_qc: clean recordings all pass qc", {
  master <- make_master(
    grids = c("G0001", "G0001", "G0002"),
    starts = c("2026-04-10 06:00:00",
               "2026-04-10 07:00:00",
               "2026-04-10 06:00:00"),
    durations_s = c(3600, 3600, 3600)
  )
  cfg <- make_qc_cfg()
  out <- pam_add_qc(master, cfg)

  expect_true(all(out$qc_pass))
  expect_false(any(out$duplicate))
  expect_false(any(out$short))
  expect_false(any(out$truncated))
  # end_time column added
  expect_true("end_time" %in% names(out))
})

test_that("pam_add_qc: duplicate start time within grid flagged", {
  master <- make_master(
    grids = c("G0001", "G0001"),
    starts = c("2026-04-10 06:00:00", "2026-04-10 06:00:00"),
    durations_s = c(3600, 3600)
  )
  cfg <- make_qc_cfg()
  out <- pam_add_qc(master, cfg)

  expect_true(all(out$duplicate))
  expect_false(any(out$qc_pass))
})

test_that("pam_add_qc: truncated file (too small) flagged", {
  master <- make_master(
    grids = "G0001",
    starts = "2026-04-10 06:00:00",
    durations_s = 3600,
    # 50 % of expected size → should trigger truncated
    file_size_b = round(0.5 * (44 + 3600 * 44100 * 1 * 16 / 8))
  )
  cfg <- make_qc_cfg()
  out <- pam_add_qc(master, cfg)

  expect_true(out$truncated[1])
  expect_false(out$qc_pass[1])
})

test_that("pam_add_qc: gap between consecutive files detected", {
  # File 1 ends at 07:00, File 2 starts at 08:00 → 3600 s gap
  master <- make_master(
    grids = c("G0001", "G0001"),
    starts = c("2026-04-10 06:00:00", "2026-04-10 08:00:00"),
    durations_s = c(3600, 3600)
  )
  cfg <- make_qc_cfg()
  out <- pam_add_qc(master, cfg)

  # Second file should have gap_before = TRUE
  expect_true(out[grid == "G0001" & start_time == as.POSIXct(
    "2026-04-10 08:00:00", tz = "Asia/Kolkata"), gap_before])
})

# ── pam_match_deployments ────────────────────────────────────────────────────

test_that("pam_match_deployments: in-window recordings matched", {
  master <- make_master(
    grids = "G0059",
    starts = "2026-04-10 06:00:00",
    durations_s = 3600
  )
  dep <- data.table::data.table(
    deployment_id = "dep001",
    grid          = "G0059",
    recorder      = "SM4",
    latitude      = 12.34,
    longitude     = 77.56,
    deploy_start  = as.POSIXct("2026-04-01 06:00", tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct("2026-04-20 18:00", tz = "Asia/Kolkata")
  )
  out <- pam_match_deployments(master, dep)

  expect_true(out$in_deployment[1])
  expect_equal(out$deployment_id[1], "dep001")
  expect_equal(out$recorder[1], "SM4")
})

test_that("pam_match_deployments: out-of-window recordings get NA", {
  master <- make_master(
    grids = "G0059",
    starts = "2025-01-01 06:00:00",   # before any deployment
    durations_s = 3600
  )
  dep <- data.table::data.table(
    deployment_id = "dep001",
    grid          = "G0059",
    recorder      = "SM4",
    latitude      = 12.34,
    longitude     = 77.56,
    deploy_start  = as.POSIXct("2026-04-01 06:00", tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct("2026-04-20 18:00", tz = "Asia/Kolkata")
  )
  out <- pam_match_deployments(master, dep)

  expect_false(out$in_deployment[1])
  expect_true(is.na(out$deployment_id[1]))
})

test_that("pam_match_deployments: different grids matched independently", {
  master <- make_master(
    grids = c("G0059", "G0060"),
    starts = c("2026-04-10 06:00:00", "2026-04-10 06:00:00"),
    durations_s = c(3600, 3600)
  )
  dep <- data.table::data.table(
    deployment_id = c("dep001", "dep002"),
    grid          = c("G0059", "G0060"),
    recorder      = c("SM4", "SM4Mini"),
    latitude      = c(12.34, 12.40),
    longitude     = c(77.56, 77.60),
    deploy_start  = as.POSIXct(c("2026-04-01 06:00", "2026-04-01 06:00"),
                               tz = "Asia/Kolkata"),
    retrieve_end  = as.POSIXct(c("2026-04-20 18:00", "2026-04-20 18:00"),
                               tz = "Asia/Kolkata")
  )
  out <- pam_match_deployments(master, dep)

  expect_true(all(out$in_deployment))
  expect_equal(out[grid == "G0059", recorder], "SM4")
  expect_equal(out[grid == "G0060", recorder], "SM4Mini")
})

# ── pam_audio_summary ────────────────────────────────────────────────────────

test_that("pam_audio_summary: overall counts correct", {
  # Build a post-QC master with known counts
  master <- make_master(
    grids = c("G0001", "G0001", "G0002"),
    starts = c("2026-04-10 06:00:00",
               "2026-04-10 07:00:00",
               "2026-04-10 06:00:00"),
    durations_s = c(3600, 3600, 1800)
  )
  # Add expected QC and deployment columns
  master[, `:=`(
    valid_name    = TRUE,
    readable      = TRUE,
    truncated     = FALSE,
    short         = FALSE,
    duplicate     = FALSE,
    gap_before    = FALSE,
    overlap_before = FALSE,
    qc_pass       = TRUE,
    in_deployment = TRUE,
    end_time      = start_time + duration_s
  )]

  summ <- pam_audio_summary(master)

  expect_equal(summ$overall$n_files, 3L)
  expect_equal(summ$overall$n_grids, 2L)
  expect_equal(summ$overall$total_hours, (3600 + 3600 + 1800) / 3600,
               tolerance = 1e-6)
  expect_equal(summ$overall$n_qc_pass, 3L)
  expect_equal(summ$overall$n_outside_deployment, 0L)
})

test_that("pam_audio_summary: per_grid row per grid", {
  master <- make_master(
    grids = c("G0001", "G0001", "G0002"),
    starts = c("2026-04-10 06:00:00",
               "2026-04-10 07:00:00",
               "2026-04-10 06:00:00"),
    durations_s = c(3600, 3600, 1800)
  )
  master[, `:=`(
    valid_name = TRUE, readable = TRUE, truncated = FALSE, short = FALSE,
    duplicate = FALSE, gap_before = FALSE, overlap_before = FALSE,
    qc_pass = TRUE, in_deployment = TRUE,
    end_time = start_time + duration_s
  )]

  summ <- pam_audio_summary(master)

  expect_equal(nrow(summ$per_grid), 2L)
  expect_equal(summ$per_grid[grid == "G0001", n_files], 2L)
  expect_equal(summ$per_grid[grid == "G0002", n_files], 1L)
})

test_that("pam_audio_summary: grids_without_deployment reported", {
  master <- make_master(
    grids = c("G0001", "G0099"),
    starts = c("2026-04-10 06:00:00", "2026-04-10 06:00:00"),
    durations_s = c(3600, 3600)
  )
  master[, `:=`(
    valid_name = TRUE, readable = TRUE, truncated = FALSE, short = FALSE,
    duplicate = FALSE, gap_before = FALSE, overlap_before = FALSE,
    qc_pass = TRUE, in_deployment = TRUE,
    end_time = start_time + duration_s
  )]
  dep <- data.table::data.table(
    deployment_id = "dep001", grid = "G0001",
    recorder = "SM4",
    deploy_start = as.POSIXct("2026-04-01", tz = "Asia/Kolkata"),
    retrieve_end = as.POSIXct("2026-04-20", tz = "Asia/Kolkata")
  )

  summ <- pam_audio_summary(master, dep)

  expect_true("G0099" %in% summ$grids_without_deployment)
  expect_false("G0001" %in% summ$grids_without_deployment)
})

# ── pam_parse_filenames: bad pattern ──────────────────────────────────────────

test_that("pam_parse_filenames: pattern without grid/date/time groups aborts", {
  expect_error(pam_parse_filenames("a.wav", "^(?<grid>G\\d+)", "UTC"), "named groups")
  expect_error(pam_parse_filenames("a.wav", "^G\\d+", "UTC"), "named groups")
})

# ── pam_read_deployments: repairs and errors ──────────────────────────────────

test_that("pam_read_deployments: too few columns aborts", {
  csv <- write_dep_csv("59,dep001,2026-04-01")
  expect_error(pam_read_deployments(make_dep_cfg(csv)), "columns")
})

test_that("pam_read_deployments: has_header skips the first line", {
  csv <- write_dep_csv(c("g,id,d1,t1,d2,t2,rec,lat,lon",
                         "59,dep001,2026-04-01,06:00,2026-04-15,18:00,SM4,12.3,77.5"))
  cfg <- make_dep_cfg(csv); cfg$deployments$has_header <- TRUE
  dep <- pam_read_deployments(cfg)
  expect_equal(nrow(dep), 1L)
  expect_equal(dep$grid, "G0059")
})

test_that("pam_read_deployments: '/' and '.' separators and seconds are normalised", {
  csv <- write_dep_csv("59,dep001,01/04/2026,06.30.15,15.04.2026,18:00:30,SM4,12.3,77.5")
  cfg <- make_dep_cfg(csv); cfg$deployments$date_format <- "%d-%m-%Y"
  dep <- pam_read_deployments(cfg)
  expect_equal(format(dep$deploy_start, "%Y-%m-%d %H:%M"), "2026-04-01 06:30")
  expect_equal(format(dep$retrieve_end, "%Y-%m-%d %H:%M"), "2026-04-15 18:00")
})

test_that("pam_read_deployments: recovery year before 2000 is repaired with a warning", {
  csv <- write_dep_csv("59,dep001,01-04-2026,06:00,15-04-0206,18:00,SM4,12.3,77.5")
  cfg <- make_dep_cfg(csv); cfg$deployments$date_format <- "%d-%m-%Y"
  expect_warning(dep <- pam_read_deployments(cfg), "Recovery year repaired")
  expect_equal(format(dep$retrieve_end, "%Y-%m-%d"), "2026-04-15")
})

test_that("pam_read_deployments: unparseable dates become NA instead of failing", {
  csv <- write_dep_csv("59,dep001,not-a-date,06:00,,,SM4,12.3,77.5")
  dep <- pam_read_deployments(make_dep_cfg(csv))
  expect_true(is.na(dep$deploy_start))
  expect_true(is.na(dep$retrieve_end))
})

# ── pam_check_deployments: remaining issues ───────────────────────────────────

test_that("pam_check_deployments: unparseable start and assumed recovery time flagged", {
  dep <- data.table::data.table(
    deployment_id = c("d1", "d2"), grid = c("G1", "G2"),
    deploy_start = as.POSIXct(c(NA, "2026-04-01 06:00"), tz = "Asia/Kolkata"),
    retrieve_end = as.POSIXct(c("2026-04-02 18:00", "2026-04-02 18:00"), tz = "Asia/Kolkata"),
    recovery_time_missing = c(FALSE, TRUE))
  issues <- pam_check_deployments(dep)
  expect_true(any(grepl("start missing", issues$issue) & issues$deployment_id == "d1"))
  expect_true(any(grepl("end of day assumed", issues$issue) & issues$deployment_id == "d2"))
})

# ── pam_add_qc: additional flags ──────────────────────────────────────────────

test_that("pam_add_qc: file much shorter than the modal duration is flagged short but passes", {
  master <- make_master(grids = rep("G1", 3),
                        starts = c("2026-04-10 06:00:00", "2026-04-10 07:00:00", "2026-04-10 08:00:00"),
                        durations_s = c(3600, 3600, 1800))
  out <- pam_add_qc(master, make_qc_cfg())
  expect_equal(out$short, c(FALSE, FALSE, TRUE))
  expect_true(all(out$qc_pass))
})

test_that("pam_add_qc: overlapping files are flagged overlap_before", {
  master <- make_master(grids = rep("G1", 2),
                        starts = c("2026-04-10 06:00:00", "2026-04-10 06:30:00"),
                        durations_s = c(3600, 3600))
  out <- pam_add_qc(master, make_qc_cfg())
  expect_equal(out$overlap_before, c(FALSE, TRUE))
  expect_equal(out$gap_before, c(FALSE, FALSE))
})

test_that("pam_add_qc: NA bit depth (compressed) is never flagged truncated", {
  master <- make_master(grids = "G1", starts = "2026-04-10 06:00:00", durations_s = 3600,
                        bits = NA_real_, file_size_b = 1000)
  out <- pam_add_qc(master, make_qc_cfg())
  expect_false(out$truncated)
  expect_true(out$qc_pass)
})

test_that("pam_add_qc: unreadable or invalid-name files fail qc", {
  m1 <- make_master(grids = "G1", starts = "2026-04-10 06:00:00", durations_s = 3600,
                    readable = FALSE)
  m2 <- make_master(grids = "G1", starts = "2026-04-10 06:00:00", durations_s = 3600,
                    valid_name = FALSE)
  expect_false(pam_add_qc(m1, make_qc_cfg())$qc_pass)
  expect_false(pam_add_qc(m2, make_qc_cfg())$qc_pass)
})

# ── pam_audio_summary: deployment reporting ───────────────────────────────────

test_that("pam_audio_summary: deployments_without_audio lists unmatched deployments", {
  master <- make_master(grids = "G0001", starts = "2026-04-10 06:00:00", durations_s = 3600)
  master[, `:=`(truncated = FALSE, short = FALSE, duplicate = FALSE, gap_before = FALSE,
                overlap_before = FALSE, qc_pass = TRUE, in_deployment = TRUE,
                deployment_id = "dep001")]
  dep <- data.table::data.table(deployment_id = c("dep001", "dep002"), grid = c("G0001", "G0002"),
                                recorder = "SM4")
  summ <- pam_audio_summary(master, dep)
  expect_equal(summ$deployments_without_audio$deployment_id, "dep002")
  expect_length(summ$grids_without_deployment, 0L)
})

test_that("pam_audio_summary: without deployments the two deployment reports are NULL", {
  master <- make_master(grids = "G0001", starts = "2026-04-10 06:00:00", durations_s = 3600)
  master[, `:=`(truncated = FALSE, short = FALSE, duplicate = FALSE, gap_before = FALSE,
                overlap_before = FALSE, qc_pass = TRUE, in_deployment = TRUE)]
  summ <- pam_audio_summary(master)
  expect_null(summ$grids_without_deployment)
  expect_null(summ$deployments_without_audio)
})

# ── pam_scan_audio orchestration ──────────────────────────────────────────────

scan_write_wav <- function(path, dur = 1, sr = 8000L) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  n <- as.integer(dur * sr)
  tuneR::writeWave(tuneR::Wave(left = as.integer(1000 * sin(2 * pi * 440 * seq_len(n) / sr)),
                               samp.rate = sr, bit = 16), path)
}

mk_scan_cfg <- function(root, dep_row = "59,dep001,2026-04-01,06:00,2026-04-15,18:00,SM4,12.3,77.5") {
  csv <- write_dep_csv(dep_row, dir = root)
  cfg <- make_dep_cfg(csv)
  cfg$paths <- c(cfg$paths, list(
    audio_standardized = file.path(root, "audio"), metadata = file.path(root, "meta"),
    outputs = file.path(root, "out"), logs = file.path(root, "logs")))
  cfg$qc <- list(gap_tolerance_s = 5, header_chunk_size = 1L)
  cfg$filenames <- list(pattern = pat, timezone = "Asia/Kolkata")
  cfg
}

mk_scan_audio <- function(root, times = c("060000", "060001")) {
  for (tm in times) {
    scan_write_wav(file.path(root, "audio", "G0059", sprintf("G0059_20260405_%s.wav", tm)))
  }
}

test_that("pam_scan_audio: builds master, summaries and caches headers", {
  skip_if_not_installed("tuneR")
  root <- withr::local_tempdir(); cfg <- mk_scan_cfg(root); mk_scan_audio(root)
  res <- suppressMessages(pam_scan_audio(cfg))
  expect_named(res, c("master", "deployments", "summary"))
  expect_equal(nrow(res$master), 2L)
  expect_true(all(res$master$in_deployment))
  expect_true(all(res$master$valid_name))
  expect_true(all(res$master$qc_pass))
  expect_equal(res$summary$overall$n_files, 2L)
  expect_true(file.exists(file.path(root, "meta", "audio_headers.csv")))
  expect_true(file.exists(file.path(root, "meta", "audio_master.csv")))
  expect_true(file.exists(file.path(root, "out", "audio_summary_per_grid.csv")))
  expect_true(file.exists(file.path(root, "out", "deployment_issues.csv")))
})

test_that("pam_scan_audio: re-run reads only new files; force re-reads everything", {
  skip_if_not_installed("tuneR")
  root <- withr::local_tempdir(); cfg <- mk_scan_cfg(root); mk_scan_audio(root)
  orig_info <- pamflow:::pam_audio_info
  n_read <- 0L
  testthat::local_mocked_bindings(
    pam_audio_info = function(files) { n_read <<- n_read + length(files); orig_info(files) },
    .package = "pamflow")
  suppressMessages(pam_scan_audio(cfg))
  expect_equal(n_read, 2L)

  n_read <- 0L
  suppressMessages(pam_scan_audio(cfg))
  expect_equal(n_read, 0L)

  scan_write_wav(file.path(root, "audio", "G0059", "G0059_20260405_060002.wav"))
  n_read <- 0L
  res <- suppressMessages(pam_scan_audio(cfg))
  expect_equal(n_read, 1L)
  expect_equal(nrow(res$master), 3L)

  n_read <- 0L
  suppressMessages(pam_scan_audio(cfg, force = TRUE))
  expect_equal(n_read, 3L)
})

test_that("pam_scan_audio: deployment issues are written and logged as a warning", {
  skip_if_not_installed("tuneR")
  root <- withr::local_tempdir()
  cfg <- mk_scan_cfg(root, "59,dep001,2026-04-01,06:00,2026-04-15,,SM4,12.3,77.5")
  mk_scan_audio(root)
  suppressMessages(pam_scan_audio(cfg))
  issues <- data.table::fread(file.path(root, "out", "deployment_issues.csv"))
  expect_true(any(grepl("end of day assumed", issues$issue)))
  expect_match(paste(readLines(file.path(root, "logs", "01_scan.log")), collapse = "\n"),
               "deployment issues")
})

test_that("pam_scan_audio: recordings outside every deployment are kept but flagged", {
  skip_if_not_installed("tuneR")
  root <- withr::local_tempdir()
  cfg <- mk_scan_cfg(root, "59,dep001,2026-01-01,06:00,2026-01-02,18:00,SM4,12.3,77.5")
  mk_scan_audio(root)
  res <- suppressMessages(pam_scan_audio(cfg))
  expect_equal(nrow(res$master), 2L)
  expect_false(any(res$master$in_deployment))
  expect_equal(res$summary$overall$n_outside_deployment, 2L)
})

test_that("pam_scan_audio: aborts when the audio folder is missing or empty", {
  root <- withr::local_tempdir(); cfg <- mk_scan_cfg(root)
  expect_error(suppressMessages(pam_scan_audio(cfg)), "Audio folder not found")
  dir.create(file.path(root, "audio"))
  expect_error(suppressMessages(pam_scan_audio(cfg)), "No .wav/.flac files")
})
