#' Follow audio files through the workflow
#'
#' Collects, for every audio file, what each stage recorded about it: the
#' standardization result (Stage 0), the scan and QC flags (Stage 1), filtering
#' (Stage 2), detection (Stage 3), cleaning (Stage 4), validation (Stage 5),
#' ground-truth annotation (Stage 5b) and whether it went into the occupancy
#' histories (Stage 6). It reads the files the stages already write, so it works
#' on existing projects and changes nothing unless you ask it to write.
#'
#' @param cfg A `pam_config` object.
#' @param file Optional audio file to look up: a path relative to the
#'   standardized audio folder (such as `"G0059/G0059_20260405_183000.wav"`), a
#'   file name, or, for files standardized by Stage 0, the name of the raw file.
#'   `NULL` (the default) returns every file.
#' @param run_id Optional detection run (or runs). `NULL` (the default)
#'   includes every run found in the project.
#' @param wide If `TRUE`, return one row per file with one column per stage
#'   (and per run, for the stages that belong to a run) holding the status.
#' @param write If `TRUE`, also save the long table to
#'   `metadata/audio_history.csv`. Nothing is written by default.
#' @return A data.table. The long table has one row per file and stage (and
#'   run) with columns `rel` (path relative to the standardized audio folder,
#'   `NA` for files Stage 0 set aside), `file` (file name), `stage`, `run_id`,
#'   `status`, `detail` (what happened, in words), `n` (a count, such as the
#'   number of detections) and `time` (when the stage recorded it, where the
#'   stage keeps a time, otherwise the time its output file was written). The
#'   attribute `stages_found` lists the stages whose outputs were found. With
#'   `wide = TRUE` the table has `rel` plus one status column per stage.
#' @details Statuses: Stage 0 `ok`, `warning` or `failed`; Stage 1 `pass` or
#'   `fail`; Stage 2 and 3 `ok` or `failed`; Stage 4 `kept` (some events
#'   survived cleaning) or `removed` (none did); Stage 5 `reviewed` or
#'   `sampled`; Stage 5b `annotated`, `partly annotated` or `drawn`; Stage 6
#'   `included` or `excluded`. Stages whose outputs are missing are skipped.
#'   Times are saved in UTC when `write = TRUE`. The history is built from the
#'   current outputs, so a stage you delete or rerun is shown as it now is.
#' @examples
#' ex <- pam_example_project()
#' res <- suppressMessages(pam_scan_audio(ex$cfg))
#' proc <- suppressMessages(pam_process_detections(ex$cfg))
#'
#' # one row per file and stage
#' hist <- pam_audio_history(ex$cfg)
#' as.data.frame(hist)[1:3, c("file", "stage", "status", "detail")]
#'
#' # one file, by name
#' one <- pam_audio_history(ex$cfg, file = "G0059_20260405_183004.wav")
#' as.data.frame(one)[, c("stage", "status", "detail")]
#'
#' # one row per file, one column per stage
#' as.data.frame(pam_audio_history(ex$cfg, wide = TRUE))
#' @export
pam_audio_history <- function(cfg, file = NULL, run_id = NULL, wide = FALSE, write = FALSE) {
  if (is.null(cfg$paths$audio_standardized)) {
    rlang::abort("`cfg` must be a pamflow configuration (see pam_config_read())")
  }
  stages <- c("0 standardize", "1 scan", "2 filter", "3 detect", "4 process",
              "5 validation", "5b recall", "6 occupancy")
  runs <- pam_history_runs(cfg, run_id)

  parts <- c(
    list(pam_history_try("0 standardize", pam_history_standardize(cfg)),
         pam_history_try("1 scan", pam_history_scan(cfg)),
         pam_history_try("2 filter", pam_history_filter(cfg))),
    lapply(runs$detections, function(r) pam_history_try("3 detect", pam_history_detect(cfg, r))),
    lapply(runs$detections, function(r) pam_history_try("4 process", pam_history_process(cfg, r))),
    lapply(runs$detections, function(r) pam_history_try("5 validation", pam_history_validation(cfg, r))),
    list(pam_history_try("5b recall", pam_history_recall(cfg))),
    lapply(runs$occupancy, function(r) pam_history_try("6 occupancy", pam_history_occupancy(cfg, r))))
  parts <- Filter(Negate(is.null), parts)
  found <- unique(unlist(lapply(parts, function(p) as.character(p$stage[1L]))))
  found <- stages[stages %in% found]

  hist <- if (length(parts)) data.table::rbindlist(parts, use.names = TRUE) else pam_history_empty()
  if (!length(parts)) {
    rlang::warn(sprintf("No stage outputs found for the project in %s", cfg$paths$project_root))
  }

  if (!is.null(file)) {
    file <- as.character(file)
    hit <- hist$rel %in% file | hist$file %in% file | hist$source_file %in% file
    hit_rel <- unique(hist$rel[hit & !is.na(hist$rel)])
    keep <- (!is.na(hist$rel) & hist$rel %in% hit_rel) | (is.na(hist$rel) & hit)
    hist <- hist[keep]
  }
  data.table::set(hist, j = "source_file", value = NULL)
  hist <- hist[order(hist$rel, match(hist$stage, stages), hist$run_id)]
  data.table::setcolorder(hist, c("rel", "file", "stage", "run_id", "status", "detail", "n", "time"))

  if (isTRUE(write)) {
    path <- file.path(cfg$paths$metadata, "audio_history.csv")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    data.table::fwrite(hist, path)
    message("Audio history written to ", path)
  }

  out <- if (isTRUE(wide)) pam_history_wide(hist, stages) else hist
  data.table::setattr(out, "stages_found", found)
  out
}

