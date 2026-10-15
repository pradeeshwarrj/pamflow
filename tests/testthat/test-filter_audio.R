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
