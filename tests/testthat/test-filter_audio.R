test_that("butterworth Q values match the 8th-order design", {
  expect_equal(round(sort(pam_butterworth_q(8)), 4), c(0.5098, 0.6013, 0.9000, 2.5629))
})

test_that("filter string has four sections for order 8 and rejects odd orders", {
  f <- pam_highpass_filter_string(250, 8)
  expect_equal(lengths(regmatches(f, gregexpr("highpass=", f))), 4)
  expect_match(f, "f=250")
  expect_error(pam_highpass_filter_string(250, 7))
})

test_that("ffmpeg removes low frequencies and keeps the passband", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  sr <- 48000; n <- 2 * sr; t <- seq_len(n) / sr
  x <- 0.3 * sin(2 * pi * 60 * t) + 0.3 * sin(2 * pi * 1000 * t)
  inp <- tempfile(fileext = ".wav"); outp <- tempfile(fileext = ".wav")
  tuneR::writeWave(tuneR::Wave(left = as.integer(round(x * 32767)),
                               samp.rate = sr, bit = 16), inp)
  res <- pam_filter_one(list(input = inp, output = outp, bits = 16L),
                        pam_highpass_filter_string(250, 8), "ffmpeg")
  expect_true(res$ok)
  y <- as.numeric(tuneR::readWave(outp)@left)
  x_in <- as.numeric(tuneR::readWave(inp)@left)
  amp <- function(sig, f) Mod(stats::fft(sig))[f * length(sig) / sr + 1]
  expect_lt(amp(y, 60) / amp(y, 1000), 0.001)           # 60 Hz essentially gone
  expect_gt(amp(y, 1000) / amp(x_in, 1000), 0.99)       # 1 kHz untouched
  expect_false(file.exists(paste0(outp, ".part")))
})

test_that("a missing input fails cleanly and leaves no partial file", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  outp <- tempfile(fileext = ".wav")
  res <- pam_filter_one(list(input = "does_not_exist.wav", output = outp, bits = 16L),
                        pam_highpass_filter_string(250, 8), "ffmpeg")
  expect_false(res$ok)
  expect_false(file.exists(outp))
  expect_false(file.exists(paste0(outp, ".part")))
})

# ── pam_butterworth_q: order variants and validation ─────────────────────────

test_that("pam_butterworth_q: order=2 returns one value close to 1/sqrt(2)", {
  q <- pamflow:::pam_butterworth_q(2L)
  expect_length(q, 1L)
  expect_equal(round(q, 4), 0.7071)
})

test_that("pam_butterworth_q: order=4 returns two Q values", {
  q <- pamflow:::pam_butterworth_q(4L)
  expect_length(q, 2L)
  expect_equal(round(sort(q), 4), c(0.5412, 1.3066))
})

test_that("pam_butterworth_q: all values are positive and finite", {
  q <- pamflow:::pam_butterworth_q(8L)
  expect_true(all(is.finite(q)))
  expect_true(all(q > 0))
})

test_that("pam_butterworth_q: odd order aborts", {
  expect_error(pamflow:::pam_butterworth_q(3L), "even number")
})

test_that("pam_butterworth_q: order below 2 aborts", {
  expect_error(pamflow:::pam_butterworth_q(1L), regexp = "2")
})

# ── pam_highpass_filter_string: validation ───────────────────────────────────

test_that("pam_highpass_filter_string: order=4 produces two-section cascade", {
  f <- pam_highpass_filter_string(500, 4L)
  expect_equal(lengths(regmatches(f, gregexpr("highpass=", f))), 2L)
  expect_match(f, "f=500")
})

test_that("pam_highpass_filter_string: returns a single string", {
  f <- pam_highpass_filter_string(250, 8L)
  expect_type(f, "character")
  expect_length(f, 1L)
})

test_that("pam_highpass_filter_string: negative cutoff aborts", {
  expect_error(pam_highpass_filter_string(-1, 8L), "positive number")
})

test_that("pam_highpass_filter_string: zero cutoff aborts", {
  expect_error(pam_highpass_filter_string(0, 8L), "positive number")
})

test_that("pam_highpass_filter_string: non-numeric cutoff aborts", {
  expect_error(pam_highpass_filter_string("abc", 8L))
})

# ── pam_filter_one: codec selection and partial-file cleanup (no ffmpeg) ──────

test_that("pam_filter_one: .part file removed on failure (missing input)", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  outp <- tempfile(fileext = ".wav")
  res <- pamflow:::pam_filter_one(
    list(input = "no_such_file_xyz.wav", output = outp, bits = 16L),
    pam_highpass_filter_string(250, 8),
    "ffmpeg"
  )
  expect_false(res$ok)
  expect_false(file.exists(paste0(outp, ".part")))
  expect_false(file.exists(outp))
  expect_type(res$message, "character")
})

