# Count histories: detections per site and occasion, the basis for abundance-model input.

utils::globalVariables(c("occasion"))

#' Match site covariates to the sites of a history (internal)
#'
#' @param sites Site identifiers, in the order of the history rows.
#' @param cov `NULL`, or a data frame. With a `site_id` column rows are matched
#'   by site; without one the table must have one row per site, in order.
#' @return A data frame with `site_id` first and one row per site, in the order
#'   of `sites`.
#' @keywords internal
#' @noRd
pam_match_site_covariates <- function(sites, cov) {
  if (is.null(cov)) return(data.frame(site_id = sites, stringsAsFactors = FALSE))
  if (!is.data.frame(cov)) rlang::abort("`site_covariates` must be a data frame.")
  cov <- as.data.frame(cov, stringsAsFactors = FALSE)
  if (!"site_id" %in% names(cov)) {
    if (nrow(cov) != length(sites)) {
      rlang::abort("`site_covariates` needs a site_id column or one row per site.")
    }
    cov$site_id <- sites
  } else {
    cov$site_id <- as.character(cov$site_id)
    if (anyDuplicated(cov$site_id)) rlang::abort("`site_covariates` has a site more than once.")
    absent <- setdiff(sites, cov$site_id)
    if (length(absent)) {
      rlang::abort(sprintf("`site_covariates` has no row for %d site(s): %s", length(absent),
                           paste(utils::head(absent, 5L), collapse = ", ")))
    }
    cov <- cov[match(sites, cov$site_id), , drop = FALSE]
  }
  rownames(cov) <- NULL
  cov[, c("site_id", setdiff(names(cov), "site_id")), drop = FALSE]
}

#' Sites, occasions and empty matrices of a project's count histories (internal)
#'
#' @param effort Effort bins from `pam_effort_bins()`.
#' @param bin_days Length of an occasion in days.
#' @return A list: `sites`, `occasion_start`, `y0` (0 where a site-occasion was
#'   surveyed, `NA` elsewhere), `effort_hours`, `day`, `occasions`.
#' @keywords internal
#' @noRd
pam_history_frame <- function(effort, bin_days) {
  if (nrow(effort) == 0L) rlang::abort("No usable recordings found in the master table.")
  sites <- sort(unique(effort$site_id))
  occasion_start <- sort(unique(effort$bin_start))
  cell <- cbind(match(effort$site_id, sites), match(effort$bin_start, occasion_start))
  surveyed <- effort$sufficient
  y0 <- matrix(NA_integer_, nrow = length(sites), ncol = length(occasion_start))
  effort_hours <- matrix(NA_real_, nrow = length(sites), ncol = length(occasion_start))
  y0[cell[surveyed, , drop = FALSE]] <- 0L
  effort_hours[cell[surveyed, , drop = FALSE]] <- effort$effort_hours[surveyed]
  day <- matrix(rep(as.integer(occasion_start - min(occasion_start)), each = length(sites)),
                nrow = length(sites))
  occasions <- data.table::data.table(
    occasion = seq_along(occasion_start), bin_start = occasion_start,
    bin_end = occasion_start + bin_days - 1L)
  dimnames(y0) <- dimnames(effort_hours) <- dimnames(day) <-
    list(sites, as.character(occasion_start))
  list(sites = sites, occasion_start = occasion_start, y0 = y0, effort_hours = effort_hours,
       day = day, occasions = occasions)
}

#' Fill a count matrix from the counts of one species (internal)
#'
#' @param frame Output of `pam_history_frame()`.
#' @param counts Sparse counts of one species (`site_id`, `bin_start` and the
#'   value column).
#' @param value_col Name of the column to count.
#' @return The integer matrix `frame$y0` with the counts filled in.
#' @keywords internal
#' @noRd
pam_history_fill <- function(frame, counts, value_col) {
  y <- frame$y0
  if (nrow(counts)) {
    count_cell <- cbind(match(counts$site_id, frame$sites),
                        match(counts$bin_start, frame$occasion_start))
    in_survey <- !is.na(y[count_cell])
    y[count_cell[in_survey, , drop = FALSE]] <- as.integer(counts[[value_col]][in_survey])
  }
  y
}

#' Column of the sparse counts to use (internal)
#'
#' @param count `"events"` or `"files"`.
#' @param counts Sparse counts from `pam_binned_counts()`.
#' @return The column name; aborts when recordings cannot be counted.
#' @keywords internal
#' @noRd
pam_count_column <- function(count, counts) {
  value_col <- if (count == "events") "n_detections" else "n_files"
  if (nrow(counts) && anyNA(counts[[value_col]])) {
    rlang::abort("The detections have no `rel` column, so recordings cannot be counted; use count = \"events\".")
  }
  value_col
}

