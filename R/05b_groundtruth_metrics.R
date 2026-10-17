#' Species lists of the annotations in long format (internal)
#'
#' @param truth Annotation table with `segment_id`, `present`, `possible`.
#' @return A data.table `segment_id`, `scientific_name`, `status` ("present" or
#'   "possible"; "present" wins when both were given).
#' @keywords internal
#' @noRd
pam_truth_long <- function(truth) {
  expand <- function(col, status) {
    x <- strsplit(ifelse(is.na(truth[[col]]), "", truth[[col]]), ";", fixed = TRUE)
    n <- lengths(x)
    lab <- trimws(unlist(x, use.names = FALSE))
    if (is.null(lab)) lab <- character(0)
    out <- data.table::data.table(segment_id = rep(truth$segment_id, n), label = lab,
                                  status = rep(status, length(lab)))
    out[nzchar(label)]
  }
  tl <- data.table::rbindlist(list(expand("present", "present"), expand("possible", "possible")))
  if (!nrow(tl)) {
    return(data.table::data.table(segment_id = integer(), scientific_name = character(),
                                  status = character()))
  }
  tl[, scientific_name := sub("_.*$", "", label)]
  tl[, .(status = if (any(status == "present")) "present" else "possible"),
     by = .(segment_id, scientific_name)]
}

#' Segment-level recall, precision and F1 against ground truth
#'
#' The unit is a segment x species: a species is "detected" in a segment if the
#' detector has an event of that species overlapping the segment at or above
#' the threshold, and "present" if the annotator marked it. Possibly-present
#' pairs are left out of the counts.
#'
#' @param truth Annotation table (`segment_id`, `present`, `possible`).
#' @param segments Segment table (`segment_id`, `rel`, `seg_start`, `seg_end`).
#' @param events Detector events from `pam_validation_pool()` (`rel`,
#'   `start_time`, `end_time`, `scientific_name`, `confidence`).
#' @param classes Scientific names of the classifier's classes.
#' @param thresholds Confidence thresholds to evaluate.
#' @return A data.table with one row per species (and "ALL", summed over
#'   species) and threshold: `tp`, `fn`, `fp`, `tn`, `n_present`, `recall`,
#'   `recall_low`, `recall_high`, `precision`, `precision_low`,
#'   `precision_high`, `f1`.
#' @details With simple random sampling of segments the estimates apply to the
#'   sampled recordings and hours. A species that is rarely present in random
#'   segments has few `n_present` and an uncertain recall.
#' @export
pam_recall_metrics <- function(truth, segments, events, classes = NULL,
                               thresholds = c(0.3, 0.4, 0.5, 0.7)) {
  ann <- merge(segments[, .(segment_id, rel, seg_start, seg_end)], truth[, .(segment_id)],
               by = "segment_id")
  tl <- pam_truth_long(truth[segment_id %in% ann$segment_id])
  classes <- unique(c(classes, events$scientific_name))
  tl_model <- tl[scientific_name %in% classes]

  hits <- events[ann, on = .(rel, start_time < seg_end, end_time > seg_start),
                 nomatch = NULL, allow.cartesian = TRUE,
                 .(segment_id = i.segment_id, scientific_name = x.scientific_name,
                   confidence = x.confidence)]
  grid <- data.table::CJ(segment_id = ann$segment_id, scientific_name = classes)
  grid <- merge(grid, tl_model, by = c("segment_id", "scientific_name"), all.x = TRUE)

  one_threshold <- function(t) {
    d <- unique(hits[confidence >= t, .(segment_id, scientific_name)])[, detected := TRUE]
    g <- merge(grid, d, by = c("segment_id", "scientific_name"), all.x = TRUE)
    g[is.na(detected), detected := FALSE]
    g <- g[is.na(status) | status == "present"]
    g[, .(tp = sum(status %in% "present" & detected), fn = sum(status %in% "present" & !detected),
          fp = sum(is.na(status) & detected), tn = sum(is.na(status) & !detected)),
      by = scientific_name][, threshold := t]
  }
  by_sp <- data.table::rbindlist(lapply(thresholds, one_threshold))
  all_sp <- by_sp[, .(tp = sum(tp), fn = sum(fn), fp = sum(fp), tn = sum(tn)),
                  by = threshold][, scientific_name := "ALL"]
  out <- data.table::rbindlist(list(all_sp, by_sp), use.names = TRUE)
  out[, n_present := tp + fn]
  rc <- pam_wilson_ci(out$tp, out$tp + out$fn)
  pc <- pam_wilson_ci(out$tp, out$tp + out$fp)
  out[, `:=`(recall = ifelse(tp + fn > 0, tp / (tp + fn), NA_real_),
             recall_low = rc$low, recall_high = rc$high,
             precision = ifelse(tp + fp > 0, tp / (tp + fp), NA_real_),
             precision_low = pc$low, precision_high = pc$high,
             f1 = ifelse(2 * tp + fp + fn > 0, 2 * tp / (2 * tp + fp + fn), NA_real_))]
  data.table::setcolorder(out, c("scientific_name", "threshold", "n_present", "tp", "fn", "fp",
                                 "tn", "recall", "recall_low", "recall_high", "precision",
                                 "precision_low", "precision_high", "f1"))
  data.table::setorder(out, threshold, scientific_name)
  out[]
}

