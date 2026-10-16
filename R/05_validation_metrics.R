#' Wilson score confidence interval for a proportion
#'
#' @param x Number of successes (vector).
#' @param n Number of trials (vector, same length).
#' @param conf Confidence level.
#' @return A data.table with `low` and `high` (NA where `n` is 0).
#' @export
#' @examples
#' pam_wilson_ci(c(18, 5), c(25, 5))
pam_wilson_ci <- function(x, n, conf = 0.95) {
  z <- stats::qnorm(1 - (1 - conf) / 2)
  p <- ifelse(n > 0, x / n, NA_real_)
  denom <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / denom
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
  data.table::data.table(low = pmax(0, centre - half), high = pmin(1, centre + half))
}

#' Join the reviewed verdicts to the sample table
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @return A data.table: one row per reviewed sample, with `verdict`
#'   ("correct", "incorrect", "unsure"), `true_species`, `note`, `reviewer`,
#'   `reviewed_at` added to the sample columns.
#' @export
pam_validation_import <- function(cfg, run_id = cfg$birdnet$run_id) {
  val_dir <- file.path(cfg$paths$detections, run_id, "validation")
  samples_path <- file.path(val_dir, "validation_samples.csv")
  results_path <- file.path(val_dir, "validation_results.csv")
  if (!file.exists(samples_path) || !file.exists(results_path)) {
    rlang::abort("Sample or results file missing. Draw samples and review them first.")
  }
  samples <- data.table::fread(samples_path)
  results <- data.table::fread(
    results_path, colClasses = list(character = c("verdict", "true_species", "note",
                                                  "reviewer", "reviewed_at")))
  results <- unique(results, by = "sample_id", fromLast = TRUE)
  val <- merge(samples, results, by = "sample_id")
  val[, verdict := tolower(trimws(verdict))]
  val[]
}

#' Precision by species and confidence band, and by confidence threshold
#'
#' @param val Reviewed samples from `pam_validation_import()`.
#' @param pool Pool of all events from `pam_validation_pool()`; its cell sizes
#'   weight the threshold estimates, because sampling is stratified.
#' @param bands Confidence band edges used when sampling.
#' @return A list:
#'   * `cells`: per species x band: `n_pool`, `n_reviewed`, `n_correct`,
#'     `n_incorrect`, `n_unsure`, `n_judged`, `precision` and its 95% Wilson
#'     interval (unsure verdicts are excluded from precision).
#'   * `thresholds`: for each species (and "ALL") and each band edge, the
#'     estimated precision of all events at or above that confidence, weighted
#'     by band size, plus `coverage` (share of those events that sit in bands
#'     with at least one judged sample).
#'   * `confusion`: counts of predicted species vs the true species entered for
#'     incorrect verdicts.
#' @details Recall, false negatives and F1 cannot be estimated from reviewing
#'   detections alone: they need a set of recordings in which every call has
#'   been annotated independently of the detector.
#' @export
pam_validation_metrics <- function(val, pool, bands) {
  v <- data.table::copy(val)
  v[, band_idx := pam_band_index(confidence, bands)]
  rev <- v[, .(n_reviewed = .N, n_correct = sum(verdict == "correct"),
               n_incorrect = sum(verdict == "incorrect"), n_unsure = sum(verdict == "unsure")),
           by = .(scientific_name, band_idx)]
  p <- data.table::copy(pool)
  p[, band_idx := pam_band_index(confidence, bands)]
  sizes <- p[, .(n_pool = .N), by = .(scientific_name, band_idx)]
  cells <- merge(sizes, rev, by = c("scientific_name", "band_idx"), all.x = TRUE)
  for (cn in c("n_reviewed", "n_correct", "n_incorrect", "n_unsure")) {
    data.table::set(cells, which(is.na(cells[[cn]])), cn, 0L)
  }
  cells[, n_judged := n_correct + n_incorrect]
  ci <- pam_wilson_ci(cells$n_correct, cells$n_judged)
  cells[, `:=`(band = pam_band_label(band_idx, bands),
               precision = ifelse(n_judged > 0, n_correct / n_judged, NA_real_),
               ci_low = ci$low, ci_high = ci$high)]
  data.table::setorder(cells, scientific_name, band_idx)

  summarise_cells <- function(s, lo) {
    j <- s$n_judged > 0
    tot <- sum(s$n_pool)
    data.table::data.table(
      min_confidence = lo, n_events = tot,
      coverage = if (tot > 0) sum(s$n_pool[j]) / tot else NA_real_,
      precision_est = if (any(j)) sum(s$n_pool[j] * s$precision[j]) / sum(s$n_pool[j]) else NA_real_)
  }
  thr <- data.table::rbindlist(lapply(seq_len(length(bands) - 1L), function(i) {
    lo <- bands[i]
    sub <- cells[band_idx >= i]
    by_sp <- sub[, summarise_cells(.SD, lo), by = scientific_name]
    all_sp <- summarise_cells(sub, lo)[, scientific_name := "ALL"]
    data.table::rbindlist(list(all_sp, by_sp), use.names = TRUE)
  }))
  data.table::setcolorder(thr, "scientific_name")

  confusion <- v[verdict == "incorrect",
                 .(predicted = scientific_name,
                   true_species = data.table::fifelse(is.na(true_species) | true_species == "",
                                                      "(not given)", true_species))][
                                                        , .N, by = .(predicted, true_species)][order(-N)]
  list(cells = cells[], thresholds = thr[], confusion = confusion[])
}

#' Validation report: precision tables written to disk
#'
#' Imports the reviewed verdicts, computes `pam_validation_metrics()` and
#' writes `precision_by_cell.csv`, `precision_by_threshold.csv` and
#' `confusion_incorrect.csv` to `<detections>/<run_id>/validation/`.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param pool Optional pool from `pam_validation_pool()`.
#' @return The metrics list (see `pam_validation_metrics()`).
#' @export
pam_validation_report <- function(cfg, run_id = cfg$birdnet$run_id, pool = NULL) {
  val <- pam_validation_import(cfg, run_id)
  if (is.null(pool)) pool <- pam_validation_pool(cfg, run_id)
  m <- pam_validation_metrics(val, pool, unlist(cfg$validation$bands))
  out_dir <- file.path(cfg$paths$detections, run_id, "validation")
  data.table::fwrite(m$cells, file.path(out_dir, "precision_by_cell.csv"))
  data.table::fwrite(m$thresholds, file.path(out_dir, "precision_by_threshold.csv"))
  data.table::fwrite(m$confusion, file.path(out_dir, "confusion_incorrect.csv"))
  pam_log("INFO", sprintf("%d reviewed samples (%d unsure); tables written to %s",
                          nrow(val), sum(val$verdict == "unsure"), out_dir),
          "05_report", cfg$paths$logs)
  m
}
