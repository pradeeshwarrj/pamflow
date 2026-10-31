# Species richness and diversity from the cleaned detections: richness, Hill
# numbers, expected species accumulation over sites, and the Chao2 estimate.

utils::globalVariables(c("richness", "n_events", "weight", "n_sites", "n_occasions_surveyed"))

#' Hill numbers of a set of abundances (internal)
#'
#' @param abundance Non-negative weights, one per species (zeros are ignored).
#' @param q Orders of diversity (numbers of 0 or more). 0 is the number of
#'   species, 1 the exponential of Shannon entropy, 2 the inverse Simpson index.
#' @return A named numeric vector (`q0`, `q1`, ...). An empty community has
#'   richness 0 and `NA` for every other order.
#' @keywords internal
#' @noRd
pam_hill_numbers <- function(abundance, q = c(0, 1, 2)) {
  if (!is.numeric(q) || anyNA(q) || any(!is.finite(q)) || any(q < 0)) {
    rlang::abort("`q` must be numbers of 0 or more.")
  }
  abundance <- abundance[is.finite(abundance) & abundance > 0]
  out <- vapply(q, function(order) {
    if (!length(abundance)) return(if (order == 0) 0 else NA_real_)
    p <- abundance / sum(abundance)
    if (order == 0) length(p)
    else if (order == 1) exp(-sum(p * log(p)))
    else sum(p^order)^(1 / (1 - order))
  }, numeric(1))
  stats::setNames(out, paste0("q", as.character(q)))
}

#' Expected species accumulation over sites (internal)
#'
#' Sample-based rarefaction (Coleman et al. 1982): the expected number of
#' species found in `n` sites drawn at random, from how many sites each species
#' occupies. Exact, so no random numbers are used.
#'
#' @param incidence Logical matrix, sites in rows and species in columns.
#' @return A data.table with `n_sites` (1 to the number of sites) and the
#'   expected `richness`; zero rows when there are no sites.
#' @keywords internal
#' @noRd
pam_rarefy_sites <- function(incidence) {
  m <- nrow(incidence)
  if (m == 0L) return(data.table::data.table(n_sites = integer(), richness = numeric()))
  freq <- colSums(incidence)
  n_species <- length(freq)
  expected <- vapply(seq_len(m), function(n) {
    absent <- ifelse(m - freq >= n, exp(lchoose(m - freq, n) - lchoose(m, n)), 0)
    n_species - sum(absent)
  }, numeric(1))
  data.table::data.table(n_sites = seq_len(m), richness = expected)
}

#' Chao2 estimate of the total number of species (internal)
#'
#' Incidence-based estimator with the small-sample correction of Chao (1987).
#'
#' @param incidence Logical matrix, sites in rows and species in columns.
#' @return A one-row data.table: `n_sites`, `observed`, `singletons` (species in
#'   exactly one site), `doubletons` (exactly two), `chao2` and `completeness`
#'   (`observed / chao2`). Values are `NA` when there are no sites.
#' @keywords internal
#' @noRd
pam_chao2 <- function(incidence) {
  m <- nrow(incidence)
  if (m == 0L) {
    return(data.table::data.table(n_sites = 0L, observed = 0L, singletons = NA_integer_,
                                  doubletons = NA_integer_, chao2 = NA_real_,
                                  completeness = NA_real_))
  }
  freq <- colSums(incidence)
  observed <- sum(freq > 0)
  q1 <- sum(freq == 1); q2 <- sum(freq == 2)
  extra <- if (q2 > 0) q1^2 / (2 * q2) else q1 * (q1 - 1) / 2
  chao2 <- observed + (m - 1) / m * extra
  data.table::data.table(n_sites = as.integer(m), observed = as.integer(observed),
                         singletons = as.integer(q1), doubletons = as.integer(q2),
                         chao2 = chao2,
                         completeness = if (chao2 > 0) observed / chao2 else NA_real_)
}