#' Make a count history from your own counts
#'
#' Wraps a matrix of counts (sites in rows, occasions in columns) so that it can
#' be prepared for modelling by [pam_model_input()]. [pam_count_history()] builds the same
#' object from the detections of a project; use this function when the counts
#' come from somewhere else.
#'
#' @param y A matrix of whole-number counts, sites in rows and occasions in
#'   columns, with `NA` where a site was not surveyed. Row names are the site
#'   identifiers (made up if missing).
#' @param site_covariates Optional data frame of site covariates. With a
#'   `site_id` column the rows are matched to the sites by name, otherwise there
#'   must be one row per site in the same order.
#' @param effort Optional matrix (same shape as `y`) of recording hours per site
#'   and occasion, usable as a detection covariate named `effort`.
#' @param day Optional matrix (same shape as `y`) of days since the first
#'   occasion, usable as a detection covariate named `day`. By default the
#'   occasion number minus one.
#' @param occasions Optional data frame describing the occasions, one row per
#'   column of `y`.
#' @param species Name of the species, for labelling.
#' @param count What the counts are: `"events"` or `"files"` (for labelling).
#' @return An object of class `pam_count_history`: a list with `y`, `effort`,
#'   `day`, `site_covariates`, `occasions`, `species` and `count`.
#' @examples
#' counts <- matrix(c(0, 2, 5, 1, 0, 3, 4, 0, 2, 1, 1, 0), nrow = 3,
#'                  dimnames = list(c("site_a", "site_b", "site_c"), NULL))
#' hist <- pam_as_count_history(counts, species = "Example species")
#' hist$y
#' @seealso [pam_count_history()], [pam_model_input()]
#' @export
pam_as_count_history <- function(y, site_covariates = NULL, effort = NULL, day = NULL,
                                 occasions = NULL, species = NA_character_, count = "events") {
  if (!is.matrix(y) || !is.numeric(y) || nrow(y) < 1L || ncol(y) < 1L) {
    rlang::abort("`y` must be a numeric matrix with at least one site and one occasion.")
  }
  if (any(y < 0 | y != round(y), na.rm = TRUE)) {
    rlang::abort("`y` must hold whole numbers of 0 or more (NA where a site was not surveyed).")
  }
  storage.mode(y) <- "integer"
  sites <- rownames(y)
  if (is.null(sites)) sites <- paste0("site", seq_len(nrow(y)))
  if (anyDuplicated(sites)) rlang::abort("Site names (row names of `y`) must be unique.")
  rownames(y) <- sites
  if (is.null(colnames(y))) colnames(y) <- as.character(seq_len(ncol(y)))

  same_shape <- function(m, what) {
    if (!is.matrix(m) || !is.numeric(m) || !identical(dim(m), dim(y))) {
      rlang::abort(sprintf("`%s` must be a numeric matrix with the same shape as `y`.", what))
    }
    dimnames(m) <- dimnames(y)
    m
  }
  if (!is.null(effort)) {
    effort <- same_shape(effort, "effort")
    if (any(effort < 0, na.rm = TRUE)) rlang::abort("`effort` cannot be negative.")
  }
  day <- if (is.null(day)) {
    matrix(rep(seq_len(ncol(y)) - 1, each = nrow(y)), nrow = nrow(y), dimnames = dimnames(y))
  } else same_shape(day, "day")

  occasions <- if (is.null(occasions)) {
    data.table::data.table(occasion = seq_len(ncol(y)), bin_start = as.Date(NA))
  } else {
    if (nrow(occasions) != ncol(y)) rlang::abort("`occasions` needs one row per column of `y`.")
    data.table::as.data.table(occasions)
  }

  structure(list(y = y, effort = effort, day = day,
                 site_covariates = pam_match_site_covariates(sites, site_covariates),
                 occasions = occasions, species = as.character(species)[1L],
                 count = count),
            class = "pam_count_history")
}

