# Synthetic validation metrics: two precision curves and two species with too little data
make_metrics <- function() {
  band_edges <- c(0.3, 0.4, 0.5, 0.7)
  thr <- function(sp, prec, cov = 1, n = c(100, 80, 60, 30)) {
    data.table::data.table(scientific_name = sp, min_confidence = band_edges,
                           n_events = n, coverage = cov, precision_est = prec)
  }
  list(
    thresholds = data.table::rbindlist(list(
      thr("ALL", c(0.60, 0.70, 0.80, 0.90)),
      thr("Species a", c(0.70, 0.82, 0.93, 0.95)),   # best 0.95, within 0.05 from 0.5
      thr("Species b", c(0.50, 0.60, 0.70, 0.80)),
      thr("Species c", c(0.50, 0.60, 0.70, 0.80), cov = 0.2)   # never enough reviewed events
    )),
    cells = data.table::data.table(
      scientific_name = c("Species a", "Species b", "Species c"),
      n_judged = c(40L, 3L, 25L))
  )
}

test_that("the plateau rule picks the lowest confidence within tolerance of the species' best precision", {
  out <- pamflow:::pam_choose_thresholds(make_metrics(), tolerance = 0.05, min_judged = 10)
  a <- out[scientific_name == "Species a"]
  expect_equal(a$threshold, 0.5)
  expect_equal(a$method, "plateau")
  expect_equal(a$precision_est, 0.93)
  expect_equal(a$n_events_kept, 60L)
  expect_equal(a$n_judged, 40L)
})

test_that("a tolerance of 0 keeps only the best level and a wide tolerance keeps the lowest", {
  strict <- pamflow:::pam_choose_thresholds(make_metrics(), tolerance = 0, min_judged = 10)
  expect_equal(strict[scientific_name == "Species a"]$threshold, 0.7)
  loose <- pamflow:::pam_choose_thresholds(make_metrics(), tolerance = 1, min_judged = 10)
  expect_equal(loose[scientific_name == "Species a"]$threshold, 0.3)
})

test_that("species without enough judged samples or reviewed events get the default, with a reason", {
  out <- pamflow:::pam_choose_thresholds(make_metrics(), min_judged = 10, default = 0.6)
  b <- out[scientific_name == "Species b"]
  expect_equal(b$threshold, 0.6)
  expect_equal(b$method, "default")
  expect_match(b$reason, "only 3 judged")
  cc <- out[scientific_name == "Species c"]
  expect_equal(cc$method, "default")
  expect_match(cc$reason, "enough reviewed events")
  expect_false("ALL" %in% out$scientific_name)
})

test_that("manual thresholds override the estimate and can add species", {
  manual <- data.frame(scientific_name = c("Species a", "Species d"), threshold = c(0.8, 0.45))
  out <- pamflow:::pam_choose_thresholds(make_metrics(), min_judged = 10, manual = manual)
  expect_equal(out[scientific_name == "Species a"]$threshold, 0.8)
  expect_equal(out[scientific_name == "Species a"]$method, "manual")
  expect_equal(out[scientific_name == "Species d"]$threshold, 0.45)
  expect_equal(out$scientific_name, sort(out$scientific_name))
  expect_equal(sum(out$scientific_name == "Species a"), 1L)
})

test_that("bad arguments and bad threshold tables are refused", {
  m <- make_metrics()
  expect_error(pamflow:::pam_choose_thresholds(m, tolerance = 2), "tolerance")
  expect_error(pamflow:::pam_choose_thresholds(m, min_coverage = -1), "min_coverage")
  expect_error(pamflow:::pam_choose_thresholds(m, default = NA_real_), "default")
  expect_error(pamflow:::pam_choose_thresholds(m, min_judged = -1), "min_judged")
  expect_error(pamflow:::pam_read_thresholds(data.frame(a = 1), "x"), "scientific_name and threshold")
  expect_error(pamflow:::pam_read_thresholds(data.frame(scientific_name = "a", threshold = 2), "x"),
               "between 0 and 1")
  expect_error(pamflow:::pam_read_thresholds(data.frame(scientific_name = c("a", "a"),
                                                         threshold = c(0.1, 0.2)), "x"),
               "one threshold per species")
  expect_error(pamflow:::pam_read_thresholds(file.path(tempdir(), "no_such_file.csv")), "not found")
  expect_error(pamflow:::pam_read_thresholds(42), "data frame")
  expect_null(pamflow:::pam_read_thresholds(NULL))
})

test_that("pam_species_thresholds works on the example project, writes only on request, and feeds Stage 4", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 8))
  val_dir <- file.path(ex$cfg$paths$detections, "run01", "validation")
  results <- data.frame(sample_id = new$sample_id,
                        verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
                        true_species = NA_character_, note = "", reviewer = "test",
                        reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
  utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)

  thr <- suppressMessages(pam_species_thresholds(ex$cfg, min_judged = 1))
  expect_named(thr, c("scientific_name", "threshold", "method", "precision_est", "coverage",
                      "n_judged", "n_events_kept", "reason"))
  expect_true(all(thr$threshold >= 0 & thr$threshold <= 1))
  expect_true(all(thr$method %in% c("plateau", "default")))
  expect_false(file.exists(file.path(val_dir, "species_thresholds.csv")))

  thr2 <- suppressMessages(pam_species_thresholds(ex$cfg, min_judged = 1, write = TRUE))
  path <- file.path(val_dir, "species_thresholds.csv")
  expect_true(file.exists(path))
  expect_equal(data.table::fread(path)$scientific_name, thr2$scientific_name)

  # the file can be used as the Stage 4 species-threshold file
  ex$cfg$processing$species_thresholds_file <- path
  out <- suppressMessages(pam_process_detections(ex$cfg))
  chk <- merge(out$clean, thr2[, .(scientific_name, threshold)], by = "scientific_name")
  expect_true(all(chk$confidence >= chk$threshold))
})
