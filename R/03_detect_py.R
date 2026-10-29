#' Choose the number of BirdNET worker processes (internal)
#'
#' Pure function (the machine's core counts are arguments), so it can be
#' tested. The user's value is respected. Without one, half of the physical
#' cores are used, so the machine stays usable. A value that would use every
#' core triggers a note, and a value above the logical core count is reduced.
#'
#' @param requested Requested workers (`birdnet$workers`), or NULL/NA.
#' @param physical Physical core count.
#' @param logical Logical core count.
#' @return A list: `workers` (integer) and `notes` (character, may be empty).
#' @keywords internal
#' @noRd
pam_birdnet_resolve_workers <- function(requested = NULL,
                                        physical = parallel::detectCores(logical = FALSE),
                                        logical = parallel::detectCores(logical = TRUE)) {
  physical <- if (length(physical) != 1L || is.na(physical) || physical < 1) 1L else as.integer(physical)
  logical <- if (length(logical) != 1L || is.na(logical) || logical < physical) physical else as.integer(logical)
  if (is.null(requested) || length(requested) != 1L || is.na(requested)) {
    workers <- max(1L, physical %/% 2L)
    return(list(workers = workers,
                notes = sprintf("birdnet$workers not set: using %d (half of the %d physical cores)",
                                workers, physical)))
  }
  if (!is.numeric(requested) || requested < 1 || requested != round(requested)) {
    rlang::abort("birdnet$workers must be a whole number >= 1")
  }
  workers <- as.integer(requested)
  notes <- character()
  if (workers > logical) {
    notes <- sprintf("birdnet$workers = %d is more than the %d logical cores: using %d",
                     workers, logical, logical)
    workers <- logical
  } else if (workers >= physical) {
    notes <- sprintf(paste0("birdnet$workers = %d uses all %d physical cores: the computer will be ",
                            "slow for other work. Consider %d or fewer."),
                     workers, physical, max(1L, physical - 2L))
  }
  list(workers = workers, notes = notes)
}

#' Path of the Python batch script shipped with pamflow (internal)
#'
#' @return Path to `pam_birdnet_predict.py` (empty string if not found).
#' @keywords internal
#' @noRd
pam_birdnet_py_script <- function() {
  system.file("python", "pam_birdnet_predict.py", package = "pamflow")
}

#' Format a number for the command line (internal)
#'
#' @param x A number.
#' @return A string without scientific notation.
#' @keywords internal
#' @noRd
pam_fmt_num <- function(x) format(x, scientific = FALSE, trim = TRUE, digits = 15)

#' Arguments for the Python batch script (internal)
#'
#' Pure function (no I/O).
#'
#' @param s Settings list from `pam_detect_settings()`.
#' @param files_file Text file listing the audio files of the batch.
#' @param out_file Detections CSV to be written.
#' @param status_file Per-file status CSV to be written.
#' @param check If TRUE, build the model-only `--check` call instead.
#' @return Character vector of arguments (script path first).
#' @keywords internal
#' @noRd
pam_birdnet_py_args <- function(s, files_file = NULL, out_file = NULL, status_file = NULL,
                                check = FALSE) {
  base <- c(s$script, "--model", s$model_file, "--labels", s$labels_file,
            "--version", s$model_version)
  if (check) return(c(base, "--check"))
  fmin <- if (isTRUE(s$use_bandpass)) s$bandpass_fmin else 0L
  fmax <- if (isTRUE(s$use_bandpass)) s$bandpass_fmax else 15000L
  c(base,
    "--files", files_file, "--out", out_file, "--status", status_file,
    "--min-confidence", pam_fmt_num(s$min_confidence),
    "--overlap", pam_fmt_num(s$overlap_s),
    "--fmin", pam_fmt_num(fmin), "--fmax", pam_fmt_num(fmax),
    "--batch-size", pam_fmt_num(s$py_batch_size),
    "--n-workers", pam_fmt_num(s$workers),
    "--n-producers", pam_fmt_num(s$n_producers),
    "--top-k", if (is.null(s$top_k)) "0" else pam_fmt_num(s$top_k),
    "--sigmoid-sensitivity", pam_fmt_num(s$sigmoid_sensitivity),
    "--device", s$device,
    "--skip-validity-check")        # checked once per run by pam_birdnet_py_check()
}

