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