# ---- helpers ---------------------------------------------------------------------------

#' Empty history table (internal)
#' @return A zero-row data.table with the history columns.
#' @keywords internal
#' @noRd
pam_history_empty <- function() {
  data.table::data.table(
    rel = character(), file = character(), stage = character(), run_id = character(),
    status = character(), detail = character(), n = integer(), time = as.POSIXct(character()),
    source_file = character())
}

#' Build history rows (internal)
#'
#' @param rel Paths relative to the standardized audio folder (`NA` allowed).
#' @param stage Stage label.
#' @param status,detail,n,time,run_id,file,source_file Vectors or single values.
#' @return A data.table of history rows.
#' @keywords internal
#' @noRd
pam_history_rows <- function(rel, stage, status, detail = NA_character_, n = NA_integer_,
                             time = as.POSIXct(NA), run_id = NA_character_,
                             file = basename(rel), source_file = NA_character_) {
  if (!length(rel)) return(pam_history_empty())
  data.table::data.table(
    rel = as.character(rel), file = as.character(file), stage = stage, run_id = as.character(run_id),
    status = as.character(status), detail = as.character(detail), n = as.integer(n),
    time = time, source_file = as.character(source_file))
}

#' Read a stage output if it exists (internal)
#'
#' @param path CSV path.
#' @param select Columns wanted; only those present are read.
#' @param char Columns to read as text.
#' @return A data.table, or NULL if the file is missing or empty.
#' @keywords internal
#' @noRd
pam_history_read <- function(path, select, char = character()) {
  if (!file.exists(path) || file.size(path) == 0L) return(NULL)
  header <- names(data.table::fread(path, nrows = 0L))
  select <- intersect(select, header)
  if (!length(select)) return(NULL)
  as_text <- intersect(char, select)
  out <- if (length(as_text)) {
    data.table::fread(path, select = select, colClasses = list(character = as_text))
  } else {
    data.table::fread(path, select = select)
  }
  if (!nrow(out)) NULL else out
}

#' Run a stage reader, warn instead of failing (internal)
#'
#' @param stage Stage label, used in the warning.
#' @param expr The reader call.
#' @return Its result, or NULL if it failed.
#' @keywords internal
#' @noRd
pam_history_try <- function(stage, expr) {
  tryCatch(expr, error = function(e) {
    rlang::warn(sprintf("Could not read the outputs of stage %s: %s", stage, conditionMessage(e)))
    NULL
  })
}

#' Join flag texts, leaving out the empty ones (internal)
#'
#' @param ... Character vectors of equal length with `NA` where a flag does not apply.
#' @return A character vector: the flags joined with "; ", or `NA` if none.
#' @keywords internal
#' @noRd
pam_history_join <- function(...) {
  Reduce(function(a, b) {
    ifelse(is.na(b), a, ifelse(is.na(a), b, paste(a, b, sep = "; ")))
  }, list(...))
}

#' Text for a flag that applies where `cond` is TRUE (internal)
#' @param cond Logical vector.
#' @param text Flag text.
#' @return Character vector, `NA` where the flag does not apply.
#' @keywords internal
#' @noRd
pam_history_flag <- function(cond, text) ifelse(cond %in% TRUE, text, NA_character_)

