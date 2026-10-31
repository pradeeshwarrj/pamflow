# Shared foundation for the ecological products (activity, richness, abundance):
# one confidence threshold per species, chosen from the validation results.

utils::globalVariables(c("bin_start", "bin_end", "n_days", "thr_extra", "detections_per_hour"))

#' Read a species-threshold table (internal)
#'
#' @param x `NULL`, a data frame, or the path of a CSV file. It needs the
#'   columns `scientific_name` and `threshold` (between 0 and 1), with one
#'   threshold per species.
#' @param what Name of the argument, used in error messages.
#' @return A data.table with `scientific_name` and `threshold`, or `NULL` when
#'   `x` is `NULL`.
#' @keywords internal
#' @noRd
pam_read_thresholds <- function(x, what = "thresholds") {
  if (is.null(x)) return(NULL)
  if (is.character(x) && length(x) == 1L && !is.na(x)) {
    if (!file.exists(x)) rlang::abort(sprintf("Threshold file not found: %s", x))
    x <- data.table::fread(x)
  }
  if (!is.data.frame(x)) {
    rlang::abort(sprintf("`%s` must be a data frame or the path of a CSV file.", what))
  }
  x <- data.table::as.data.table(x)
  if (!all(c("scientific_name", "threshold") %in% names(x))) {
    rlang::abort(sprintf("`%s` must have the columns scientific_name and threshold.", what))
  }
  x <- x[, .(scientific_name = as.character(scientific_name),
             threshold = as.numeric(threshold))]
  if (anyNA(x$scientific_name) || anyNA(x$threshold) ||
      any(x$threshold < 0 | x$threshold > 1)) {
    rlang::abort(sprintf("`%s`: thresholds must be numbers between 0 and 1.", what))
  }
  if (anyDuplicated(x$scientific_name)) {
    rlang::abort(sprintf("`%s` must have one threshold per species.", what))
  }
  x[]
}

#' Choose one threshold per species from validation metrics (internal)
#'
#' Pure function (no file access), so it can be tested directly.
#'
#' @param metrics The list returned by `pam_validation_metrics()` (uses its
#'   `cells` and `thresholds` tables).
#' @param tolerance Allowed drop in estimated precision, between 0 and 1.
#' @param min_judged Minimum number of judged (correct or incorrect) samples a
#'   species needs before its own threshold is estimated.
#' @param min_coverage Minimum share of a species' events, at or above a
#'   confidence level, that must sit in bands with at least one judged sample
#'   for that level to be trusted (between 0 and 1).
#' @param default Threshold used for species that cannot be estimated.
#' @param manual Optional table of manual thresholds (see
#'   `pam_read_thresholds()`); these override the estimate.
#' @return A data.table with one row per species: `scientific_name`,
#'   `threshold`, `method` ("plateau", "manual" or "default"), `precision_est`,
#'   `coverage`, `n_judged`, `n_events_kept` and `reason`.
#' @keywords internal
#' @noRd
pam_choose_thresholds <- function(metrics, tolerance = 0.05, min_judged = 10,
                                  min_coverage = 0.5, default = 0.5, manual = NULL) {
  in_unit <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 0 && x <= 1
  if (!in_unit(tolerance)) rlang::abort("`tolerance` must be a single number between 0 and 1.")
  if (!in_unit(min_coverage)) rlang::abort("`min_coverage` must be a single number between 0 and 1.")
  if (!in_unit(default)) rlang::abort("`default` must be a single number between 0 and 1.")
  if (!is.numeric(min_judged) || length(min_judged) != 1L || is.na(min_judged) || min_judged < 0) {
    rlang::abort("`min_judged` must be a single number of 0 or more.")
  }

  thr <- metrics$thresholds[scientific_name != "ALL"]
  judged <- metrics$cells[, .(n_judged = sum(n_judged)), by = scientific_name]
  species <- sort(unique(judged$scientific_name))

  template <- data.table::data.table(
    scientific_name = character(), threshold = numeric(), method = character(),
    precision_est = numeric(), coverage = numeric(), n_judged = integer(),
    n_events_kept = integer(), reason = character())
  fallback <- function(sp, nj, why) {
    data.table::data.table(scientific_name = sp, threshold = default, method = "default",
                           precision_est = NA_real_, coverage = NA_real_,
                           n_judged = as.integer(nj), n_events_kept = NA_integer_,
                           reason = why)
  }

  rows <- lapply(species, function(sp) {
    nj <- judged[scientific_name == sp, n_judged]
    if (nj < min_judged) {
      return(fallback(sp, nj, sprintf("only %d judged samples (at least %g needed)", as.integer(nj), min_judged)))
    }
    s <- thr[scientific_name == sp & !is.na(precision_est) & !is.na(coverage) &
               coverage >= min_coverage]
    if (nrow(s) == 0L) {
      return(fallback(sp, nj, "no confidence level has enough reviewed events"))
    }
    best <- max(s$precision_est)
    pick <- s[precision_est >= best - tolerance - 1e-9][which.min(min_confidence)]
    data.table::data.table(
      scientific_name = sp, threshold = pick$min_confidence, method = "plateau",
      precision_est = pick$precision_est, coverage = pick$coverage,
      n_judged = as.integer(nj), n_events_kept = as.integer(round(pick$n_events)),
      reason = sprintf("lowest confidence within %.2f of the best estimated precision (%.2f)",
                       tolerance, best))
  })
  out <- data.table::rbindlist(c(list(template), rows), use.names = TRUE)

  if (!is.null(manual)) {
    m <- pam_read_thresholds(manual, "manual")
    out <- out[!scientific_name %in% m$scientific_name]
    add <- data.table::data.table(
      scientific_name = m$scientific_name, threshold = m$threshold, method = "manual",
      precision_est = NA_real_, coverage = NA_real_,
      n_judged = as.integer(judged$n_judged[match(m$scientific_name, judged$scientific_name)]),
      n_events_kept = NA_integer_, reason = "set manually")
    out <- data.table::rbindlist(list(out, add), use.names = TRUE)
  }
  data.table::setorder(out, scientific_name)
  out[]
}

