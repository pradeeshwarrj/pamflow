test_that("Hill numbers follow their definitions", {
  hill <- pamflow:::pam_hill_numbers
  equal <- hill(c(5, 5, 5, 5), q = c(0, 1, 2))
  expect_equal(unname(equal), c(4, 4, 4))                  # equal abundances: every order gives S
  expect_named(equal, c("q0", "q1", "q2"))
  a <- c(8, 1, 1)
  p <- a / sum(a)
  got <- hill(a, q = c(0, 1, 2, 0.5))
  expect_equal(unname(got["q0"]), 3)
  expect_equal(unname(got["q1"]), exp(-sum(p * log(p))))
  expect_equal(unname(got["q2"]), 1 / sum(p^2))
  expect_equal(unname(got["q0.5"]), sum(p^0.5)^2)
  expect_true(got[["q0"]] >= got[["q1"]] && got[["q1"]] >= got[["q2"]])
  expect_equal(unname(hill(c(8, 0, 1, 1), 0)), 3)          # zeros are ignored
  expect_equal(unname(hill(numeric(), c(0, 1))), c(0, NA))   # empty community
  expect_error(hill(1, q = -1), "q")
  expect_error(hill(1, q = NA_real_), "q")
})

# three sites: species A at sites 1 and 2, B at site 1, C at site 3
make_incidence <- function() {
  matrix(c(TRUE, TRUE, FALSE,    # A
           TRUE, FALSE, FALSE,   # B
           FALSE, FALSE, TRUE),  # C
         nrow = 3, dimnames = list(paste0("s", 1:3), c("A", "B", "C")))
}

test_that("rarefaction gives the exact expected species count for n sites", {
  acc <- pamflow:::pam_rarefy_sites(make_incidence())
  expect_equal(acc$n_sites, 1:3)
  expect_equal(acc$richness, c(4 / 3, 7 / 3, 3))           # worked out by listing the site combinations
  expect_true(all(diff(acc$richness) > 0))
  expect_equal(nrow(pamflow:::pam_rarefy_sites(make_incidence()[0, , drop = FALSE])), 0L)
  one <- pamflow:::pam_rarefy_sites(make_incidence()[1, , drop = FALSE])
  expect_equal(one$richness, 2)
})

test_that("Chao2 uses the species found in one and two sites", {
  inc <- matrix(FALSE, nrow = 4, ncol = 4, dimnames = list(NULL, paste0("sp", 1:4)))
  inc[, 1] <- TRUE            # in all 4 sites
  inc[1, 2] <- TRUE           # singleton
  inc[2, 3] <- TRUE           # singleton
  inc[1:2, 4] <- TRUE         # doubleton
  est <- pamflow:::pam_chao2(inc)
  expect_equal(est$observed, 4L)
  expect_equal(est$singletons, 2L)
  expect_equal(est$doubletons, 1L)
  expect_equal(est$chao2, 4 + (3 / 4) * 2^2 / (2 * 1))     # 5.5
  expect_equal(est$completeness, 4 / 5.5)
  # no doubletons: bias-corrected form
  inc2 <- inc[, 1:3]
  expect_equal(pamflow:::pam_chao2(inc2)$chao2, 3 + (3 / 4) * 2 * 1 / 2)
  none <- pamflow:::pam_chao2(inc[0, , drop = FALSE])
  expect_equal(none$n_sites, 0L)
  expect_true(is.na(none$chao2))
})

make_richness_example <- function(env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  list(ex = ex, proc = proc)
}

test_that("richness tables of the example project are consistent", {
  r <- make_richness_example()
  rich <- suppressMessages(pam_richness(r$ex$cfg))
  expect_s3_class(rich, "pam_richness")
  expect_named(rich, c("occasions", "sites", "accumulation", "estimates", "settings"))
  occ <- rich$occasions
  expect_equal(nrow(occ), 2L)                              # one surveyed day per site
  expect_true(all(occ$sufficient))
  expect_equal(sum(occ$n_events), nrow(r$proc$clean))
  ok <- occ[richness > 0]
  expect_true(all(ok$hill_q1 <= ok$richness + 1e-9 & ok$hill_q2 <= ok$hill_q1 + 1e-9))
  sites <- rich$sites
  expect_equal(sort(sites$site_id), c("G0059", "G0110"))
  expect_equal(sites$n_occasions_surveyed, c(1L, 1L))
  # with one occasion per site the site table equals the occasion table
  merged <- merge(occ, sites, by = "site_id")
  expect_equal(merged$richness.x, merged$richness.y)
  expect_equal(merged$n_events.x, merged$n_events.y)
  # accumulation ends at the observed richness
  acc <- rich$accumulation
  expect_equal(acc$n_sites, 1:2)
  expect_equal(acc$richness[2], rich$estimates$observed)
  expect_equal(rich$estimates$n_sites, 2L)
  expect_true(rich$estimates$chao2 >= rich$estimates$observed)
  expect_equal(rich$settings$min_events, 1L)
  expect_equal(rich$settings$q, c(1, 2))
})