#' Recall report for a detection run
#'
#' Compares a run's detections with the ground-truth annotations and writes
#' `recall_by_species_threshold.csv` to `<detections>/<run_id>/validation/`.
#' Only annotated segments from recordings the run processed are used.
#'
#' @param cfg A `pam_config` object.
#' @param run_id Detection run.
#' @param thresholds Confidence thresholds. Default: the band edges of
#'   `validation$bands` except the last.
#' @param pool Optional pool from `pam_validation_pool()`.
#' @return A list: `metrics` (see `pam_recall_metrics()`), `n_segments`,
#'   `n_no_species`, `n_other_only`.
#' @export
pam_recall_report <- function(cfg, run_id = cfg$birdnet$run_id, thresholds = NULL, pool = NULL) {
  gt_dir <- pam_gt_dir(cfg)
  seg_path <- file.path(gt_dir, "recall_segments.csv")
  res_path <- file.path(gt_dir, "recall_annotations.csv")
  if (!file.exists(seg_path) || !file.exists(res_path)) {
    rlang::abort("Segments or annotations missing. Draw, export and annotate segments first.")
  }
  seg <- data.table::fread(seg_path)
  truth <- data.table::fread(res_path, colClasses = list(
    character = c("present", "possible", "other", "note", "reviewer", "reviewed_at")))
  truth <- unique(truth, by = "segment_id", fromLast = TRUE)

  fr <- file.path(cfg$paths$detections, run_id, "file_results.csv")
  if (file.exists(fr)) {
    done <- data.table::fread(fr)[ok == TRUE, rel]
    keep <- seg[rel %in% done, segment_id]
    if (length(keep) < nrow(seg)) {
      warning(nrow(seg) - length(keep), " segments are from recordings this run did not process; ignored")
    }
    seg <- seg[segment_id %in% keep]
    truth <- truth[segment_id %in% keep]
  }
  if (!nrow(truth)) rlang::abort("No annotated segments from recordings of this run")

  if (is.null(pool)) pool <- pam_validation_pool(cfg, run_id)
  if (is.null(thresholds)) {
    b <- unlist(cfg$validation$bands); thresholds <- b[-length(b)]
  }
  labels <- tryCatch(readLines(pam_detect_settings(cfg)$labels_file, warn = FALSE),
                     error = function(e) character())
  classes <- unique(sub("_.*$", "", labels[nzchar(labels)]))

  metrics <- pam_recall_metrics(truth, seg, pool, classes, thresholds)
  out_dir <- file.path(cfg$paths$detections, run_id, "validation")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(metrics, file.path(out_dir, "recall_by_species_threshold.csv"))
  pam_log("INFO", sprintf("recall report on %d annotated segments written to %s",
                          nrow(truth), out_dir), "05b_report", cfg$paths$logs)
  list(metrics = metrics, n_segments = nrow(truth),
       n_no_species = sum(truth$none_audible %in% TRUE),
       n_other_only = sum(!truth$none_audible %in% TRUE & !nzchar(truth$present) & nzchar(truth$other)))
}