#' Count history of one species: detections per site and occasion
#'
#' Counts the detections of one species in each site and occasion of a project
#' and returns them in the form that abundance models need: a matrix with
#' sites in rows and occasions in columns, `NA` where a site was not surveyed,
#' and matrices of recording effort and days. This is the abundance counterpart
#' of the detection histories of Stage 6.
#'
#' @param cfg A `pam_config` object.
#' @param species The species, given as scientific name, common name or species
#'   label (any capitalisation). It must identify exactly one species.
#' @param run_id Detection run (sub-folder of paths$detections).
#' @param bin_days Length of an occasion in days. `NULL` uses
#'   `occupancy$occasion_length_days` (1 if not set).
#' @param count What to count: `"events"` (the default; detected events, which
#'   Stage 4 forms by merging overlapping BirdNET windows) or `"files"` (the
#'   number of recordings with at least one detection, which cannot exceed the
#'   number of recordings and is less affected by one animal calling for a long
#'   time).
#' @param thresholds Optional per-species thresholds (a data frame, or the path
#'   of a CSV file, with `scientific_name` and `threshold`), for example from
#'   `pam_species_thresholds()`.
#' @param min_effort_hours Minimum recorded hours for an occasion to count as
#'   surveyed; others are `NA`. `NULL` uses `occupancy$min_effort_hours` (2 if
#'   not set).
#' @param site_covariates Optional data frame of site covariates with a
#'   `site_id` column (for example habitat or elevation). Every site must have
#'   a row.
#' @return An object of class `pam_count_history`: a list with
#'   * `y`: integer matrix of counts (sites x occasions, `NA` = not surveyed);
#'   * `effort`: matrix of recorded hours (`NA` where not surveyed);
#'   * `day`: matrix of days since the first occasion;
#'   * `site_covariates`: data frame with `site_id` and your covariates;
#'   * `occasions`: the start and end day of each occasion;
#'   * `species`, `count`: what was counted.
#' @details
#' Sites and occasions follow Stage 6: occasions are blocks of `bin_days` days
#' starting on the first recorded day, shared by all sites, and only occasions
#' with recordings at some site appear. The counts are numbers of detections,
#' not numbers of animals, so models fitted to them give a relative abundance
#' index. Use [pam_model_input()] to turn the history into input for
#' abundance or occupancy models.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' sp <- unique(proc$clean$scientific_name)[1]
#' hist <- suppressMessages(pam_count_history(ex$cfg, species = sp))
#' hist$y
#' @seealso [pam_as_count_history()], [pam_model_input()]
#' @export
pam_count_history <- function(cfg, species, run_id = cfg$birdnet$run_id, bin_days = NULL,
                              count = c("events", "files"), thresholds = NULL,
                              min_effort_hours = NULL, site_covariates = NULL) {
  count <- match.arg(count)
  if (missing(species) || !is.character(species) || length(species) != 1L || is.na(species) ||
      !nzchar(species)) {
    rlang::abort("`species` must be a single species name.")
  }
  bin_days <- pam_check_bin_days(pam_or(bin_days, pam_or(cfg$occupancy$occasion_length_days, 1L)))
  min_effort_h <- pam_resolve_min_effort(cfg, min_effort_hours)
  thresholds <- pam_read_thresholds(thresholds, "thresholds")

  bc <- pam_binned_counts(cfg, run_id, bin_days, thresholds, min_effort_h, species = species)
  if (nrow(bc$species_tab) == 0L) {
    rlang::abort(sprintf("No detections of '%s' in run '%s'.", species, run_id))
  }
  if (nrow(bc$species_tab) > 1L) {
    rlang::abort(sprintf("'%s' matches %d species (%s); use one scientific name or species label.",
                         species, nrow(bc$species_tab),
                         paste(bc$species_tab$species, collapse = "; ")))
  }
  frame <- pam_history_frame(bc$effort, bin_days)
  value_col <- pam_count_column(count, bc$counts)
  y <- pam_history_fill(frame, bc$counts, value_col)

  out <- pam_as_count_history(y, site_covariates = site_covariates, effort = frame$effort_hours,
                              day = frame$day, occasions = frame$occasions,
                              species = bc$species_tab$species, count = count)
  if (sum(y, na.rm = TRUE) == 0L) {
    rlang::warn(sprintf("No '%s' counts in any surveyed occasion.", species))
  }
  out
}