#' Species richness and diversity per site and occasion
#'
#' Turns the cleaned detections into species richness and diversity: for every
#' site and time bin, for every site over the whole survey, and across sites
#' (species accumulation and an estimate of how many species were missed). The
#' site table can be joined to habitat covariates by `site_id` to study how
#' richness varies with the environment.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run (sub-folder of paths$detections).
#' @param bin_days Length of a time bin in days. `NULL` uses
#'   `occupancy$occasion_length_days` (1 if not set).
#' @param min_events A species counts as present in a site and bin only when it
#'   has at least this many events there (a whole number, default 1). A higher
#'   number removes species known only from a lone, possibly false, detection,
#'   at the cost of missing rare species.
#' @param abundance How species are weighted in the Hill numbers: `"counts"`
#'   (the default; the number of events, an activity-based measure) or
#'   `"presence"` (every present species weighs the same, so only occurrence
#'   matters).
#' @param q Orders of the Hill numbers to compute besides richness (default 1
#'   and 2). Richness is the Hill number of order 0 and is always returned.
#' @param thresholds Optional per-species thresholds (a data frame, or the path
#'   of a CSV file, with `scientific_name` and `threshold`), for example from
#'   `pam_species_thresholds()`.
#' @param species Optional species to keep (scientific names, common names or
#'   species labels). `NULL` keeps all.
#' @param min_effort_hours Minimum recorded hours for a bin to count as
#'   surveyed. `NULL` uses `occupancy$min_effort_hours` (2 if not set).
#' @param write If `TRUE`, also save the four tables to `<outputs>/<run_id>/`
#'   as `richness_occasions.csv`, `richness_sites.csv`,
#'   `species_accumulation.csv` and `richness_estimates.csv`.
#' @return A list of class `pam_richness`:
#'   * `occasions`: one row per site and bin: `richness`, `hill_q<q>` columns,
#'     `n_events` (events of the species counted as present), `effort_hours`,
#'     `n_days`, `sufficient`. Bins below the minimum effort are kept and
#'     flagged.
#'   * `sites`: one row per site, using only surveyed bins: `richness`,
#'     `hill_q<q>`, `n_events`, `n_occasions_surveyed`, `effort_hours`.
#'   * `accumulation`: the expected number of species (`richness`) for
#'     `n_sites` = 1 to the number of surveyed sites.
#'   * `estimates`: one row with the observed richness, the Chao2 estimate of
#'     the total and `completeness` (observed divided by estimated).
#'   * `settings`: the choices that were used.
#' @details
#' ## Hill numbers
#' Hill numbers describe diversity as an effective number of species. Order 1
#' is the number of equally common species that gives the same Shannon
#' diversity, and order 2 the same for the Simpson index; larger orders give
#' more weight to the dominant species. With `abundance = "counts"` a loud, vocal
#' species weighs more than a quiet one, so the numbers describe the acoustic
#' community; use `"presence"` when only occurrence matters. A bin with no
#' species has richness 0 and `NA` for the other orders.
#'
#' ## Accumulation and the estimate
#' Sites are the sampling units. `accumulation` is the exact expected number of
#' species found in `n` randomly chosen surveyed sites (sample-based
#' rarefaction), so curves from different projects can be compared at the same
#' number of sites. The Chao2 estimate uses how many species were found in only
#' one or two sites to estimate how many remain undetected; treat it as a lower
#' bound. A species with a false-positive detection counts as present, so
#' validated thresholds and `min_events` matter for all of these numbers.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' rich <- suppressMessages(pam_richness(ex$cfg))
#' as.data.frame(rich$sites)[, c("site_id", "richness", "hill_q1", "hill_q2")]
#' rich$estimates
#' # count a species only when it has at least two events in a bin
#' strict <- suppressMessages(pam_richness(ex$cfg, min_events = 2))
#' strict$sites$richness
#' @seealso [pam_plot_richness()], [pam_detection_table()]
#' @export
pam_richness <- function(cfg, run_id = cfg$birdnet$run_id, bin_days = NULL, min_events = 1,
                         abundance = c("counts", "presence"), q = c(1, 2), thresholds = NULL,
                         species = NULL, min_effort_hours = NULL, write = FALSE) {
  abundance <- match.arg(abundance)
  stage <- "07_richness"; log_dir <- cfg$paths$logs
  if (!is.numeric(min_events) || length(min_events) != 1L || is.na(min_events) ||
      min_events < 1 || min_events != round(min_events)) {
    rlang::abort("`min_events` must be a single whole number of 1 or more.")
  }
  if (!is.numeric(q) || anyNA(q) || any(!is.finite(q)) || any(q < 0)) {
    rlang::abort("`q` must be numbers of 0 or more.")
  }
  q <- sort(unique(q[q != 0]))                    # order 0 is the richness column
  hill_names <- paste0("hill_q", as.character(q))
  bin_days <- pam_check_bin_days(pam_or(bin_days, pam_or(cfg$occupancy$occasion_length_days, 1L)))
  min_effort_h <- pam_resolve_min_effort(cfg, min_effort_hours)
  thresholds <- pam_read_thresholds(thresholds, "thresholds")

  bc <- pam_binned_counts(cfg, run_id, bin_days, thresholds, min_effort_h, species = species)
  effort <- bc$effort
  hill_columns <- function(w) as.list(stats::setNames(pam_hill_numbers(w, q), hill_names))
  # richness, events and Hill numbers per group; zero rows give an empty table with the same columns
  richness_by <- function(dt, keys) {
    if (nrow(dt) == 0L) {
      empty <- dt[, keys, with = FALSE]
      empty[, `:=`(richness = integer(), n_events = integer())]
      for (nm in hill_names) data.table::set(empty, j = nm, value = numeric())
      return(empty)
    }
    dt[, c(list(richness = .N, n_events = sum(n_events)), hill_columns(weight)), by = keys]
  }

  # species counted as present in each site and bin
  present <- bc$counts[n_detections >= min_events,
                       .(site_id, bin_start, species, n_events = n_detections,
                         weight = if (abundance == "counts") as.numeric(n_detections) else rep(1, .N))]

  occ <- richness_by(present, c("site_id", "bin_start"))
  occasions <- merge(effort, occ, by = c("site_id", "bin_start"), all.x = TRUE, sort = FALSE)
  occasions[is.na(richness), `:=`(richness = 0L, n_events = 0L)]
  data.table::setcolorder(occasions, c("site_id", "bin_start", "bin_end", "richness", hill_names,
                                       "n_events", "effort_hours", "n_days", "sufficient"))
  data.table::setorder(occasions, site_id, bin_start)

  # sites: only bins that reached the minimum effort
  surveyed <- effort[sufficient == TRUE, .(site_id, bin_start)]
  present_surveyed <- present[surveyed, on = c("site_id", "bin_start"), nomatch = NULL]
  site_species <- present_surveyed[, .(weight = sum(weight), n_events = sum(n_events)),
                                   by = .(site_id, species)]
  site_hill <- richness_by(site_species, "site_id")
  site_effort <- effort[sufficient == TRUE, .(n_occasions_surveyed = .N,
                                              effort_hours = sum(effort_hours)), by = site_id]
  sites <- merge(site_effort, site_hill, by = "site_id", all.x = TRUE, sort = FALSE)
  sites[is.na(richness), `:=`(richness = 0L, n_events = 0L)]
  data.table::setcolorder(sites, c("site_id", "richness", hill_names, "n_events",
                                   "n_occasions_surveyed", "effort_hours"))
  data.table::setorder(sites, site_id)

  # accumulation and the Chao2 estimate across surveyed sites
  site_ids <- sites$site_id
  species_ids <- sort(unique(site_species$species))
  incidence <- matrix(FALSE, nrow = length(site_ids), ncol = length(species_ids),
                      dimnames = list(site_ids, species_ids))
  if (nrow(site_species)) {
    incidence[cbind(match(site_species$site_id, site_ids),
                    match(site_species$species, species_ids))] <- TRUE
  }
  if (length(site_ids) == 0L) {
    pam_log("WARN", "No site reached the minimum recording effort; richness tables are empty.",
            stage, log_dir)
    rlang::warn("No surveyed sites: lower `min_effort_hours` or check the recordings.")
  }
  accumulation <- pam_rarefy_sites(incidence)
  estimates <- pam_chao2(incidence)

  out <- structure(
    list(occasions = occasions[], sites = sites[], accumulation = accumulation,
         estimates = estimates,
         settings = list(bin_days = bin_days, min_events = as.integer(min_events),
                         abundance = abundance, q = q, min_effort_hours = min_effort_h)),
    class = "pam_richness")

  pam_log("INFO", sprintf("Richness: %d sites, %d site-bins, %d species (min %d event(s) per bin)",
                          nrow(sites), nrow(occasions), length(species_ids), as.integer(min_events)),
          stage, log_dir)

  if (isTRUE(write)) {
    dir <- file.path(cfg$paths$outputs, run_id)
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    pam_write_csv_atomic(out$occasions, file.path(dir, "richness_occasions.csv"))
    pam_write_csv_atomic(out$sites, file.path(dir, "richness_sites.csv"))
    pam_write_csv_atomic(out$accumulation, file.path(dir, "species_accumulation.csv"))
    pam_write_csv_atomic(out$estimates, file.path(dir, "richness_estimates.csv"))
    pam_log("INFO", sprintf("Richness tables written to %s", dir), stage, log_dir)
  }
  out
}

