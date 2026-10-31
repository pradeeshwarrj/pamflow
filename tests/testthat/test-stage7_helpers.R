make_stage7_example <- function(env = parent.frame()) {
  ex <- pam_example_project()
  withr::defer(unlink(ex$root, recursive = TRUE), envir = env)
  suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  list(ex = ex, proc = proc, labels = sort(unique(proc$clean$species)))
}

test_that("pam_count_histories builds one history per species on a shared grid", {
  r <- make_stage7_example()
  hists <- suppressMessages(pam_count_histories(r$ex$cfg))
  expect_s3_class(hists, "pam_count_histories")
  expect_equal(names(hists), r$labels)
  for (h in unclass(hists)) {
    expect_s3_class(h, "pam_count_history")
    expect_equal(dim(h$y), c(2L, 2L))
  }
  totals <- vapply(unclass(hists), function(h) sum(h$y, na.rm = TRUE), numeric(1))
  expect_equal(unname(totals), as.numeric(table(r$proc$clean$species)[r$labels]))
  expect_output(print(hists), sprintf("%d species", length(r$labels)))
  one <- suppressMessages(pam_count_history(r$ex$cfg, species = r$labels[1]))
  expect_identical(hists[[1]]$y, one$y)
  expect_identical(hists[[1]]$effort, one$effort)
})

test_that("pam_count_histories can select species, count recordings and attach covariates", {
  r <- make_stage7_example()
  first_name <- r$proc$clean$scientific_name[r$proc$clean$species == r$labels[1]][1]
  sel <- suppressMessages(pam_count_histories(r$ex$cfg, species = first_name))
  expect_equal(names(sel), r$labels[1])
  files <- suppressMessages(pam_count_histories(r$ex$cfg, count = "files"))
  events <- suppressMessages(pam_count_histories(r$ex$cfg))
  expect_equal(unclass(files)[[1]]$count, "files")
  expect_true(all(mapply(function(f, e) all(f$y <= e$y, na.rm = TRUE),
                         unclass(files), unclass(events))))
  cov <- data.frame(site_id = c("G0110", "G0059"), elev = c(110, 59))
  withcov <- suppressMessages(pam_count_histories(r$ex$cfg, site_covariates = cov))
  expect_equal(unclass(withcov)[[1]]$site_covariates$elev, c(59, 110))
})

test_that("min_total, thresholds and arguments of pam_count_histories are handled", {
  r <- make_stage7_example()
  expect_error(suppressMessages(pam_count_histories(r$ex$cfg, min_total = 1e6)), "No species has at least")
  thr <- data.frame(scientific_name = unique(r$proc$clean$scientific_name), threshold = 1)
  expect_error(suppressMessages(pam_count_histories(r$ex$cfg, thresholds = thr)), "No species has at least")
  kept <- suppressMessages(pam_count_histories(r$ex$cfg, thresholds = thr, min_total = 0))
  expect_equal(length(kept), length(r$labels))
  expect_error(pam_count_histories(r$ex$cfg, species = 1), "NULL or species names")
  expect_error(pam_count_histories(r$ex$cfg, min_total = -1), "min_total")
  expect_error(suppressMessages(pam_count_histories(r$ex$cfg, species = "no such species")), "No detections")
  expect_error(pam_count_histories(r$ex$cfg, count = "x"), "should be one of")
})

test_that("site covariates can be added later, by name, to one history or to many", {
  y <- matrix(c(0, 2, 5, 1, 0, 3), nrow = 3, dimnames = list(c("a", "b", "c"), NULL))
  h <- pam_as_count_history(y, species = "Sp")
  covs <- data.frame(site_id = c("c", "a", "b"), canopy = c(0.9, 0.2, 0.5))
  out <- pam_add_site_covariates(h, covs)
  expect_equal(out$site_covariates$site_id, c("a", "b", "c"))
  expect_equal(out$site_covariates$canopy, c(0.2, 0.5, 0.9))
  expect_error(pam_add_site_covariates(out, covs), "already present: canopy")
  again <- pam_add_site_covariates(out, data.frame(site_id = c("a", "b", "c"), canopy = 1:3), replace = TRUE)
  expect_equal(again$site_covariates$canopy, 1:3)
  expect_equal(names(again$site_covariates), c("site_id", "canopy"))
  both <- pam_add_site_covariates(out, data.frame(site_id = c("a", "b", "c"), slope = 4:6))
  expect_equal(names(both$site_covariates), c("site_id", "canopy", "slope"))
  many <- structure(list(one = h, two = h), class = c("pam_count_histories", "list"))
  added <- pam_add_site_covariates(many, covs)
  expect_s3_class(added, "pam_count_histories")
  expect_equal(unclass(added)$two$site_covariates$canopy, c(0.2, 0.5, 0.9))
  expect_error(pam_add_site_covariates(h, data.frame(site_id = c("a", "b"), z = 1:2)), "no row for 1 site")
  expect_error(pam_add_site_covariates(h, data.frame(site_id = c("a", "b", "c"))), "no covariate columns")
  expect_error(pam_add_site_covariates(list(), covs), "pam_count_history")
  expect_error(pam_add_site_covariates(h, covs, replace = NA), "replace")
})

