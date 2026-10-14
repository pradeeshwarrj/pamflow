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