#' Detection and occupancy runs to look at (internal)
#'
#' @param cfg A `pam_config` object.
#' @param run_id Requested runs, or NULL for all found.
#' @return A list with `detections` and `occupancy`, each a character vector of run names.
#' @keywords internal
#' @noRd
pam_history_runs <- function(cfg, run_id) {
  subdirs <- function(dir) {
    if (is.null(dir) || !dir.exists(dir)) return(character())
    list.dirs(dir, recursive = FALSE, full.names = FALSE)
  }
  det <- subdirs(cfg$paths$detections)
  occ <- subdirs(cfg$paths$occupancy)
  if (!is.null(run_id)) {
    det <- intersect(det, as.character(run_id))
    occ <- intersect(occ, as.character(run_id))
  }
  list(detections = det, occupancy = occ)
}

#' Path relative to the standardized audio folder (internal)
#' @param path Full paths.
#' @param root The standardized audio folder.
#' @return Relative paths, `NA` for paths that are not inside `root`.
#' @keywords internal
#' @noRd
pam_history_rel <- function(path, root) {
  path <- as.character(path)
  root <- sub("/+$", "", gsub("\\\\", "/", root))
  p <- gsub("\\\\", "/", path)
  inside <- !is.na(p) & startsWith(p, paste0(root, "/"))
  out <- rep(NA_character_, length(p))
  out[inside] <- substring(p[inside], nchar(root) + 2L)
  out
}

# ---- one reader per stage --------------------------------------------------------------

#' Stage 0 rows from `standardization_log.csv` (internal)
#' @param cfg A `pam_config` object.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_standardize <- function(cfg) {
  path <- file.path(cfg$paths$audio_standardized, "standardization_log.csv")
  x <- pam_history_read(path, c("source_path", "dest_path", "category", "action", "status", "message"))
  if (is.null(x)) return(NULL)
  rel <- pam_history_rel(x$dest_path, cfg$paths$audio_standardized)
  shown <- ifelse(is.na(rel), basename(ifelse(is.na(x$dest_path), x$source_path, x$dest_path)),
                  basename(rel))
  status <- c(SUCCESS = "ok", WARN = "warning", ERROR = "failed")[toupper(as.character(x$status))]
  status[is.na(status)] <- tolower(as.character(x$status))[is.na(status)]
  detail <- pam_history_join(
    as.character(x$action), paste("from", x$source_path),
    ifelse(is.na(x$message) | !nzchar(x$message), NA_character_, as.character(x$message)))
  pam_history_rows(rel, "0 standardize", unname(status), detail, time = file.mtime(path),
                   file = shown, source_file = basename(as.character(x$source_path)))
}

#' Stage 1 rows from the master table (internal)
#' @param cfg A `pam_config` object.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_scan <- function(cfg) {
  path <- file.path(cfg$paths$metadata, "audio_master.csv")
  m <- pam_history_read(path, c("file_path", "valid_name", "readable", "truncated", "short",
                                "duplicate", "gap_before", "overlap_before", "qc_pass",
                                "in_deployment", "deployment_id"), char = "file_path")
  if (is.null(m)) return(NULL)
  rel <- pam_history_rel(m$file_path, cfg$paths$audio_standardized)
  col <- function(nm) if (nm %in% names(m)) m[[nm]] else rep(NA, nrow(m))
  detail <- pam_history_join(
    pam_history_flag(!col("valid_name"), "invalid file name"),
    pam_history_flag(!col("readable"), "unreadable"),
    pam_history_flag(col("truncated"), "truncated"),
    pam_history_flag(col("duplicate"), "duplicate"),
    pam_history_flag(!col("in_deployment"), "outside any deployment"),
    pam_history_flag(col("short"), "shorter than the usual file"),
    pam_history_flag(col("gap_before"), "gap before this file"),
    pam_history_flag(col("overlap_before"), "overlaps the previous file"),
    ifelse(col("in_deployment") %in% TRUE & !is.na(col("deployment_id")),
           paste("deployment", col("deployment_id")), NA_character_))
  status <- ifelse(col("qc_pass") %in% TRUE, "pass", "fail")
  pam_history_rows(rel, "1 scan", status, detail, time = file.mtime(path))
}