test_that("pam_filter_one: FLAC output path does not produce a .wav", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  # Build a minimal 16-bit WAV in memory
  sr <- 8000L; n <- sr
  wav <- tuneR::Wave(left = as.integer(rep(0L, n)), samp.rate = sr, bit = 16L)
  inp <- tempfile(fileext = ".wav")
  out <- tempfile(fileext = ".flac")
  tuneR::writeWave(wav, inp)
  res <- pamflow:::pam_filter_one(
    list(input = inp, output = out, bits = 16L),
    pam_highpass_filter_string(250, 4),
    "ffmpeg"
  )
  expect_true(res$ok)
  expect_true(file.exists(out))
  expect_false(file.exists(paste0(out, ".part")))  # .part cleaned up
  unlink(c(inp, out))
})

test_that("pam_filter_one: 24-bit WAV output selects pcm_s24le codec", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  sr <- 8000L; n <- sr
  inp <- tempfile(fileext = ".wav")
  out <- tempfile(fileext = ".wav")
  # Write a 16-bit wave (ffmpeg will upsample to 24-bit based on codec_args)
  tuneR::writeWave(tuneR::Wave(left = as.integer(rep(0L, n)), samp.rate = sr, bit = 16L), inp)
  res <- pamflow:::pam_filter_one(
    list(input = inp, output = out, bits = 24L),
    pam_highpass_filter_string(250, 4),
    "ffmpeg"
  )
  expect_true(res$ok)
  unlink(c(inp, out))
})

# ── pam_filter_batch: ok/verified columns, bad-output deletion ────────────────

test_that("pam_filter_batch: verified column is set and bad outputs deleted", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  sr <- 8000L; dur <- 1L
  wav <- tuneR::Wave(left = as.integer(rep(0L, sr * dur)), samp.rate = sr, bit = 16L)
  inp <- tempfile(fileext = ".wav")
  tuneR::writeWave(wav, inp)
  out <- tempfile(fileext = ".wav")

  batch <- data.table::data.table(
    rel     = "test.wav",
    input   = inp,
    output  = out,
    bits    = 16L,
    exp_dur = dur,
    exp_sr  = sr,
    exp_ch  = 1L,
    size    = file.size(inp)
  )

  fc <- list(ffmpeg_path = "ffmpeg", duration_tolerance_s = 0.5)
  fn <- pamflow:::pam_filter_one
  environment(fn) <- globalenv()

  result <- pamflow:::pam_filter_batch(batch, fn, pam_highpass_filter_string(250, 4), fc)
  expect_true("ok" %in% names(result))
  expect_true("verified" %in% names(result))
  expect_true("message" %in% names(result))
  # A good file should be verified
  expect_true(result$verified[1])
  unlink(c(inp, out))
})

test_that("pam_filter_batch: failed item has ok=FALSE and verified=FALSE", {
  skip_if(!nzchar(unname(Sys.which("ffmpeg"))), "ffmpeg not installed")
  out <- tempfile(fileext = ".wav")
  batch <- data.table::data.table(
    rel     = "missing.wav",
    input   = "definitely_does_not_exist.wav",
    output  = out,
    bits    = 16L,
    exp_dur = 1,
    exp_sr  = 8000L,
    exp_ch  = 1L,
    size    = 0L
  )
  fc <- list(ffmpeg_path = "ffmpeg", duration_tolerance_s = 0.5)
  fn <- pamflow:::pam_filter_one
  environment(fn) <- globalenv()
  result <- pamflow:::pam_filter_batch(batch, fn, pam_highpass_filter_string(250, 4), fc)
  expect_false(result$ok[1])
  expect_false(result$verified[1])
})

# ── pam_filter_batch with a stub worker (no ffmpeg required) ──────────────────

stub_filter_fn <- function(item, filter, ffmpeg = "ffmpeg") {
  dir.create(dirname(item$output), recursive = TRUE, showWarnings = FALSE)
  tuneR::writeWave(
    tuneR::Wave(left = as.integer(rep(0L, 8000)), samp.rate = 8000L, bit = 16L),
    item$output
  )
  list(ok = TRUE, message = "")
}

make_stub_batch <- function(out, exp_sr = 8000L) {
  data.table::data.table(
    rel = "a.wav", input = "unused.wav", output = out, bits = 16L,
    exp_dur = 1, exp_sr = exp_sr, exp_ch = 1L, size = 0L
  )
}

test_that("pam_filter_batch (stub): matching output is verified and kept", {
  out <- withr::local_tempfile(fileext = ".wav")
  fc <- list(ffmpeg_path = "ffmpeg", duration_tolerance_s = 0.5)
  res <- pamflow:::pam_filter_batch(make_stub_batch(out), stub_filter_fn, "f", fc)
  expect_true(res$ok)
  expect_true(res$verified)
  expect_true(file.exists(out))
})

test_that("pam_filter_batch (stub): sample-rate mismatch deletes output and flags message", {
  out <- withr::local_tempfile(fileext = ".wav")
  fc <- list(ffmpeg_path = "ffmpeg", duration_tolerance_s = 0.5)
  res <- pamflow:::pam_filter_batch(make_stub_batch(out, exp_sr = 16000L), stub_filter_fn, "f", fc)
  expect_true(res$ok)
  expect_false(res$verified)
  expect_match(res$message, "failed verification")
  expect_false(file.exists(out))
})