test_that("several species become a species x site x occasion array", {
  r <- make_stage7_example()
  hists <- suppressMessages(pam_count_histories(r$ex$cfg))
  x <- pam_model_input(hists, binary = TRUE)
  expect_equal(dim(x$y), c(length(r$labels), 2L, 2L))
  expect_equal(dimnames(x$y)[[1]], r$labels)
  expect_equal(dimnames(x$y)[[2]], c("G0059", "G0110"))
  expect_equal(attr(x, "layout"), c("species", "site", "occasion"))
  expect_equal(x$species, r$labels)
  expect_true(all(x$y %in% c(0L, 1L, NA)))
  expect_identical(is.na(x$y[1, , ]), is.na(unclass(hists)[[1]]$y))
  expect_equal(dim(x$obsCovs$effort), c(2L, 2L))                  # shared by the species
  expect_no_error(pam_check_model_input(x))
  expect_output(print(x), "species")
  counts <- pam_model_input(hists)
  expect_equal(sum(counts$y, na.rm = TRUE), nrow(r$proc$clean))
  dir <- file.path(withr::local_tempdir(), "multi")
  pam_model_input(hists, dir = dir)
  long <- data.table::fread(file.path(dir, "y_long.csv"), header = TRUE)
  expect_named(long, c("species", "site", "occasion", "value"))
  expect_equal(nrow(long), length(counts$y))
  expect_true(file.exists(file.path(dir, "effort_long.csv")))
})

season_history <- function() {
  dates <- as.Date("2026-04-01") + 0:7
  y <- matrix(1:24, nrow = 3, dimnames = list(paste0("s", 1:3), as.character(dates)))
  pam_as_count_history(
    y, site_covariates = data.frame(canopy = c(0.1, 0.5, 0.9)), effort = matrix(10, 3, 8),
    occasions = data.frame(occasion = 1:8, bin_start = dates, bin_end = dates), species = "Sp")
}
two_seasons <- function() {
  data.frame(season = c("A", "B"), start = as.Date(c("2026-04-01", "2026-04-05")),
             end = as.Date(c("2026-04-04", "2026-04-08")))
}

test_that("occasions are grouped into seasons for multi-season models", {
  h <- season_history()
  x <- pam_model_input(h, seasons = two_seasons())
  expect_equal(x$num_primary, 2L)
  expect_equal(x$n_secondary, 4L)
  expect_equal(attr(x, "layout"), c("site", "season", "occasion"))
  expect_equal(unname(x$y), unname(h$y))                          # contiguous seasons keep the order
  expect_equal(colnames(x$y), paste(rep(c("A", "B"), each = 4), 1:4, sep = ":"))
  expect_equal(dim(x$y_array), c(3L, 2L, 4L))
  expect_equal(x$y_array["s2", "B", "3"], h$y["s2", 7])
  expect_equal(x$y_array["s3", "A", "1"], h$y["s3", 1])
  expect_equal(dim(x$obsCovs$effort), c(3L, 8L))
  expect_equal(dim(x$obsCovs_array$day), c(3L, 2L, 4L))
  expect_equal(x$obsCovs_array$day["s1", "B", ], c(`1` = 4, `2` = 5, `3` = 6, `4` = 7))
  expect_equal(x$seasons$n_occasions, c(4L, 4L))
  expect_equal(x$occasion_map$season, rep(c("A", "B"), each = 4))
  expect_equal(x$occasion_map$source_occasion, 1:8)
  expect_no_error(pam_check_model_input(x))
  expect_output(print(x), "seasons")
  expect_equal(unname(pam_model_input(h, binary = TRUE, seasons = two_seasons())$y_array[1, 1, ]), rep(1L, 4))
})

