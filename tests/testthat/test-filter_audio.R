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
