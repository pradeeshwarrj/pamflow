# Input data for abundance and occupancy models: response matrix, site covariates and
# observation covariates, for one or many species and one or many seasons.
# pamflow does not fit these models; it only prepares their input.

#' Standardise covariates (internal)
#'
#' Numeric covariates are centered and scaled (mean 0, standard deviation 1);
#' character covariates become factors. A constant covariate is only centered.
#'
#' @param site_covs Data frame with `site_id` and covariates.
#' @param obs_covs Named list of matrices (observation covariates).
#' @param standardize If `FALSE`, only character columns are converted.
#' @return A list: `site`, `obs` and `scaling` (a data.table with `source`,
#'   `name`, `center`, `scale`; empty when nothing was scaled).
#' @keywords internal
#' @noRd
pam_scale_covariates <- function(site_covs, obs_covs, standardize = TRUE) {
  scaling <- list()
  scale_values <- function(x, source, name) {
    centre <- mean(x, na.rm = TRUE)
    spread <- stats::sd(x, na.rm = TRUE)
    if (!is.finite(spread) || spread == 0) spread <- 1
    scaling[[length(scaling) + 1L]] <<- data.table::data.table(
      source = source, name = name, center = centre, scale = spread)
    (x - centre) / spread
  }
  for (nm in setdiff(names(site_covs), "site_id")) {
    if (is.character(site_covs[[nm]])) site_covs[[nm]] <- factor(site_covs[[nm]])
    if (standardize && is.numeric(site_covs[[nm]])) {
      site_covs[[nm]] <- scale_values(site_covs[[nm]], "site", nm)
    }
  }
  if (standardize) {
    for (nm in names(obs_covs)) obs_covs[[nm]] <- scale_values(obs_covs[[nm]], "obs", nm)
  }
  list(site = site_covs, obs = obs_covs,
       scaling = if (length(scaling)) data.table::rbindlist(scaling) else
         data.table::data.table(source = character(), name = character(),
                                center = numeric(), scale = numeric()))
}

utils::globalVariables(c("season", "occasion_in_season", "source_occasion", "passed"))

#' Collect the pieces of one or several histories on a common grid (internal)
#'
#' @param history A `pam_count_history` or `pam_count_histories`.
#' @return A list: `y` (integer array, species x sites x occasions), `species`,
#'   `site_covs`, `obs_covs` (list of site x occasion matrices), `occasions`.
#' @keywords internal
#' @noRd
pam_history_parts <- function(history) {
  hists <- if (inherits(history, "pam_count_histories")) unclass(history) else list(history)
  if (length(hists) == 0L) rlang::abort("`history` contains no species.")
  first <- hists[[1L]]
  same_grid <- vapply(hists, function(h) {
    identical(rownames(h$y), rownames(first$y)) && identical(colnames(h$y), colnames(first$y))
  }, logical(1))
  if (!all(same_grid)) rlang::abort("All histories must have the same sites and occasions.")
  species <- vapply(hists, function(h) as.character(h$species)[1L], character(1))
  species[is.na(species)] <- paste0("species", which(is.na(species)))
  species <- make.unique(species)
  y <- array(NA_integer_, dim = c(length(hists), dim(first$y)),
             dimnames = list(species, rownames(first$y), colnames(first$y)))
  for (i in seq_along(hists)) y[i, , ] <- hists[[i]]$y
  list(y = y, species = species, site_covs = first$site_covariates,
       obs_covs = Filter(Negate(is.null), list(effort = first$effort, day = first$day)),
       occasions = first$occasions, count = first$count)
}