#' Stage 2 rows from the filter results (internal)
#' @param cfg A `pam_config` object.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_filter <- function(cfg) {
  path <- file.path(cfg$paths$metadata, "02_filter_results.csv")
  x <- pam_history_read(path, c("rel", "ok", "verified", "message"), char = c("rel", "message"))
  if (is.null(x)) return(NULL)
  x <- unique(x, by = "rel", fromLast = TRUE)               # a rerun adds rows; keep the latest
  good <- if ("verified" %in% names(x)) x$verified %in% TRUE else x$ok %in% TRUE
  msg <- if ("message" %in% names(x)) as.character(x$message) else rep(NA_character_, nrow(x))
  pam_history_rows(x$rel, "2 filter", ifelse(good, "ok", "failed"),
                   ifelse(is.na(msg) | !nzchar(msg), NA_character_, msg), time = file.mtime(path))
}

#' Stage 3 rows of one run from `file_results.csv` (internal)
#' @param cfg A `pam_config` object.
#' @param run Run name.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_detect <- function(cfg, run) {
  path <- file.path(cfg$paths$detections, run, "file_results.csv")
  x <- pam_history_read(path, c("rel", "ok", "n_detections", "seconds", "message"),
                        char = c("rel", "message"))
  if (is.null(x)) return(NULL)
  x <- unique(x, by = "rel", fromLast = TRUE)
  none <- rep(NA_character_, nrow(x))
  n <- if ("n_detections" %in% names(x)) x$n_detections else rep(NA_integer_, nrow(x))
  secs <- if ("seconds" %in% names(x)) ifelse(is.na(x$seconds), NA_character_,
                                              paste(x$seconds, "s")) else none
  msg <- if ("message" %in% names(x)) ifelse(is.na(x$message) | !nzchar(x$message),
                                             NA_character_, as.character(x$message)) else none
  pam_history_rows(x$rel, "3 detect", ifelse(x$ok %in% TRUE, "ok", "failed"),
                   pam_history_join(secs, msg), n = n, time = file.mtime(path), run_id = run)
}

#' Stage 4 rows of one run from the cleaned and removed detections (internal)
#' @param cfg A `pam_config` object.
#' @param run Run name.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_process <- function(cfg, run) {
  dir <- file.path(cfg$paths$detections, run, "processed")
  clean_path <- file.path(dir, "detections_clean.csv")
  removed_path <- file.path(dir, "removed_detections.csv")
  clean <- pam_history_read(clean_path, "rel", char = "rel")
  removed <- pam_history_read(removed_path, c("rel", "reason"), char = c("rel", "reason"))
  if (is.null(clean) && is.null(removed)) return(NULL)
  if (is.null(clean)) {
    kept <- data.table::data.table(rel = character(), kept = integer())
  } else {
    kept <- clean[, .(kept = .N), by = rel]
  }
  if (is.null(removed)) {
    why <- data.table::data.table(rel = character(), why = character())
  } else {
    why <- removed[, .N, by = .(rel, reason)][
      , .(why = paste0(reason, " (", N, ")", collapse = "; ")), by = rel]
  }
  both <- merge(kept, why, by = "rel", all = TRUE)
  both$kept[is.na(both$kept)] <- 0L
  detail <- paste0(both$kept, " event", ifelse(both$kept == 1L, "", "s"), " kept",
                   ifelse(is.na(both$why), "", paste0("; removed: ", both$why)))
  time <- file.mtime(if (file.exists(clean_path)) clean_path else removed_path)
  pam_history_rows(both$rel, "4 process", ifelse(both$kept > 0L, "kept", "removed"), detail,
                   n = both$kept, time = time, run_id = run)
}

#' Parse review times written by the apps (internal)
#' @param x Character times like "2026-04-05 18:30:00".
#' @return POSIXct vector.
#' @keywords internal
#' @noRd
pam_history_time <- function(x) {
  as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

#' Stage 5 rows of one run from the validation samples and verdicts (internal)
#' @param cfg A `pam_config` object.
#' @param run Run name.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_validation <- function(cfg, run) {
  dir <- file.path(cfg$paths$detections, run, "validation")
  samples_path <- file.path(dir, "validation_samples.csv")
  s <- pam_history_read(samples_path, c("sample_id", "rel"), char = "rel")
  if (is.null(s)) return(NULL)
  r <- pam_history_read(file.path(dir, "validation_results.csv"),
                        c("sample_id", "verdict", "reviewed_at"), char = c("verdict", "reviewed_at"))
  if (is.null(r)) {
    r <- data.table::data.table(sample_id = integer(), verdict = character(), reviewed_at = character())
  }
  r <- unique(r, by = "sample_id", fromLast = TRUE)
  j <- merge(s, r, by = "sample_id", all.x = TRUE)
  agg <- j[, .(n = .N,
               n_done = sum(!is.na(verdict)),
               n_correct = sum(verdict %in% "correct"),
               n_wrong = sum(verdict %in% "incorrect"),
               n_unsure = sum(verdict %in% "unsure"),
               last = if (all(is.na(reviewed_at))) NA_character_ else max(reviewed_at, na.rm = TRUE)),
           by = rel]
  detail <- sprintf("%d sampled, %d reviewed (%d correct, %d incorrect, %d unsure)",
                    agg$n, agg$n_done, agg$n_correct, agg$n_wrong, agg$n_unsure)
  pam_history_rows(agg$rel, "5 validation", ifelse(agg$n_done > 0L, "reviewed", "sampled"), detail,
                   n = agg$n, time = pam_history_time(agg$last), run_id = run)
}