#' Choose a confidence threshold for each species from the validation results
#'
#' Species differ a lot in how reliable BirdNET is, so one confidence cut-off
#' for all species is rarely right. This function reads the reviewed verdicts
#' of Stage 5 and gives every species its own threshold, without asking you
#' for a precision target.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run (sub-folder of paths$detections).
#' @param tolerance How far below its own best estimated precision a species
#'   may fall (a number between 0 and 1, default 0.05).
#' @param min_judged Minimum number of judged samples (correct or incorrect)
#'   a species needs; species with fewer get the default threshold.
#' @param min_coverage A confidence level only counts when at least this share
#'   of the species' events at or above it lies in bands that were reviewed
#'   (default 0.5).
#' @param manual Optional data frame, or path to a CSV file, with the columns
#'   `scientific_name` and `threshold`. These species use your value instead of
#'   the estimate.
#' @param write If `TRUE`, save the table as
#'   `<detections>/<run_id>/validation/species_thresholds.csv`. Nothing is
#'   written by default.
#' @return A data.table with one row per species: `scientific_name`,
#'   `threshold`, `method`, `precision_est` (estimated precision of the events
#'   kept), `coverage`, `n_judged`, `n_events_kept` and `reason`.
#' @details
#' ## Plateau rule
#' For each species, the estimated precision of all events at or above each
#' confidence band edge comes from `pam_validation_metrics()`. The species'
#' best estimated precision is found, and the **lowest** confidence whose
#' precision is within `tolerance` of that best value is chosen. Going higher
#' than that would discard detections without making them noticeably more
#' reliable. A species with a flat precision curve therefore keeps a low
#' threshold, and one that needs a high threshold gets one.
#'
#' ## Defaults
#' A species with too few judged samples, or no confidence level with enough
#' reviewed events, gets `processing$min_confidence` and `method = "default"`;
#' the `reason` column says why. Manual values always win (`method = "manual"`).
#'
#' ## Using the result
#' Save it with `write = TRUE` and set `processing$species_thresholds_file` in
#' the config to that file. Stage 4 and Stage 6 read it; the columns they do
#' not need are ignored.
#' @examples
#' ex <- pam_example_project()
#' # the later stages read the master table that the scan builds
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 8))
#' val_dir <- file.path(ex$cfg$paths$detections, "run01", "validation")
#' # normally the review app writes this file; here the verdicts are made up
#' results <- data.frame(sample_id = new$sample_id,
#'                       verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
#'                       true_species = NA_character_, note = "", reviewer = "example",
#'                       reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
#' utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)
#' thr <- suppressMessages(pam_species_thresholds(ex$cfg, min_judged = 1))
#' as.data.frame(thr)[, c("scientific_name", "threshold", "method")]
#' @export
pam_species_thresholds <- function(cfg, run_id = cfg$birdnet$run_id, tolerance = 0.05,
                                   min_judged = 10, min_coverage = 0.5, manual = NULL,
                                   write = FALSE) {
  stage <- "07_thresholds"; log_dir <- cfg$paths$logs
  val <- pam_validation_import(cfg, run_id)
  pool <- pam_validation_pool(cfg, run_id)
  metrics <- pam_validation_metrics(val, pool, unlist(cfg$validation$bands))
  default <- pam_or(cfg$processing$min_confidence, 0.5)

  out <- pam_choose_thresholds(metrics, tolerance = tolerance, min_judged = min_judged,
                               min_coverage = min_coverage, default = default, manual = manual)
  pam_log("INFO", sprintf("%d species: %d plateau, %d manual, %d default threshold",
                          nrow(out), sum(out$method == "plateau"), sum(out$method == "manual"),
                          sum(out$method == "default")), stage, log_dir)

  if (isTRUE(write)) {
    path <- file.path(cfg$paths$detections, run_id, "validation", "species_thresholds.csv")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    pam_write_csv_atomic(out, path)
    pam_log("INFO", sprintf("Species thresholds written to %s", path), stage, log_dir)
  }
  out[]
}
