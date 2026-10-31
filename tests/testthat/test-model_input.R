# Simulated counts: 40 sites x 4 occasions, a site covariate and recording effort
sim_history <- function(n_sites = 40, n_occ = 4, seed = 42) {
  withr::local_seed(seed, .local_envir = parent.frame())
  elev <- rnorm(n_sites)
  abundance <- rpois(n_sites, exp(1 + 0.5 * elev))
  y <- matrix(rbinom(n_sites * n_occ, rep(abundance, n_occ), 0.4), nrow = n_sites)
  rownames(y) <- paste0("s", seq_len(n_sites))
  effort <- matrix(runif(n_sites * n_occ, 12, 24), nrow = n_sites)
  pam_as_count_history(y, site_covariates = data.frame(elev = elev), effort = effort,
                       species = "Sim species")
}

test_that("covariates are standardised and character covariates become factors", {
  site <- data.frame(site_id = c("a", "b", "c", "d"), elev = c(1, 2, 3, 4), flat = c(5, 5, 5, 5),
                     habitat = c("x", "y", "x", "y"), stringsAsFactors = FALSE)
  obs <- list(effort = matrix(c(10, 20, NA, 30), 2))
  out <- pamflow:::pam_scale_covariates(site, obs, standardize = TRUE)
  expect_equal(mean(out$site$elev), 0)
  expect_equal(stats::sd(out$site$elev), 1)
  expect_equal(out$site$flat, c(0, 0, 0, 0))               # constant: centred only
  expect_s3_class(out$site$habitat, "factor")
  expect_equal(out$site$site_id, site$site_id)
  expect_equal(mean(out$obs$effort, na.rm = TRUE), 0)
  expect_true(is.na(out$obs$effort[1, 2]))
  expect_setequal(out$scaling$name, c("elev", "flat", "effort"))
  expect_equal(out$scaling[name == "elev"]$center, 2.5)
  raw <- pamflow:::pam_scale_covariates(site, obs, standardize = FALSE)
  expect_equal(raw$site$elev, site$elev)
  expect_equal(raw$obs, obs)
  expect_equal(nrow(raw$scaling), 0L)
  expect_s3_class(raw$site$habitat, "factor")
})

test_that("the input has the pieces the models need, shaped consistently", {
  h <- sim_history()
  x <- pam_model_input(h)
  expect_s3_class(x, "pam_model_input")
  expect_named(x, c("y", "siteCovs", "obsCovs", "site_ids", "species", "count", "binary", "scaling"))
  expect_identical(x$y, h$y)
  expect_true(is.integer(x$y))
  expect_equal(names(x$siteCovs), "elev")
  expect_equal(rownames(x$siteCovs), rownames(h$y))
  expect_equal(x$siteCovs$elev, h$site_covariates$elev)    # not standardised by default
  expect_named(x$obsCovs, c("effort", "day"))
  for (m in x$obsCovs) expect_equal(dim(m), dim(x$y))
  expect_equal(x$site_ids, rownames(h$y))
  expect_equal(x$species, "Sim species")
  expect_false(x$binary)
  expect_equal(nrow(x$scaling), 0L)
  expect_output(print(x), "model input")
})

test_that("binary = TRUE gives detection and non-detection and keeps the NA", {
  h <- sim_history()
  y <- h$y
  y[2, 3] <- NA
  h2 <- pam_as_count_history(y, site_covariates = h$site_covariates)
  x <- pam_model_input(h2, binary = TRUE)
  expect_true(x$binary)
  expect_true(all(x$y %in% c(0L, 1L, NA)))
  expect_equal(unname(is.na(x$y)), unname(is.na(y)))
  expect_equal(x$y[!is.na(y)], as.integer(y[!is.na(y)] > 0))
  expect_equal(dim(x$y), dim(y))
})

test_that("standardising covariates records the centre and scale", {
  h <- sim_history()
  x <- pam_model_input(h, standardize = TRUE)
  expect_equal(mean(x$siteCovs$elev), 0)
  expect_equal(stats::sd(x$siteCovs$elev), 1)
  expect_setequal(x$scaling$name, c("elev", "effort", "day"))
  expect_equal(x$scaling[name == "elev"]$center, mean(h$site_covariates$elev))
  expect_equal(mean(x$obsCovs$effort), 0)
  expect_identical(x$y, h$y)                                # the response is never scaled
})