test_that("seasons with different numbers of occasions are padded, gaps stay, outside occasions go", {
  h <- season_history()
  uneven <- data.frame(season = c("A", "B"), start = as.Date(c("2026-04-01", "2026-04-04")),
                       end = as.Date(c("2026-04-03", "2026-04-08")))
  x <- pam_model_input(h, seasons = uneven)
  expect_equal(x$n_secondary, 5L)
  expect_true(all(is.na(x$y_array[, "A", c("4", "5")])))
  expect_equal(sum(!is.na(x$y_array)), 3 * 8)
  expect_no_error(pam_check_model_input(x))

  expect_message(y_out <- pam_model_input(h, seasons = two_seasons()[2, ]), "4 occasion\\(s\\) fall outside")
  expect_equal(y_out$num_primary, 1L)

  with_gap <- rbind(two_seasons(),
                    data.frame(season = "C", start = as.Date("2026-05-01"), end = as.Date("2026-05-10")))
  gap <- pam_model_input(h, seasons = with_gap)
  expect_equal(gap$num_primary, 3L)
  expect_true(all(is.na(gap$y_array[, "C", ])))
  expect_equal(gap$seasons$n_occasions, c(4L, 4L, 0L))
  expect_no_error(pam_check_model_input(gap))
})

test_that("season definitions are validated", {
  h <- season_history()
  expect_error(pam_model_input(h, seasons = data.frame(season = "A")), "columns season, start and end")
  bad_end <- data.frame(season = "A", start = as.Date("2026-04-05"), end = as.Date("2026-04-01"))
  expect_error(pam_model_input(h, seasons = bad_end), "not before the start")
  overlapping <- data.frame(season = c("A", "B"), start = as.Date(c("2026-04-01", "2026-04-04")),
                            end = as.Date(c("2026-04-05", "2026-04-08")))
  expect_error(pam_model_input(h, seasons = overlapping), "must not overlap")
  dup <- data.frame(season = c("A", "A"), start = as.Date(c("2026-04-01", "2026-04-05")),
                    end = as.Date(c("2026-04-02", "2026-04-06")))
  expect_error(pam_model_input(h, seasons = dup), "unique")
  nowhere <- data.frame(season = "A", start = as.Date("2027-01-01"), end = as.Date("2027-01-31"))
  expect_error(pam_model_input(h, seasons = nowhere), "No occasion falls")
  undated <- pam_as_count_history(h$y)
  expect_error(pam_model_input(undated, seasons = two_seasons()), "need dates")
})

test_that("seasonal covariates become yearly site covariates", {
  h <- season_history()
  cov <- data.frame(season = c("B", "A"), rain = c(20, 10), phase = c("wet", "dry"))
  x <- pam_model_input(h, seasons = two_seasons(), season_covariates = cov)
  expect_equal(nrow(x$yearlySiteCovs), 3L * 2L)
  expect_equal(x$yearlySiteCovs$rain, rep(c(10, 20), times = 3))   # sites first, seasons within site
  expect_equal(as.character(x$yearlySiteCovs$phase), rep(c("dry", "wet"), times = 3))
  expect_equal(unname(x$yearlySiteCovs_matrices$rain["s1", ]), c(10, 20))
  expect_equal(dim(x$yearlySiteCovs_matrices$rain), c(3L, 2L))
  expect_no_error(pam_check_model_input(x))
  std <- pam_model_input(h, seasons = two_seasons(), season_covariates = cov, standardize = TRUE)
  expect_true("rain" %in% std$scaling[source == "season"]$name)
  expect_equal(mean(std$yearlySiteCovs$rain), 0)
  expect_error(pam_model_input(h, season_covariates = cov), "needs `seasons`")
  expect_error(pam_model_input(h, seasons = two_seasons(), season_covariates = cov[1, ]), "no row for season")
  expect_error(pam_model_input(h, seasons = two_seasons(), season_covariates = data.frame(season = c("A", "A"))),
               "more than once")
  expect_error(pam_model_input(h, seasons = two_seasons(), season_covariates = data.frame(season = c("A", "B"))),
               "no covariate columns")
  expect_error(pam_model_input(h, seasons = two_seasons(), season_covariates = data.frame(rain = 1:2)),
               "`season` column")
})