#' Define seasons from the occasions of a history
#'
#' Builds a table of seasons (one per calendar year or month) that cover the
#' occasions of a history, for use as the `seasons` argument of
#' [pam_model_input()]. Years or months without any occasion between the first
#' and last are included, so the spacing of seasons is kept.
#'
#' @param history A `pam_count_history` or `pam_count_histories` that has dates
#'   for its occasions (as built by [pam_count_history()]).
#' @param by `"year"` (the default) or `"month"`.
#' @return A data frame with `season` (label), `start` and `end` (Dates).
#' @examples
#' dates <- as.Date(c("2025-12-20", "2026-01-05", "2026-03-10"))
#' counts <- matrix(c(1, 0, 2, 0, 1, 1), nrow = 2, dimnames = list(c("a", "b"), NULL))
#' hist <- pam_as_count_history(
#'   counts, occasions = data.frame(occasion = 1:3, bin_start = dates, bin_end = dates))
#' pam_define_seasons(hist, by = "month")
#' @seealso [pam_model_input()]
#' @export
pam_define_seasons <- function(history, by = c("year", "month")) {
  by <- match.arg(by)
  if (!inherits(history, c("pam_count_history", "pam_count_histories"))) {
    rlang::abort("`history` must be a pam_count_history or pam_count_histories.")
  }
  first <- if (inherits(history, "pam_count_histories")) unclass(history)[[1L]] else history
  dates <- first$occasions$bin_start
  if (length(dates) == 0L || anyNA(dates)) {
    rlang::abort("The occasions of `history` need dates (bin_start) to define seasons.")
  }
  if (by == "year") {
    years <- seq(as.integer(format(min(dates), "%Y")), as.integer(format(max(dates), "%Y")))
    start <- as.Date(paste0(years, "-01-01"))
    end <- as.Date(paste0(years, "-12-31"))
    label <- as.character(years)
  } else {
    first_day <- as.Date(format(min(dates), "%Y-%m-01"))
    last_day <- as.Date(format(max(dates), "%Y-%m-01"))
    start <- seq(first_day, last_day, by = "month")
    end <- seq(start[length(start)], by = "month", length.out = 2L)[2L] - 1L
    end <- c(start[-1L] - 1L, end)
    label <- format(start, "%Y-%m")
  }
  data.frame(season = label, start = start, end = end, stringsAsFactors = FALSE)
}

#' Reshape occasions into seasons (internal)
#'
#' @param y Integer array, species x sites x occasions.
#' @param obs_covs List of site x occasion matrices.
#' @param occasions Table of occasions with `occasion` and `bin_start`.
#' @param seasons Data frame with `season`, `start`, `end`.
#' @return A list: `y_array` (sites x seasons x occasions, with a leading species
#'   dimension when `y` has more than one species), `y_wide` (sites x
#'   seasons*occasions, one species only, else `NULL`), `obs_array`, `obs_wide`,
#'   `num_primary`, `n_secondary`, `seasons` (with `n_occasions`) and
#'   `occasion_map`.
#' @keywords internal
#' @noRd
pam_reshape_seasons <- function(y, obs_covs, occasions, seasons) {
  if (!is.data.frame(seasons) || !all(c("season", "start", "end") %in% names(seasons))) {
    rlang::abort("`seasons` must be a data frame with the columns season, start and end.")
  }
  seasons <- data.table::data.table(season = as.character(seasons$season),
                                    start = as.Date(seasons$start), end = as.Date(seasons$end))
  if (anyNA(seasons$season) || anyNA(seasons$start) || anyNA(seasons$end) ||
      any(seasons$end < seasons$start)) {
    rlang::abort("`seasons` needs a name, a start and an end (not before the start) for every season.")
  }
  if (anyDuplicated(seasons$season)) rlang::abort("Season names must be unique.")
  data.table::setorderv(seasons, "start")
  n_seasons <- nrow(seasons)
  if (n_seasons > 1L && any(seasons$start[-1L] <= seasons$end[-n_seasons])) {
    rlang::abort("Seasons must not overlap.")
  }
  if (anyNA(occasions$bin_start)) {
    rlang::abort("The occasions need dates (bin_start) to be grouped into seasons.")
  }

  season_of <- vapply(occasions$bin_start, function(day) {
    hit <- which(day >= seasons$start & day <= seasons$end)
    if (length(hit)) hit[1L] else NA_integer_
  }, integer(1))
  kept <- which(!is.na(season_of))
  if (length(kept) == 0L) rlang::abort("No occasion falls inside the seasons.")
  if (length(kept) < length(season_of)) {
    rlang::inform(sprintf("%d occasion(s) fall outside the seasons and were left out.",
                          length(season_of) - length(kept)))
  }
  season_idx <- season_of[kept]
  position <- stats::ave(kept, season_idx, FUN = seq_along)
  n_secondary <- max(tabulate(season_idx, nbins = n_seasons))
  seasons[, n_occasions := tabulate(season_idx, nbins = n_seasons)]

  n_species <- dim(y)[1L]; n_sites <- dim(y)[2L]
  site_names <- dimnames(y)[[2L]]
  position_names <- as.character(seq_len(n_secondary))
  y_array <- array(NA, dim = c(n_species, n_sites, n_seasons, n_secondary),
                   dimnames = list(dimnames(y)[[1L]], site_names, seasons$season, position_names))
  for (i in seq_along(kept)) {
    y_array[, , season_idx[i], position[i]] <- y[, , kept[i]]
  }
  to_wide <- function(arr3) {
    matrix(aperm(arr3, c(1L, 3L, 2L)), nrow = dim(arr3)[1L],
           dimnames = list(dimnames(arr3)[[1L]],
                           paste(rep(seasons$season, each = n_secondary),
                                 rep(position_names, times = n_seasons), sep = ":")))
  }
  reshape_matrix <- function(m) {
    arr <- array(NA, dim = c(nrow(m), n_seasons, n_secondary),
                 dimnames = list(rownames(m), seasons$season, position_names))
    for (i in seq_along(kept)) arr[, season_idx[i], position[i]] <- m[, kept[i]]
    arr
  }

  single <- n_species == 1L
  y_out <- if (single) array(y_array, dim = dim(y_array)[-1L], dimnames = dimnames(y_array)[-1L]) else y_array
  obs_array <- lapply(obs_covs, reshape_matrix)
  occasion_map <- data.table::data.table(
    season = seasons$season[season_idx], occasion_in_season = position,
    source_occasion = occasions$occasion[kept], bin_start = occasions$bin_start[kept])
  list(y_array = y_out, y_wide = if (single) to_wide(y_out) else NULL,
       obs_array = obs_array, obs_wide = lapply(obs_array, to_wide),
       num_primary = n_seasons, n_secondary = n_secondary,
       seasons = seasons, occasion_map = occasion_map)
}