test_that("pam_filter_batch (stub): worker failure yields ok = FALSE, verified = FALSE", {
  out <- withr::local_tempfile(fileext = ".wav")
  fc <- list(ffmpeg_path = "ffmpeg", duration_tolerance_s = 0.5)
  failing <- function(item, filter, ffmpeg) list(ok = FALSE, message = "ffmpeg died")
  res <- pamflow:::pam_filter_batch(make_stub_batch(out), failing, "f", fc)
  expect_false(res$ok)
  expect_false(res$verified)
  expect_equal(res$message, "ffmpeg died")
})

# ── pam_filter_audio orchestration (ffmpeg check and worker stubbed) ──────────

make_filter_project <- function(tmp, n = 3L) {
  aud <- file.path(tmp, "std", "G1")
  dir.create(aud, recursive = TRUE)
  dir.create(file.path(tmp, "meta"), recursive = TRUE)
  paths <- file.path(aud, paste0("r", seq_len(n), ".wav"))
  for (p in paths) {
    tuneR::writeWave(tuneR::Wave(left = as.integer(rep(0L, 8000)), samp.rate = 8000L, bit = 16L), p)
  }
  master <- data.table::data.table(
    file_path = paths, duration_s = 1, sample_rate = 8000L, channels = 1L,
    bits = 16L, file_size_b = file.size(paths),
    qc_pass = c(rep(TRUE, n - 1L), FALSE)
  )
  cfg <- list(
    paths = list(logs = file.path(tmp, "logs"), metadata = file.path(tmp, "meta"),
                 audio_standardized = file.path(tmp, "std"),
                 filtered = file.path(tmp, "filtered")),
    filter = list(enabled = TRUE, highpass_hz = 250, order = 4L, ffmpeg_path = "ffmpeg",
                  chunk_size = 1L, workers = 1L, duration_tolerance_s = 0.5)
  )
  list(cfg = cfg, master = master)
}

# Self-contained: pam_filter_audio re-parents the worker to globalenv()
stub_filter_worker <- function(item, filter, ffmpeg = "ffmpeg") {
  dir.create(dirname(item$output), recursive = TRUE, showWarnings = FALSE)
  tuneR::writeWave(
    tuneR::Wave(left = as.integer(rep(0L, 8000)), samp.rate = 8000L, bit = 16L),
    item$output
  )
  list(ok = TRUE, message = "")
}

test_that("pam_filter_audio: disabled filter returns NULL without work", {
  cfg <- list(paths = list(logs = withr::local_tempdir()), filter = list(enabled = FALSE))
  expect_null(suppressMessages(pam_filter_audio(cfg)))
})

test_that("pam_filter_audio: errors when master table is absent", {
  skip_if_not_installed("tuneR")
  tmp <- withr::local_tempdir()
  proj <- make_filter_project(tmp)
  testthat::local_mocked_bindings(pam_check_ffmpeg = function(...) "ffmpeg stub", .package = "pamflow")
  expect_error(suppressMessages(pam_filter_audio(proj$cfg)), "audio_master.csv not found")
})

test_that("pam_filter_audio: filters only qc_pass files, then resumes with nothing pending", {
  skip_if_not_installed("tuneR")
  tmp <- withr::local_tempdir()
  proj <- make_filter_project(tmp)
  testthat::local_mocked_bindings(
    pam_check_ffmpeg = function(...) "ffmpeg stub",
    pam_filter_one = stub_filter_worker,
    .package = "pamflow"
  )
  res <- suppressMessages(pam_filter_audio(proj$cfg, master = proj$master))
  expect_equal(res$n_pending, 2L)
  expect_equal(res$n_ok, 2L)
  expect_equal(res$n_failed, 0L)
  expect_true(file.exists(file.path(tmp, "filtered", "G1", "r1.wav")))
  expect_false(file.exists(file.path(tmp, "filtered", "G1", "r3.wav")))
  expect_true(file.exists(res$results_file))
  expect_equal(length(readLines(file.path(tmp, "meta", "02_filter.done"))), 2L)

  res2 <- suppressMessages(pam_filter_audio(proj$cfg, master = proj$master))
  expect_equal(res2$n_pending, 0L)

  res3 <- suppressMessages(pam_filter_audio(proj$cfg, master = proj$master, force = TRUE))
  expect_equal(res3$n_ok, 2L)
})

test_that("pam_filter_audio: re-filters files whose output vanished", {
  skip_if_not_installed("tuneR")
  tmp <- withr::local_tempdir()
  proj <- make_filter_project(tmp)
  testthat::local_mocked_bindings(
    pam_check_ffmpeg = function(...) "ffmpeg stub",
    pam_filter_one = stub_filter_worker,
    .package = "pamflow"
  )
  suppressMessages(pam_filter_audio(proj$cfg, master = proj$master))
  unlink(file.path(tmp, "filtered", "G1", "r1.wav"))
  res <- suppressMessages(pam_filter_audio(proj$cfg, master = proj$master))
  expect_equal(res$n_pending, 1L)
  expect_equal(res$n_ok, 1L)
})