test_that("several species and several seasons give a four-dimensional array", {
  h <- season_history()
  h2 <- h; h2$species <- "Sp two"; h2$y <- h$y * 2L
  many <- structure(list(a = h, b = h2), class = c("pam_count_histories", "list"))
  x <- pam_model_input(many, seasons = two_seasons())
  expect_null(x$y)
  expect_equal(dim(x$y_array), c(2L, 3L, 2L, 4L))
  expect_equal(x$y_array["Sp two", "s1", "B", "2"], 2L * h$y["s1", 6])
  expect_equal(attr(x, "layout"), c("species", "site", "season", "occasion"))
  expect_no_error(pam_check_model_input(x))
  dir <- file.path(withr::local_tempdir(), "seasons")
  pam_model_input(many, seasons = two_seasons(), dir = dir)
  expect_setequal(list.files(dir), c("site_covariates.csv", "y_long.csv", "effort_long.csv", "day_long.csv",
                                     "seasons.csv", "occasion_map.csv"))
  long <- data.table::fread(file.path(dir, "y_long.csv"), header = TRUE)
  expect_named(long, c("species", "site", "season", "occasion", "value"))
  expect_equal(nrow(long), length(x$y_array))
})

test_that("pam_define_seasons covers the occasions by year or by month, keeping gaps", {
  dates <- as.Date(c("2025-12-20", "2026-01-05", "2026-03-10"))
  y <- matrix(c(1, 0, 2, 0, 1, 1), nrow = 2, dimnames = list(c("a", "b"), NULL))
  h <- pam_as_count_history(y, occasions = data.frame(occasion = 1:3, bin_start = dates, bin_end = dates))
  yearly <- pam_define_seasons(h, by = "year")
  expect_equal(yearly$season, c("2025", "2026"))
  expect_equal(yearly$start, as.Date(c("2025-01-01", "2026-01-01")))
  expect_equal(yearly$end, as.Date(c("2025-12-31", "2026-12-31")))
  monthly <- pam_define_seasons(h, by = "month")
  expect_equal(monthly$season, c("2025-12", "2026-01", "2026-02", "2026-03"))
  expect_equal(monthly$end, as.Date(c("2025-12-31", "2026-01-31", "2026-02-28", "2026-03-31")))
  x <- pam_model_input(h, seasons = monthly)
  expect_equal(x$num_primary, 4L)
  expect_true(all(is.na(x$y_array[, "2026-02", ])))
  many <- structure(list(one = h), class = c("pam_count_histories", "list"))
  expect_equal(pam_define_seasons(many), yearly)
  expect_error(pam_define_seasons(list()), "pam_count_history")
  expect_error(pam_define_seasons(h, by = "week"), "should be one of")
  expect_error(pam_define_seasons(pam_as_count_history(y)), "need dates")
})

test_that("pam_check_model_input passes good input and names what is wrong", {
  h <- season_history()
  x <- pam_model_input(h)
  res <- pam_check_model_input(x)
  expect_true(all(res$passed))
  expect_named(res, c("check", "passed", "detail"))
  expect_invisible(pam_check_model_input(x))

  short <- x; short$siteCovs <- short$siteCovs[-1, , drop = FALSE]
  expect_error(pam_check_model_input(short), "site covariates have one row per site")
  table <- pam_check_model_input(short, error = FALSE)
  expect_false(all(table$passed))
  expect_true("site covariates have one row per site" %in% table[passed == FALSE]$check)

  fractional <- x; fractional$y[1, 1] <- 1.5
  expect_error(pam_check_model_input(fractional), "whole numbers")
  binary <- pam_model_input(h, binary = TRUE)
  binary$y[1, 1] <- 2L
  expect_error(pam_check_model_input(binary), "0 or 1")
  wrong_shape <- x; wrong_shape$obsCovs$effort <- wrong_shape$obsCovs$effort[, -1]
  expect_error(pam_check_model_input(wrong_shape), "`effort` has the shape")
  hole <- x; hole$obsCovs$effort[1, 1] <- NA
  expect_error(pam_check_model_input(hole), "present wherever the response is")
  renamed <- x; renamed$site_ids[1] <- "zzz"
  expect_error(pam_check_model_input(renamed), "site names match")
  incomplete <- x; incomplete$siteCovs$canopy[1] <- NA
  expect_error(pam_check_model_input(incomplete), "complete")
  unsurveyed <- x; unsurveyed$y[2, ] <- NA
  expect_error(pam_check_model_input(unsurveyed), "surveyed at least once")

  seasons <- pam_model_input(h, seasons = two_seasons())
  seasons$n_secondary <- 99L
  expect_error(pam_check_model_input(seasons), "seasons match")
  broken <- x; attr(broken, "layout") <- NULL
  expect_error(pam_check_model_input(broken), "response is a numeric array")
  expect_error(pam_check_model_input(list()), "pam_model_input")
  expect_error(pam_check_model_input(x, error = NA), "error")
})
