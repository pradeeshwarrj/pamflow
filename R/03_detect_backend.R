#' Normalise a BirdNET prediction table to a fixed schema
#'
#' Accepts the column layouts of both `birdnetR` API generations (`start`/`end`/
#' `scientific_name`/`common_name`, or `start_time`/`end_time`/`species_name`
#' as "Scientific name_Common name").
#'
#' @param df A data frame of predictions (possibly zero rows).
#' @return A base data.frame with `start_s`, `end_s` (seconds into the
#'   recording), `scientific_name`, `common_name`, `confidence`.
#' @keywords internal
#' @noRd
pam_birdnet_normalise <- function(df) {
  df <- as.data.frame(df)
  empty <- data.frame(start_s = numeric(), end_s = numeric(),
                      scientific_name = character(), common_name = character(),
                      confidence = numeric(), stringsAsFactors = FALSE)
  if (nrow(df) == 0L) return(empty)
  pick <- function(...) {
    for (n in c(...)) if (n %in% names(df)) return(df[[n]])
    NULL
  }
  start <- pick("start_time", "start"); end <- pick("end_time", "end")
  conf <- pick("confidence"); sci <- pick("scientific_name"); com <- pick("common_name")
  if (is.null(sci)) {
    sp <- as.character(pick("species_name", "label"))
    sci <- sub("_.*$", "", sp)
    com <- ifelse(grepl("_", sp, fixed = TRUE), sub("^[^_]*_", "", sp), NA_character_)
  }
  if (is.null(start) || is.null(end) || is.null(conf) || is.null(sci) || is.null(com)) {
    stop("Unrecognised prediction columns: ", paste(names(df), collapse = ", "))
  }
  data.frame(start_s = as.numeric(start), end_s = as.numeric(end),
             scientific_name = as.character(sci), common_name = as.character(com),
             confidence = as.numeric(conf), stringsAsFactors = FALSE)
}

#' Make a function self-contained for parallel workers
#'
#' Workers do not have pamflow installed (it may only be loaded with
#' `devtools::load_all()`), so the worker function and its helpers are given a
#' global environment instead of the package namespace. Worker code must
#' therefore use only base R and `pkg::fun` calls.
#'
#' @param fn The worker function.
#' @param ... Named helper functions the worker calls.
#' @return `fn` with a portable environment.
#' @keywords internal
#' @noRd
pam_portable <- function(fn, ...) {
  helpers <- list(...)
  env <- new.env(parent = globalenv())
  for (nm in names(helpers)) {
    h <- helpers[[nm]]
    environment(h) <- globalenv()
    assign(nm, h, envir = env)
  }
  environment(fn) <- env
  fn
}

#' Run BirdNET on a batch of files (executed in each worker)
#'
#' Loads the custom model once per process (cached in the global environment),
#' then predicts file by file with per-file error isolation. Supports both
#' `birdnetR` API generations: `birdnet_model_custom()` +
#' `predict_species_from_audio_file()` (CRAN 0.3.x) and `load_custom()` +
#' `predict()` (newer). With the newer API, settings the installed version's
#' `predict` method does not accept (overlap, batch size, bandpass) are
#' dropped and reported in the `dropped` attribute.
#'
#' @param items List of `list(rel, path)` (relative id and full audio path).
#'   An empty list just loads the model (warm-up).
#' @param s Settings list from `pam_detect_settings()`.
#' @return A list with one element per file: `rel`, `ok`, `message`,
#'   `seconds`, `det` (normalised predictions). Attributes `api` and `dropped`.
#' @keywords internal
#' @noRd
pam_birdnet_run_batch <- function(items, s) {
  if (!requireNamespace("birdnetR", quietly = TRUE)) {
    stop("Package 'birdnetR' is not installed")
  }
  genv <- globalenv()
  if (!exists(".pam_birdnet_cache", envir = genv, inherits = FALSE)) {
    assign(".pam_birdnet_cache", new.env(), envir = genv)
  }
  cache <- get(".pam_birdnet_cache", envir = genv)
  ns <- asNamespace("birdnetR")
  api <- if (exists("load_custom", envir = ns, inherits = FALSE)) "new" else
    if (exists("birdnet_model_custom", envir = ns, inherits = FALSE)) "legacy" else
      stop("Unsupported birdnetR version: found neither load_custom() nor birdnet_model_custom()")

  key <- paste(api, s$model_dir, s$classifier_name, s$labels_file, s$tflite_threads, sep = "|")
  if (is.null(cache$model) || !identical(cache$key, key)) {
    cache$model <- if (api == "legacy") {
      getExportedValue("birdnetR", "birdnet_model_custom")(
        version = "v2.4", classifier_folder = s$model_dir,
        classifier_name = s$classifier_name,
        tflite_num_threads = as.integer(s$tflite_threads))
    } else {
      getExportedValue("birdnetR", "load_custom")(model = s$model_file,
                                                  species_list = s$labels_file)
    }
    cache$key <- key
  }
  model <- cache$model

  # newer API: pass only the optional arguments the predict method accepts
  optional <- list(chunk_overlap_s = s$overlap_s, batch_size = as.integer(s$batch_size),
                   use_bandpass = isTRUE(s$use_bandpass),
                   bandpass_fmin = as.integer(s$bandpass_fmin),
                   bandpass_fmax = as.integer(s$bandpass_fmax))
  dropped <- character()
  if (api == "new") {
    m <- NULL
    for (cl in class(model)) {
      m <- utils::getS3method("predict", cl, optional = TRUE)
      if (!is.null(m)) break
    }
    accepted <- if (is.null(m)) character() else names(formals(m))
    dropped <- setdiff(names(optional), accepted)
    optional <- optional[names(optional) %in% accepted]
  }

  predict_one <- function(path) {
    if (api == "legacy") {
      getExportedValue("birdnetR", "predict_species_from_audio_file")(
        model, path, min_confidence = s$min_confidence,
        batch_size = as.integer(s$batch_size), chunk_overlap_s = s$overlap_s,
        use_bandpass = isTRUE(s$use_bandpass),
        bandpass_fmin = as.integer(s$bandpass_fmin),
        bandpass_fmax = as.integer(s$bandpass_fmax), keep_empty = FALSE)
    } else {
      do.call(stats::predict, c(list(model, path, min_confidence = s$min_confidence), optional))
    }
  }

  out <- vector("list", length(items))
  for (i in seq_along(items)) {
    t0 <- proc.time()[["elapsed"]]
    res <- tryCatch(
      list(ok = TRUE, message = "",
           det = pam_birdnet_normalise(as.data.frame(predict_one(items[[i]]$path)))),
      error = function(e) list(ok = FALSE, message = conditionMessage(e),
                               det = pam_birdnet_normalise(data.frame())))
    out[[i]] <- list(rel = items[[i]]$rel, ok = res$ok, message = res$message,
                     seconds = proc.time()[["elapsed"]] - t0, det = res$det)
  }
  attr(out, "api") <- api
  attr(out, "dropped") <- dropped
  out
}