#' Check the table of season covariates (internal)
#'
#' @param tab Data frame with `season` and covariate columns.
#' @param season_names Names of the seasons, in order.
#' @return The table with one row per season, in the order of `season_names`.
#' @keywords internal
#' @noRd
pam_season_covariates <- function(tab, season_names) {
  if (!is.data.frame(tab) || !"season" %in% names(tab)) {
    rlang::abort("`season_covariates` must be a data frame with a `season` column.")
  }
  tab <- as.data.frame(tab, stringsAsFactors = FALSE)
  tab$season <- as.character(tab$season)
  if (anyDuplicated(tab$season)) rlang::abort("`season_covariates` has a season more than once.")
  absent <- setdiff(season_names, tab$season)
  if (length(absent)) {
    rlang::abort(sprintf("`season_covariates` has no row for season(s): %s",
                         paste(absent, collapse = ", ")))
  }
  if (ncol(tab) < 2L) rlang::abort("`season_covariates` has no covariate columns.")
  tab <- tab[match(season_names, tab$season), c("season", setdiff(names(tab), "season")), drop = FALSE]
  rownames(tab) <- NULL
  tab
}

#' Prepare a count history as input for abundance and occupancy models
#'
#' Turns a count history into the pieces that site-occupancy and abundance
#' models use: the response `y` (sites by occasions), the site covariates
#' `siteCovs` and the observation covariates `obsCovs`. It handles one species
#' or several, and one season or several. pamflow does not fit these models; use
#' the prepared input with the package you prefer, such as `unmarked`, `ubms` or
#' `spOccupancy`.
#'
#' @param history A `pam_count_history` from [pam_count_history()] or
#'   [pam_as_count_history()], or a `pam_count_histories` from
#'   [pam_count_histories()].
#' @param binary If `FALSE` (the default), `y` holds the counts, as used by
#'   N-mixture (abundance) models. If `TRUE`, `y` is detection (1) or
#'   non-detection (0), as used by occupancy and Royle-Nichols models.
#' @param standardize If `TRUE`, numeric covariates are centered and scaled
#'   (mean 0, standard deviation 1), which helps models converge. The center and
#'   scale are returned in `scaling` so that new data can be treated the same
#'   way. Default `FALSE`: covariates are returned as they are.
#' @param drop_unsurveyed If `TRUE` (the default), sites with no surveyed
#'   occasion are left out of every piece, because model functions cannot use
#'   them.
#' @param seasons Optional data frame with the columns `season` (a name),
#'   `start` and `end` (Dates) that groups the occasions into seasons
#'   (primary periods) for multi-season models; see [pam_define_seasons()]. An
#'   occasion belongs to the season that contains its first day. Occasions
#'   outside every season are left out; seasons with fewer occasions than the
#'   longest are padded with `NA`.
#' @param season_covariates Optional data frame with a `season` column and one
#'   column per covariate that changes between seasons but not between sites
#'   (for example rainfall or year); needs `seasons`.
#' @param dir Optional folder. If given, the pieces are also written there as
#'   CSV files, for use outside R. Nothing is written by default.
#' @return An object of class `pam_model_input`. For one species and no seasons
#'   it is a list with
#'   * `y`: integer matrix, sites in rows and occasions in columns, `NA` where a
#'     site was not surveyed;
#'   * `siteCovs`: data frame of site covariates, one row per site (row names
#'     are the site identifiers); `NULL` if there are none;
#'   * `obsCovs`: named list of matrices shaped like `y`: `effort` (recorded
#'     hours, when the history has it) and `day` (days since the first
#'     occasion);
#'   * `site_ids`, `species`, `count`, `binary`;
#'   * `scaling`: center and scale of every standardized covariate.
#'
#' With several species, `y` is an array (species, sites, occasions) and
#' `species` lists the species. With `seasons`, the list also has
#'   * `y_array`: sites x seasons x occasions within season (with a leading
#'     species dimension for several species); `y` is then the wide matrix
#'     sites x (seasons * occasions) for one species, and `NULL` for several;
#'   * `obsCovs` (wide matrices) and `obsCovs_array` (arrays), shaped like `y`
#'     and `y_array`;
#'   * `num_primary` (number of seasons), `n_secondary` (occasions per season,
#'     including padding), `seasons` (with the number of occasions found) and
#'     `occasion_map` (which original occasion went where);
#'   * with `season_covariates`: `yearlySiteCovs` (data frame, one row per site
#'     and season, sites first) and `yearlySiteCovs_matrices` (sites x seasons).
#'
#' The layout of `y` is stored in `attr(x, "layout")`; [pam_check_model_input()]
#' uses it.
#' @details
#' ## Using the result with unmarked or ubms
#' Both build their data frames from these pieces:
#' ```
#' x <- pam_model_input(history)
#' umf <- unmarked::unmarkedFramePCount(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs)
#' fit <- unmarked::pcount(~ effort ~ canopy, data = umf, K = 100)
#'
#' x <- pam_model_input(history, binary = TRUE)
#' umf <- unmarked::unmarkedFrameOccu(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs)
#' fit <- unmarked::occu(~ effort ~ canopy, data = umf)
#'
#' # several seasons
#' x <- pam_model_input(history, binary = TRUE, seasons = pam_define_seasons(history))
#' umf <- unmarked::unmarkedMultFrame(y = x$y, siteCovs = x$siteCovs, obsCovs = x$obsCovs,
#'                                    numPrimary = x$num_primary)
#' ```
#' The detection formula (before the second `~`) may use the observation
#' covariates `effort` and `day` and any site covariate; the other formula uses
#' site covariates. `ubms` takes the same `unmarkedFrame*` objects.
#'
#' ## Using the result with spOccupancy
#' `spOccupancy` expects a list with the response, the occupancy covariates and
#' the detection covariates, which are the same pieces under other names (check
#' the argument names against its documentation):
#' ```
#' x <- pam_model_input(history, binary = TRUE)          # one species
#' data <- list(y = x$y, occ.covs = x$siteCovs, det.covs = x$obsCovs,
#'              coords = coords)   # coords: your site coordinates, same row order
#'
#' x <- pam_model_input(histories, binary = TRUE)        # several species
#' data <- list(y = x$y, occ.covs = x$siteCovs, det.covs = x$obsCovs, coords = coords)
#' ```
#' For several species `y` has the species first (species x sites x occasions).
#' With seasons use `y_array` and `obsCovs_array`. `x$site_ids` gives the site
#' order.
#'
#' ## About counts
#' Counts are numbers of detections, not numbers of animals. A model fitted to
#' them gives a relative abundance index, not a population size. N-mixture
#' models also slow down when counts are large (the upper bound `K` must exceed
#' the highest count), so `count = "files"` in [pam_count_history()] or shorter
#' occasions are often better than raw event counts.
#'
#' Site covariates with missing values cannot be used by model functions; a
#' warning names them.
#' @examples
#' counts <- matrix(c(0, 2, 5, 1, 0, 3, 4, 0, 2, 1, 1, 0), nrow = 3,
#'                  dimnames = list(c("site_a", "site_b", "site_c"), NULL))
#' hist <- pam_as_count_history(counts, site_covariates = data.frame(canopy = c(0.2, 0.5, 0.9)),
#'                              effort = matrix(24, 3, 4), species = "Example species")
#' x <- pam_model_input(hist)
#' x$y
#' x$siteCovs
#' names(x$obsCovs)
#' # detection / non-detection instead of counts, covariates standardized
#' pam_model_input(hist, binary = TRUE, standardize = TRUE)$y
#' @seealso [pam_count_history()], [pam_count_histories()], [pam_define_seasons()],
#'   [pam_check_model_input()]
#' @export
pam_model_input <- function(history, binary = FALSE, standardize = FALSE,
                            drop_unsurveyed = TRUE, seasons = NULL, season_covariates = NULL,
                            dir = NULL) {
  if (!inherits(history, c("pam_count_history", "pam_count_histories"))) {
    rlang::abort("`history` must come from pam_count_history(), pam_count_histories() or pam_as_count_history().")
  }
  for (flag in list(binary = binary, standardize = standardize, drop_unsurveyed = drop_unsurveyed)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) {
      rlang::abort("`binary`, `standardize` and `drop_unsurveyed` must be TRUE or FALSE.")
    }
  }
  if (!is.null(dir) && (!is.character(dir) || length(dir) != 1L || is.na(dir))) {
    rlang::abort("`dir` must be a single folder path.")
  }
  if (!is.null(season_covariates) && is.null(seasons)) {
    rlang::abort("`season_covariates` needs `seasons`.")
  }

  multi <- inherits(history, "pam_count_histories")
  parts <- pam_history_parts(history)
  y <- parts$y                                          # species x sites x occasions
  if (binary) y <- (y > 0) * 1L                         # keeps the NA of unsurveyed occasions
  site_covs <- parts$site_covs
  obs_covs <- parts$obs_covs

  if (drop_unsurveyed) {
    surveyed_any <- rowSums(!is.na(matrix(y[1L, , ], nrow = dim(y)[2L]))) > 0
    if (!all(surveyed_any)) {
      rlang::inform(sprintf("Left out %d site(s) with no surveyed occasion: %s", sum(!surveyed_any),
                            paste(utils::head(dimnames(y)[[2L]][!surveyed_any], 5L), collapse = ", ")))
      y <- y[, surveyed_any, , drop = FALSE]
      site_covs <- site_covs[surveyed_any, , drop = FALSE]
      obs_covs <- lapply(obs_covs, function(m) m[surveyed_any, , drop = FALSE])
    }
  }
  if (dim(y)[2L] == 0L) rlang::abort("The history has no surveyed sites.")

  site_ids <- site_covs$site_id
  scaled <- pam_scale_covariates(site_covs, obs_covs, standardize)
  site_table <- scaled$site[, setdiff(names(scaled$site), "site_id"), drop = FALSE]
  if (ncol(site_table)) {
    rownames(site_table) <- site_ids
    has_missing <- names(site_table)[vapply(site_table, anyNA, logical(1))]
    if (length(has_missing)) {
      rlang::warn(sprintf("Site covariate(s) with missing values (model functions cannot use them): %s",
                          paste(has_missing, collapse = ", ")))
    }
  } else {
    site_table <- NULL
  }
  scaling <- scaled$scaling

  species_out <- if (multi) parts$species else history$species
  base <- function(y_out, obs_out, layout) {
    out <- list(y = y_out, siteCovs = site_table, obsCovs = if (length(obs_out)) obs_out else NULL,
                site_ids = site_ids, species = species_out, count = parts$count,
                binary = binary, scaling = scaling)
    attr(out, "layout") <- layout
    out
  }

  if (is.null(seasons)) {
    out <- if (multi) {
      base(y, scaled$obs, c("species", "site", "occasion"))
    } else {
      y2 <- matrix(y[1L, , ], nrow = dim(y)[2L], dimnames = dimnames(y)[2:3])
      base(y2, scaled$obs, c("site", "occasion"))
    }
  } else {
    shaped <- pam_reshape_seasons(y, scaled$obs, parts$occasions, seasons)
    out <- base(shaped$y_wide, shaped$obs_wide,
                if (multi) c("species", "site", "season", "occasion") else c("site", "season", "occasion"))
    out$y_array <- shaped$y_array
    out$obsCovs_array <- if (length(shaped$obs_array)) shaped$obs_array else NULL
    out$num_primary <- shaped$num_primary
    out$n_secondary <- shaped$n_secondary
    out$seasons <- shaped$seasons
    out$occasion_map <- shaped$occasion_map
    if (!is.null(season_covariates)) {
      tab <- pam_season_covariates(season_covariates, shaped$seasons$season)
      scaled_tab <- pam_scale_covariates(
        data.frame(site_id = tab$season, tab[setdiff(names(tab), "season")], stringsAsFactors = FALSE),
        list(), standardize)
      if (nrow(scaled_tab$scaling)) {
        scaled_tab$scaling$source <- "season"
        out$scaling <- data.table::rbindlist(list(out$scaling, scaled_tab$scaling))
      }
      tab <- cbind(season = tab$season, scaled_tab$site[setdiff(names(scaled_tab$site), "site_id")])
      n_sites <- length(site_ids)
      covariates <- setdiff(names(tab), "season")
      out$yearlySiteCovs <- tab[rep(seq_len(nrow(tab)), times = n_sites), covariates, drop = FALSE]
      rownames(out$yearlySiteCovs) <- NULL
      out$yearlySiteCovs_matrices <- stats::setNames(lapply(covariates, function(nm) {
        values <- tab[[nm]]
        if (is.factor(values)) values <- as.character(values)
        matrix(rep(values, each = n_sites), nrow = n_sites, dimnames = list(site_ids, tab$season))
      }), covariates)
    }
  }
  class(out) <- "pam_model_input"

  if (!is.null(dir)) pam_write_model_input(out, dir)
  out
}