#' Plot species richness
#'
#' @param x The result of [pam_richness()].
#' @param type `"accumulation"` (the default) draws the expected species
#'   accumulation over sites with the Chao2 estimate as a dashed line;
#'   `"sites"` draws richness per site, highest first.
#' @return A ggplot object.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#' rich <- suppressMessages(pam_richness(ex$cfg))
#' p <- pam_plot_richness(rich, "sites")
#' class(p)
#' @export
pam_plot_richness <- function(x, type = c("accumulation", "sites")) {
  type <- match.arg(type)
  if (!inherits(x, "pam_richness")) rlang::abort("`x` must be the result of pam_richness().")
  if (type == "accumulation") {
    p <- ggplot2::ggplot(x$accumulation, ggplot2::aes(x = n_sites, y = richness)) +
      ggplot2::geom_line(colour = "#6c9bd2") +
      ggplot2::geom_point(colour = "#3a6ea5", size = 1.5) +
      ggplot2::labs(x = "Sites sampled", y = "Expected number of species")
    est <- x$estimates$chao2
    if (length(est) == 1L && is.finite(est)) {
      p <- p + ggplot2::geom_hline(yintercept = est, linetype = "dashed", colour = "grey40")
    }
  } else {
    dt <- data.table::copy(x$sites)
    dt[, site_id := stats::reorder(site_id, -richness)]
    p <- ggplot2::ggplot(dt, ggplot2::aes(x = site_id, y = richness)) +
      ggplot2::geom_col(fill = "#6c9bd2") +
      ggplot2::labs(x = "Site", y = "Species richness")
  }
  p <- p + ggplot2::theme_minimal()
  if (type == "sites") {
    p <- p + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  }
  p
}
