test_that("pam_soundscape_one creates valid output structure", {
  skip_if_not_installed("seewave")
  skip_if_not_installed("soundecology")
  skip_if_not_installed("tuneR")

  tmp_wav <- tempfile(fileext = ".wav")
  on.exit(unlink(tmp_wav), add = TRUE)

  sample_rate <- 44100
  # 10 seconds duration for robust soundecology calculation
  t <- seq(0, 10, length.out = sample_rate * 10)
  sine <- 0.5 * sin(2 * pi * 1500 * t) + 0.5 * sin(2 * pi * 3000 * t)
  wave <- tuneR::Wave(left = round(sine * 32767), samp.rate = sample_rate, bit = 16)
  tuneR::writeWave(wave, tmp_wav)

  res <- pam_soundscape_one(tmp_wav, low_stop_hz = 100)

  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 1L)
  expect_true(all(c("ACI", "ADI", "AEve", "Bio", "H", "M", "NDSI") %in% names(res)))
  expect_equal(res$status, "ok")
})