test_that("presence weighting makes every Hill number equal to the richness", {
  r <- make_richness_example()
  rich <- suppressMessages(pam_richness(r$ex$cfg, abundance = "presence", q = c(1, 2)))
  ok <- rich$occasions[richness > 0]
  expect_equal(ok$hill_q1, as.numeric(ok$richness))
  expect_equal(ok$hill_q2, as.numeric(ok$richness))
})

test_that("min_events removes species with too few events and empty bins are handled", {
  r <- make_richness_example()
  base <- suppressMessages(pam_richness(r$ex$cfg))
  strict <- suppressMessages(pam_richness(r$ex$cfg, min_events = 2))
  expect_true(all(strict$occasions$richness <= base$occasions$richness))
  expect_true(all(strict$occasions$n_events <= base$occasions$n_events))
  none <- suppressMessages(pam_richness(r$ex$cfg, min_events = 1000))
  expect_equal(unique(none$occasions$richness), 0L)
  expect_true(all(is.na(none$occasions$hill_q1)))
  expect_equal(none$sites$richness, c(0L, 0L))
  expect_equal(none$estimates$observed, 0L)
  expect_equal(nrow(none$accumulation), 2L)
  expect_equal(unique(none$accumulation$richness), 0)
})

test_that("bins, thresholds, species and effort settings behave as documented", {
  r <- make_richness_example()
  two <- suppressMessages(pam_richness(r$ex$cfg, bin_days = 2))
  expect_equal(nrow(two$occasions), 2L)
  expect_equal(unique(two$occasions$bin_start), as.Date("2026-04-05"))
  base <- suppressMessages(pam_richness(r$ex$cfg))
  thr <- data.frame(scientific_name = unique(r$proc$clean$scientific_name), threshold = 1)
  strict <- suppressMessages(pam_richness(r$ex$cfg, thresholds = thr))
  expect_equal(sum(strict$occasions$n_events), sum(r$proc$clean$confidence >= 1))
  one <- r$proc$clean$scientific_name[1]
  sel <- suppressMessages(pam_richness(r$ex$cfg, species = one))
  expect_true(all(sel$occasions$richness <= 1L))
  expect_warning(short <- suppressMessages(pam_richness(r$ex$cfg, min_effort_hours = 1)),
                 "No surveyed sites")
  expect_equal(nrow(short$sites), 0L)
  expect_equal(nrow(short$accumulation), 0L)
  expect_false(any(short$occasions$sufficient))
  other_q <- suppressMessages(pam_richness(r$ex$cfg, q = c(3, 0.5, 0)))$occasions
  expect_equal(grep("^hill_", names(other_q), value = TRUE), c("hill_q0.5", "hill_q3"))
})

test_that("pam_richness validates its arguments and writes only on request", {
  r <- make_richness_example()
  expect_error(pam_richness(r$ex$cfg, min_events = 0), "min_events")
  expect_error(pam_richness(r$ex$cfg, min_events = 1.5), "min_events")
  expect_error(pam_richness(r$ex$cfg, q = -1), "`q`")
  expect_error(pam_richness(r$ex$cfg, abundance = "x"), "should be one of")
  expect_error(pam_richness(r$ex$cfg, bin_days = 0), "bin_days")
  dir <- file.path(r$ex$cfg$paths$outputs, "run01")
  suppressMessages(pam_richness(r$ex$cfg))
  expect_false(file.exists(file.path(dir, "richness_sites.csv")))
  rich <- suppressMessages(pam_richness(r$ex$cfg, write = TRUE))
  files <- c("richness_occasions.csv", "richness_sites.csv", "species_accumulation.csv",
             "richness_estimates.csv")
  expect_true(all(file.exists(file.path(dir, files))))
  expect_equal(nrow(data.table::fread(file.path(dir, "richness_sites.csv"))), nrow(rich$sites))
})

test_that("pam_plot_richness draws both plots and refuses other input", {
  r <- make_richness_example()
  rich <- suppressMessages(pam_richness(r$ex$cfg))
  expect_s3_class(pam_plot_richness(rich), "ggplot")
  expect_s3_class(pam_plot_richness(rich, "sites"), "ggplot")
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(pam_plot_richness(rich))))
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(pam_plot_richness(rich, "sites"))))
  expect_false(is.factor(rich$sites$site_id))                 # plotting does not change the result
  expect_error(pam_plot_richness(list()), "pam_richness")
  expect_error(pam_plot_richness(rich, "map"), "should be one of")
})