test_that("sites that were never surveyed are left out of every piece", {
  h <- sim_history(n_sites = 6)
  y <- h$y
  y[3, ] <- NA
  h2 <- pam_as_count_history(y, site_covariates = h$site_covariates, effort = h$effort)
  expect_message(x <- pam_model_input(h2), "Left out 1 site")
  expect_equal(nrow(x$y), 5L)
  expect_false("s3" %in% rownames(x$y))
  expect_equal(nrow(x$siteCovs), 5L)
  expect_equal(x$site_ids, setdiff(rownames(y), "s3"))
  for (m in x$obsCovs) expect_equal(nrow(m), 5L)
  keep_all <- pam_model_input(h2, drop_unsurveyed = FALSE)
  expect_equal(nrow(keep_all$y), 6L)
  none <- pam_as_count_history(matrix(NA_integer_, 2, 2))
  expect_error(suppressMessages(pam_model_input(none)), "no surveyed sites")
})

test_that("histories without covariates or effort give NULL pieces, and missing covariates warn", {
  y <- matrix(c(1, 0, 2, 3), 2, dimnames = list(c("a", "b"), NULL))
  x <- pam_model_input(pam_as_count_history(y))
  expect_null(x$siteCovs)
  expect_named(x$obsCovs, "day")                            # day is always available
  with_na <- pam_as_count_history(y, site_covariates = data.frame(canopy = c(NA, 0.3)))
  expect_warning(pam_model_input(with_na), "cannot use them\\): canopy")
})

test_that("the pieces can be written to a folder", {
  h <- sim_history(n_sites = 5)
  dir <- file.path(withr::local_tempdir(), "unmarked", "sim")
  expect_false(dir.exists(dir))
  pam_model_input(h)
  expect_false(dir.exists(dir))                              # nothing is written by default
  x <- pam_model_input(h, dir = dir)
  expect_setequal(list.files(dir), c("y.csv", "site_covariates.csv", "effort.csv", "day.csv"))
  y_file <- data.table::fread(file.path(dir, "y.csv"), header = TRUE)   # column names look like numbers
  expect_equal(y_file$site_id, rownames(x$y))
  expect_equal(ncol(y_file), ncol(x$y) + 1L)
  counts <- as.matrix(y_file[, setdiff(names(y_file), "site_id"), with = FALSE])
  expect_equal(counts, unname(x$y), ignore_attr = TRUE)
  cov_file <- data.table::fread(file.path(dir, "site_covariates.csv"))
  expect_equal(cov_file$elev, x$siteCovs$elev)
})

test_that("pam_model_input checks its arguments", {
  h <- sim_history(n_sites = 5)
  expect_error(pam_model_input(list()), "pam_count_history")
  expect_error(pam_model_input(h, binary = NA), "TRUE or FALSE")
  expect_error(pam_model_input(h, standardize = "yes"), "TRUE or FALSE")
  expect_error(pam_model_input(h, drop_unsurveyed = c(TRUE, FALSE)), "TRUE or FALSE")
  expect_error(pam_model_input(h, dir = 1), "single folder")
})

test_that("a project's count history turns into model input", {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE))
  suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  sp <- unique(proc$clean$scientific_name)[1]
  h <- suppressMessages(pam_count_history(ex$cfg, species = sp, bin_days = 2,
                                          site_covariates = data.frame(
                                            site_id = c("G0059", "G0110"), elev = c(59, 110))))
  x <- pam_model_input(h)
  expect_equal(dim(x$y), c(2L, 1L))
  expect_equal(x$siteCovs$elev, c(59, 110))
  expect_equal(sum(x$y), sum(proc$clean$scientific_name == sp))
  expect_named(x$obsCovs, c("effort", "day"))
})

test_that("the input is accepted by unmarked's data frames", {
  skip_if_not_installed("unmarked")
  skip_on_cran()
  h <- sim_history()
  counts <- pam_model_input(h)
  umf <- unmarked::unmarkedFramePCount(y = counts$y, siteCovs = counts$siteCovs,
                                       obsCovs = counts$obsCovs)
  expect_equal(unmarked::numSites(umf), 40L)
  expect_equal(unmarked::obsNum(umf), 4L)
  binary <- pam_model_input(h, binary = TRUE, standardize = TRUE)
  umf2 <- unmarked::unmarkedFrameOccu(y = binary$y, siteCovs = binary$siteCovs,
                                      obsCovs = binary$obsCovs)
  expect_equal(unmarked::numSites(umf2), 40L)
})
