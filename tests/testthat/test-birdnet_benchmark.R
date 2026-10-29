test_that("benchmark summary computes throughput, speedup and full-archive estimate", {
  timings <- data.frame(workers = c(4L, 1L, 2L),
                        n_done = c(8L, 8L, 8L), n_failed = c(0L, 0L, 0L),
                        elapsed_s = c(900, 3600, 1800))
  s <- pam_bench_summarise(timings, n_total = 6000)
  expect_equal(s$workers, c(1L, 2L, 4L))                    # sorted
  expect_equal(s$files_per_hour, c(8, 16, 32))
  expect_equal(s$speedup, c(1, 2, 4))
  expect_equal(s$efficiency, c(1, 1, 1))
  expect_equal(s$est_hours_full, c(750, 375, 187.5))
})

test_that("efficiency drops when scaling is sub-linear", {
  timings <- data.frame(workers = c(1L, 4L), n_done = c(8L, 8L), n_failed = 0L,
                        elapsed_s = c(3600, 1800))
  s <- pam_bench_summarise(timings)
  expect_equal(s$speedup, c(1, 2))
  expect_equal(s$efficiency, c(1, 0.5))
  expect_false("est_hours_full" %in% names(s))             # no n_total given
})

test_that("failed files still count toward elapsed throughput", {
  timings <- data.frame(workers = 1L, n_done = 6L, n_failed = 2L, elapsed_s = 3600)
  expect_equal(pam_bench_summarise(timings)$files_per_hour, 8)
})

test_that("benchmark aborts clearly when every run fails", {
  skip_if_not_installed("withr")
  tmp <- withr::local_tempdir()
  cfg <- list(paths = list(logs = file.path(tmp, "logs"), metadata = tmp,
                           detections = file.path(tmp, "det")),
              birdnet = list(workers = 1L, run_id = "x"))
  testthat::local_mocked_bindings(pam_detect = function(...) stop("boom"))
  expect_error(suppressMessages(pam_birdnet_benchmark(cfg, workers = 1L, n_files = 2L)),
               "Every benchmark run failed")
})