#' Stage 5b rows from the recall segments and annotations (internal)
#' @param cfg A `pam_config` object.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_recall <- function(cfg) {
  dir <- file.path(cfg$paths$validation, "ground_truth")
  s <- pam_history_read(file.path(dir, "recall_segments.csv"), c("segment_id", "rel"), char = "rel")
  if (is.null(s)) return(NULL)
  a <- pam_history_read(file.path(dir, "recall_annotations.csv"),
                        c("segment_id", "reviewed_at"), char = "reviewed_at")
  if (is.null(a)) a <- data.table::data.table(segment_id = integer(), reviewed_at = character())
  a <- unique(a, by = "segment_id", fromLast = TRUE)
  j <- merge(s, a, by = "segment_id", all.x = TRUE)
  agg <- j[, .(n = .N, n_done = sum(!is.na(reviewed_at)),
               last = if (all(is.na(reviewed_at))) NA_character_ else max(reviewed_at, na.rm = TRUE)),
           by = rel]
  status <- ifelse(agg$n_done == 0L, "drawn", ifelse(agg$n_done < agg$n, "partly annotated", "annotated"))
  detail <- sprintf("%d of %d segments annotated", agg$n_done, agg$n)
  pam_history_rows(agg$rel, "5b recall", status, detail, n = agg$n,
                   time = pam_history_time(agg$last))
}

#' Stage 6 rows of one run: was the file used for the histories? (internal)
#' @param cfg A `pam_config` object.
#' @param run Run name.
#' @return History rows, or NULL.
#' @keywords internal
#' @noRd
pam_history_occupancy <- function(cfg, run) {
  summary_path <- file.path(cfg$paths$occupancy, run, "occupancy_summary.csv")
  if (!file.exists(summary_path)) return(NULL)
  m <- pam_history_read(file.path(cfg$paths$metadata, "audio_master.csv"),
                        c("file_path", "qc_pass", "in_deployment"), char = "file_path")
  if (is.null(m)) return(NULL)
  used <- m$qc_pass %in% TRUE & m$in_deployment %in% TRUE
  why <- pam_history_join(pam_history_flag(!m$qc_pass %in% TRUE, "failed QC"),
                          pam_history_flag(!m$in_deployment %in% TRUE, "outside any deployment"))
  pam_history_rows(pam_history_rel(m$file_path, cfg$paths$audio_standardized), "6 occupancy",
                   ifelse(used, "included", "excluded"), why, time = file.mtime(summary_path),
                   run_id = run)
}

#' One row per file, one status column per stage (internal)
#'
#' @param hist The long history table.
#' @param stages Stage labels in order.
#' @return A wide data.table.
#' @keywords internal
#' @noRd
pam_history_wide <- function(hist, stages) {
  if (!nrow(hist)) return(data.table::data.table(rel = character()))
  key <- ifelse(is.na(hist$rel), paste0("[set aside] ", hist$file), hist$rel)
  col <- ifelse(is.na(hist$run_id), hist$stage, paste0(hist$stage, " [", hist$run_id, "]"))
  d <- data.table::data.table(rel = key, col = col, status = hist$status)
  wide <- data.table::dcast(d, rel ~ col, value.var = "status",
                            fun.aggregate = function(x) x[length(x)], fill = NA_character_)
  cols <- setdiff(names(wide), "rel")
  stage_of <- vapply(strsplit(cols, " \\["), `[`, character(1), 1L)
  data.table::setcolorder(wide, c("rel", cols[order(match(stage_of, stages), cols)]))
  wide[]
}