#' Load the model once to check it and report the package version (internal)
#'
#' Runs the batch script's `--check` mode, which also verifies that the labels
#' file matches the model.
#'
#' @param s Settings list from `pam_detect_settings()`.
#' @return A list: `ok`, `birdnet_version` (NA if unknown) and `message`
#'   (the last lines of output when not ok).
#' @keywords internal
#' @noRd
pam_birdnet_py_check <- function(s) {
  fail <- function(msg) list(ok = FALSE, birdnet_version = NA_character_, message = msg)
  if (!file.exists(s$python)) {
    return(fail(paste0("Python environment not found: ", s$python,
                       "\nRun pam_birdnet_setup('inference') and then pam_birdnet_doctor().")))
  }
  if (length(s$script) != 1L || !nzchar(s$script) || !file.exists(s$script)) {
    return(fail("pam_birdnet_predict.py was not found in the pamflow installation."))
  }
  log_file <- tempfile(fileext = ".log")
  on.exit(unlink(log_file), add = TRUE)
  status <- pam_run_command(s$python, pam_birdnet_py_args(s, check = TRUE), log_file)
  out <- if (file.exists(log_file)) readLines(log_file, warn = FALSE) else character()
  hit <- grep("^PAMCHECK ", out, value = TRUE)
  if (identical(status, 0L) && length(hit)) {
    ver <- sub(".*birdnet=([^ ]+).*", "\\1", hit[1L])
    return(list(ok = TRUE, birdnet_version = ver, message = ""))
  }
  list(ok = FALSE, birdnet_version = NA_character_,
       message = paste(utils::tail(out, 12L), collapse = "\n"))
}

#' Run BirdNET (Python `birdnet` package) on a batch of files (internal)
#'
#' Starts the Python batch script in a separate process. Parallelism happens
#' inside that process (`s$workers` worker processes). Returns the same
#' structure that `pam_detect()` expects from a batch runner.
#'
#' @param items List of `list(rel, path)`.
#' @param s Settings list from `pam_detect_settings()`.
#' @return A list with one element per file: `rel`, `ok`, `message`,
#'   `seconds` (batch time divided by the number of files), `det` (normalised
#'   predictions). Errors if the whole batch could not run, in which case the
#'   caller leaves the files pending.
#' @keywords internal
#' @noRd
pam_birdnet_run_batch_py <- function(items, s) {
  if (!length(items)) return(list())
  paths <- vapply(items, function(i) i$path, character(1))
  tmp <- tempfile("pam_batch_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  files_file <- file.path(tmp, "files.txt")
  out_file <- file.path(tmp, "detections.csv")
  status_file <- file.path(tmp, "status.csv")
  log_file <- file.path(tmp, "run.log")
  writeLines(enc2utf8(paths), files_file, useBytes = TRUE)

  t0 <- proc.time()[["elapsed"]]
  status <- pam_run_command(s$python, pam_birdnet_py_args(s, files_file, out_file, status_file),
                            log_file)
  elapsed <- proc.time()[["elapsed"]] - t0
  if (!identical(status, 0L) || !file.exists(out_file) || !file.exists(status_file)) {
    tail_lines <- if (file.exists(log_file)) utils::tail(readLines(log_file, warn = FALSE), 12L) else character()
    rlang::abort(c(sprintf("BirdNET batch failed (exit status %s).", status),
                   i = paste(tail_lines, collapse = "\n")))
  }

  det <- data.table::fread(out_file, encoding = "UTF-8", colClasses = list(character = "input"))
  st <- data.table::fread(status_file, encoding = "UTF-8", colClasses = list(character = c("input", "message")))
  ok_by_path <- stats::setNames(tolower(as.character(st$ok)) == "true", st$input)
  msg_by_path <- stats::setNames(ifelse(is.na(st$message), "", st$message), st$input)
  det_by_path <- if (nrow(det)) split(det, factor(det$input, levels = unique(paths))) else list()

  out <- vector("list", length(items))
  for (i in seq_along(items)) {
    p <- paths[i]
    ok <- isTRUE(unname(ok_by_path[p]))
    d <- det_by_path[[p]]
    out[[i]] <- list(
      rel = items[[i]]$rel, ok = ok,
      message = if (ok) "" else {
        m <- unname(msg_by_path[p]); if (is.na(m) || !nzchar(m)) "not reported by the batch script" else m
      },
      seconds = elapsed / length(items),
      det = pam_birdnet_normalise(if (is.null(d)) data.frame() else d))
  }
  attr(out, "api") <- "birdnet"
  attr(out, "dropped") <- character()
  out
}
