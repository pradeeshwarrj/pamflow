test_that("audio extension and pattern helpers work correctly", {
  expect_equal(pam_audio_exts(), c("wav", "flac"))

  pattern <- pam_audio_pattern()
  expect_true(grepl(pattern, "file.wav"))
  expect_true(grepl(pattern, "file.WAV"))
  expect_true(grepl(pattern, "file.flac"))
  expect_true(grepl(pattern, "file.FLAC"))
  expect_false(grepl(pattern, "file.mp3"))
  expect_false(grepl(pattern, "file.csv"))

  expect_true(pam_is_flac("audio.flac"))
  expect_true(pam_is_flac("path/to/audio.FLAC"))
  expect_false(pam_is_flac("audio.wav"))
})

test_that("pam_list_audio finds both WAV and FLAC files", {
  tmp_dir <- testthat::test_path("tmp_audio_list")
  dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  file.create(file.path(tmp_dir, "test1.wav"))
  file.create(file.path(tmp_dir, "test2.flac"))
  file.create(file.path(tmp_dir, "test3.txt"))

  found <- pam_list_audio(tmp_dir)
  expect_equal(length(found), 2)
  expect_true(any(grepl("test1\\.wav$", found)))
  expect_true(any(grepl("test2\\.flac$", found)))
})

test_that("pam_audio_info reads WAV metadata and handles non-existent/corrupted files", {
  # Generate synthetic WAV
  tmp_wav <- tempfile(fileext = ".wav")
  on.exit(unlink(tmp_wav), add = TRUE)

  sine_wave <- tuneR::sine(440, duration = 1, xunit = "time")
  tuneR::writeWave(sine_wave, tmp_wav)

  info <- pam_audio_info(c(tmp_wav, "non_existent.wav"))

  expect_s3_class(info, "data.table")
  expect_equal(nrow(info), 2)

  # Valid WAV file assertions
  expect_true(info$readable[1])
  expect_equal(info$sample_rate[1], 44100)
  expect_equal(info$channels[1], 1)
  expect_equal(round(info$duration_s[1]), 1)

  # Missing file assertions
  expect_false(info$readable[2])
  expect_true(is.na(info$duration_s[2]))
})

test_that("pam_read_audio and pam_cut_audio work on WAV files", {
  tmp_wav <- tempfile(fileext = ".wav")
  tmp_cut <- tempfile(fileext = ".wav")
  on.exit(unlink(c(tmp_wav, tmp_cut)), add = TRUE)

  sine_wave <- tuneR::sine(440, duration = 2, xunit = "time")
  tuneR::writeWave(sine_wave, tmp_wav)

  # Read full audio
  w <- pam_read_audio(tmp_wav)
  expect_s4_class(w, "Wave")
  expect_equal(w@samp.rate, 44100)

  # Cut audio sub-segment (0.5s to 1.5s)
  pam_cut_audio(tmp_wav, tmp_cut, from = 0.5, to = 1.5)
  expect_true(file.exists(tmp_cut))

  w_cut <- pam_read_audio(tmp_cut)
  expect_equal(round(length(w_cut@left) / w_cut@samp.rate, 1), 1.0)
})

test_that("FLAC read/info/cut utilities work if av package is available", {
  skip_if_not_installed("av")

  tmp_wav <- tempfile(fileext = ".wav")
  tmp_flac <- tempfile(fileext = ".flac")
  tmp_flac_cut <- tempfile(fileext = ".flac")
  on.exit(unlink(c(tmp_wav, tmp_flac, tmp_flac_cut)), add = TRUE)

  # Create synthetic WAV and convert to FLAC
  sine_wave <- tuneR::sine(440, duration = 2, xunit = "time")
  tuneR::writeWave(sine_wave, tmp_wav)
  av::av_audio_convert(tmp_wav, tmp_flac, format = "flac", verbose = FALSE)

  # Test pam_audio_info on FLAC
  info <- pam_audio_info(tmp_flac)
  expect_true(info$readable)
  expect_equal(info$sample_rate, 44100)
  expect_equal(round(info$duration_s), 2)

  # Test pam_read_audio on FLAC
  w <- pam_read_audio(tmp_flac)
  expect_s4_class(w, "Wave")
  expect_equal(w@samp.rate, 44100)

  # Test pam_cut_audio on FLAC -> FLAC
  pam_cut_audio(tmp_flac, tmp_flac_cut, from = 0.5, to = 1.5)
  expect_true(file.exists(tmp_flac_cut))
  expect_true(pam_is_flac(tmp_flac_cut))

  info_cut <- pam_audio_info(tmp_flac_cut)
  expect_true(info_cut$readable)
  expect_equal(round(info_cut$duration_s, 1), 1.0)
})