#' Count histories of many species at once
#'
#' Builds a [pam_count_history()] for every species (or the species you name) in
#' one pass over the detections. All histories share the same sites, occasions,
#' effort and site covariates, which is what multi-species models need.
#'
#' @inheritParams pam_count_history
#' @param species Optional species to include: scientific names, common names or
#'   species labels (any capitalisation). `NULL` (the default) takes every
#'   species in the detections.
#' @param min_total Species with fewer than this many counts in total, over all
#'   sites and occasions, are left out (default 1, which drops species with no
#'   count after the thresholds).
#' @return An object of class `pam_count_histories`: a named list (one
#'   [pam_count_history()] per species, named by species label).
#' @details Pass the result to [pam_model_input()] to get a species by site by
#'   occasion array for multi-species models, or take one species with
#'   `histories[["label"]]`.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' hists <- suppressMessages(pam_count_histories(ex$cfg))
#' names(hists)
#' @seealso [pam_count_history()], [pam_model_input()]
#' @export
pam_count_histories <- function(cfg, species = NULL, run_id = cfg$birdnet$run_id,
                                bin_days = NULL, count = c("events", "files"),
                                thresholds = NULL, min_effort_hours = NULL,
                                site_covariates = NULL, min_total = 1) {
  count <- match.arg(count)
  if (!is.null(species) && (!is.character(species) || length(species) == 0L || anyNA(species))) {
    rlang::abort("`species` must be NULL or species names.")
  }
  if (!is.numeric(min_total) || length(min_total) != 1L || is.na(min_total) || min_total < 0) {
    rlang::abort("`min_total` must be a single number of 0 or more.")
  }
  bin_days <- pam_check_bin_days(pam_or(bin_days, pam_or(cfg$occupancy$occasion_length_days, 1L)))
  min_effort_h <- pam_resolve_min_effort(cfg, min_effort_hours)
  thresholds <- pam_read_thresholds(thresholds, "thresholds")

  bc <- pam_binned_counts(cfg, run_id, bin_days, thresholds, min_effort_h, species = species)
  if (nrow(bc$species_tab) == 0L) {
    rlang::abort(sprintf("No detections to count in run '%s' (check `species`).", run_id))
  }
  frame <- pam_history_frame(bc$effort, bin_days)
  value_col <- pam_count_column(count, bc$counts)
  covariates <- pam_match_site_covariates(frame$sites, site_covariates)

  labels <- sort(bc$species_tab$species)
  histories <- lapply(labels, function(label) {
    y <- pam_history_fill(frame, bc$counts[bc$counts$species == label], value_col)
    pam_as_count_history(y, site_covariates = covariates, effort = frame$effort_hours,
                         day = frame$day, occasions = frame$occasions, species = label,
                         count = count)
  })
  names(histories) <- labels
  totals <- vapply(histories, function(h) sum(h$y, na.rm = TRUE), numeric(1))
  histories <- histories[totals >= min_total]
  if (length(histories) == 0L) {
    rlang::abort(sprintf("No species has at least %g count(s) in surveyed occasions.", min_total))
  }
  structure(histories, class = c("pam_count_histories", "list"))
}

#' Print count histories of several species (internal)
#'
#' @param x A `pam_count_histories`.
#' @param ... Not used.
#' @return `x`, invisibly.
#' @keywords internal
#' @noRd
#' @export
print.pam_count_histories <- function(x, ...) {
  first <- unclass(x)[[1L]]
  cat("pamflow count histories: ", length(x), " species, ", nrow(first$y), " sites x ",
      ncol(first$y), " occasions (", first$count, ")\n", sep = "")
  invisible(x)
}

#' Add site covariates to a count history
#'
#' Attaches covariates, such as habitat or elevation, to histories that were
#' built without them. Rows are matched to the sites by name, so the order of
#' your table does not matter.
#'
#' @param x A `pam_count_history` or `pam_count_histories`.
#' @param covariates A data frame with a `site_id` column and one column per
#'   covariate. Every site of `x` needs a row; extra rows are ignored. Without a
#'   `site_id` column the table needs one row per site, in the order of the
#'   sites.
#' @param replace If `FALSE` (the default), a covariate that is already present
#'   is an error; if `TRUE`, it is replaced.
#' @return `x` with the covariates added.
#' @examples
#' counts <- matrix(c(0, 2, 5, 1, 0, 3), nrow = 3,
#'                  dimnames = list(c("site_a", "site_b", "site_c"), NULL))
#' hist <- pam_as_count_history(counts, species = "Example species")
#' covs <- data.frame(site_id = c("site_c", "site_a", "site_b"), canopy = c(0.9, 0.2, 0.5))
#' pam_add_site_covariates(hist, covs)$site_covariates
#' @seealso [pam_as_count_history()], [pam_model_input()]
#' @export
pam_add_site_covariates <- function(x, covariates, replace = FALSE) {
  if (inherits(x, "pam_count_histories")) {
    out <- lapply(unclass(x), pam_add_site_covariates, covariates = covariates, replace = replace)
    return(structure(out, class = class(x)))
  }
  if (!inherits(x, "pam_count_history")) {
    rlang::abort("`x` must be a pam_count_history or pam_count_histories.")
  }
  if (!is.logical(replace) || length(replace) != 1L || is.na(replace)) {
    rlang::abort("`replace` must be TRUE or FALSE.")
  }
  incoming <- pam_match_site_covariates(rownames(x$y), covariates)
  added <- setdiff(names(incoming), "site_id")
  if (length(added) == 0L) rlang::abort("`covariates` has no covariate columns.")
  clash <- intersect(added, names(x$site_covariates))
  if (length(clash) && !replace) {
    rlang::abort(sprintf("Covariate(s) already present: %s. Use replace = TRUE to replace them.",
                         paste(clash, collapse = ", ")))
  }
  kept <- setdiff(names(x$site_covariates), c("site_id", clash))
  x$site_covariates <- cbind(x$site_covariates[, c("site_id", kept), drop = FALSE],
                             incoming[, added, drop = FALSE])
  x
}