#' Write model input to CSV files (internal)
#'
#' @param x A `pam_model_input`.
#' @param dir Folder to write to (created if needed).
#' @return `dir`, invisibly.
#' @keywords internal
#' @noRd
pam_write_model_input <- function(x, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  layout <- attr(x, "layout")
  site_table <- data.table::data.table(site_id = x$site_ids, x$siteCovs)
  data.table::fwrite(site_table, file.path(dir, "site_covariates.csv"))
  if (identical(layout, c("site", "occasion"))) {
    with_sites <- function(m) data.table::data.table(site_id = x$site_ids, data.table::as.data.table(m))
    data.table::fwrite(with_sites(x$y), file.path(dir, "y.csv"))
    for (nm in names(x$obsCovs)) {
      data.table::fwrite(with_sites(x$obsCovs[[nm]]), file.path(dir, paste0(nm, ".csv")))
    }
  } else {
    write_long <- function(arr, file) {
      long <- data.table::as.data.table(as.table(arr))
      data.table::setnames(long, c(layout, "value"))
      data.table::fwrite(long, file)
    }
    write_long(if (is.null(x$y_array)) x$y else x$y_array, file.path(dir, "y_long.csv"))
    obs <- if (is.null(x$obsCovs_array)) x$obsCovs else x$obsCovs_array
    for (nm in names(obs)) {
      obs_layout <- setdiff(layout, "species")
      long <- data.table::as.data.table(as.table(obs[[nm]]))
      data.table::setnames(long, c(obs_layout, "value"))
      data.table::fwrite(long, file.path(dir, paste0(nm, "_long.csv")))
    }
    if (!is.null(x$seasons)) data.table::fwrite(x$seasons, file.path(dir, "seasons.csv"))
    if (!is.null(x$occasion_map)) data.table::fwrite(x$occasion_map, file.path(dir, "occasion_map.csv"))
    if (!is.null(x$yearlySiteCovs)) {
      yearly <- data.table::data.table(
        site_id = rep(x$site_ids, each = x$num_primary),
        season = rep(x$seasons$season, times = length(x$site_ids)), x$yearlySiteCovs)
      data.table::fwrite(yearly, file.path(dir, "yearly_site_covariates.csv"))
    }
  }
  invisible(dir)
}

#' Check model input before fitting
#'
#' Runs a set of consistency checks on the output of [pam_model_input()]:
#' dimensions, site and occasion matching, the values of the response and
#' missing values. Use it after editing the input by hand, or to confirm that
#' input is ready before it is passed to a modeling package.
#'
#' @param x A `pam_model_input`.
#' @param error If `TRUE` (the default), a failed check is an error that names the
#'   failed checks. If `FALSE`, the table of checks is returned whatever the
#'   result.
#' @return A data.table with one row per check: `check`, `passed` and `detail`
#'   (invisibly when everything passed).
#' @details The checks are: the response is a numeric array; sites are unique
#'   and match the site covariates (count and names); observation covariates have
#'   the shape of the response; the response holds whole numbers of 0 or more
#'   (0 or 1 for detection / non-detection); every site was surveyed at least
#'   once; observation covariates are present wherever the response is; and, for
#'   seasons, the number of seasons and occasions match the response.
#' @examples
#' counts <- matrix(c(0, 2, 5, 1, 0, 3), nrow = 3, dimnames = list(c("a", "b", "c"), NULL))
#' x <- pam_model_input(pam_as_count_history(counts))
#' pam_check_model_input(x)
#' @seealso [pam_model_input()]
#' @export
pam_check_model_input <- function(x, error = TRUE) {
  if (!inherits(x, "pam_model_input")) rlang::abort("`x` must come from pam_model_input().")
  if (!is.logical(error) || length(error) != 1L || is.na(error)) {
    rlang::abort("`error` must be TRUE or FALSE.")
  }
  layout <- attr(x, "layout")
  response <- if (!is.null(x$y_array)) x$y_array else x$y
  rows <- list()
  add <- function(check, passed, detail = "") {
    rows[[length(rows) + 1L]] <<- data.table::data.table(
      check = check, passed = isTRUE(passed), detail = detail)
  }
  finish <- function() {
    out <- data.table::rbindlist(rows)
    failed <- out[passed == FALSE]
    if (nrow(failed) && error) {
      rlang::abort(paste0("Model input failed ", nrow(failed), " check(s): ",
                          paste(failed$check, collapse = "; ")))
    }
    if (nrow(failed)) out else invisible(out)
  }

  valid_shape <- is.numeric(response) && !is.null(dim(response)) && !is.null(layout) &&
    length(dim(response)) == length(layout)
  add("response is a numeric array", valid_shape,
      if (valid_shape) paste(layout, dim(response), sep = " = ", collapse = ", ") else "unexpected type or shape")
  if (!valid_shape) return(finish())

  site_dim <- which(layout == "site")
  n_sites <- dim(response)[site_dim]
  site_names <- dimnames(response)[[site_dim]]
  add("sites are unique", !anyDuplicated(x$site_ids) && length(x$site_ids) == n_sites,
      sprintf("%d site ids for %d sites in the response", length(x$site_ids), n_sites))
  add("site names match the response", identical(as.character(x$site_ids), as.character(site_names)),
      "site_ids and the site names of the response must agree, in the same order")
  if (!is.null(x$siteCovs)) {
    add("site covariates have one row per site",
        nrow(x$siteCovs) == n_sites && identical(rownames(x$siteCovs), as.character(x$site_ids)),
        sprintf("%d rows for %d sites", nrow(x$siteCovs), n_sites))
    incomplete <- names(x$siteCovs)[vapply(x$siteCovs, anyNA, logical(1))]
    add("site covariates are complete", length(incomplete) == 0L,
        if (length(incomplete)) paste("missing values in", paste(incomplete, collapse = ", ")) else "")
  }

  # the slice of one species: sites x occasions (or sites x seasons x occasions)
  slice_axes <- setdiff(layout, "species")
  slice <- if ("species" %in% layout) {
    index <- c(list(1L), rep(list(TRUE), length(layout) - 1L))
    array(do.call(`[`, c(list(response), index, list(drop = FALSE))), dim = dim(response)[-1L])
  } else response
  obs_source <- if (!is.null(x$obsCovs_array)) x$obsCovs_array else x$obsCovs
  for (nm in names(obs_source)) {
    obs <- obs_source[[nm]]
    right_shape <- identical(as.integer(dim(obs)), as.integer(dim(slice)))
    add(sprintf("`%s` has the shape of the response", nm), right_shape,
        sprintf("is %s, expected %s", paste(dim(obs), collapse = " x "), paste(dim(slice), collapse = " x ")))
    if (right_shape) {
      lost <- sum(is.na(obs) & !is.na(slice))
      add(sprintf("`%s` is present wherever the response is", nm), lost == 0L,
          sprintf("%d missing value(s) where the response is observed", lost))
    }
  }

  values <- as.numeric(response)
  values <- values[!is.na(values)]
  add("response holds whole numbers of 0 or more", all(values >= 0 & values == round(values)), "")
  if (isTRUE(x$binary)) add("response is 0 or 1", all(values %in% c(0, 1)), "")

  surveyed <- apply(!is.na(slice), which(slice_axes == "site"), any)
  add("every site was surveyed at least once", all(surveyed),
      if (!all(surveyed)) paste(site_names[!surveyed], collapse = ", ") else "")

  if (!is.null(x$num_primary)) {
    n_dim <- length(dim(x$y_array))
    add("seasons match the response",
        nrow(x$seasons) == x$num_primary && dim(x$y_array)[n_dim - 1L] == x$num_primary &&
          dim(x$y_array)[n_dim] == x$n_secondary,
        sprintf("%d seasons x %d occasions", x$num_primary, x$n_secondary))
    if (!is.null(x$y)) {
      add("wide response has seasons x occasions columns", ncol(x$y) == x$num_primary * x$n_secondary,
          sprintf("%d columns", ncol(x$y)))
    }
    if (!is.null(x$yearlySiteCovs)) {
      add("seasonal covariates have one row per site and season",
          nrow(x$yearlySiteCovs) == n_sites * x$num_primary, sprintf("%d rows", nrow(x$yearlySiteCovs)))
    }
  }
  finish()
}

#' Print model input (internal)
#'
#' @param x A `pam_model_input`.
#' @param ... Not used.
#' @return `x`, invisibly.
#' @keywords internal
#' @noRd
#' @export
print.pam_model_input <- function(x, ...) {
  response <- if (!is.null(x$y_array)) x$y_array else x$y
  layout <- attr(x, "layout")
  shape <- paste(dim(response), layout, collapse = " x ")
  cat("pamflow model input\n")
  cat("  species:   ", paste(utils::head(x$species, 3L), collapse = ", "),
      if (length(x$species) > 3L) paste0(", ... (", length(x$species), ")"),
      " (", x$count, if (x$binary) ", detection / non-detection", ")\n", sep = "")
  cat("  y:         ", shape, "\n", sep = "")
  cat("  siteCovs:  ", if (is.null(x$siteCovs)) "none" else paste(names(x$siteCovs), collapse = ", "), "\n", sep = "")
  cat("  obsCovs:   ", if (is.null(x$obsCovs)) "none" else paste(names(x$obsCovs), collapse = ", "), "\n", sep = "")
  if (!is.null(x$num_primary)) {
    cat("  seasons:   ", x$num_primary, " x ", x$n_secondary, " occasions\n", sep = "")
  }
  invisible(x)
}
