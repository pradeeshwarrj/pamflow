#' Read and validate a pamflow configuration file
#'
#' @param path Path to a YAML config file. If missing, looks for "config/config.yml" or loads default template.
#' @return A named list of class `pam_config`, with all paths resolved
#'   against `paths$project_root`.
#' @details Missing keys fall back to the template defaults.
#' @export
#' @examples
#' \dontrun{
#' cfg <- pam_config_read("config/config.yml")
#' }
pam_config_read <- function(path = NULL) {
  default_template <- system.file("extdata", "config_template.yml", package = "pamflow", mustWork = FALSE)
  if (!nzchar(default_template)) {
    default_template <- system.file("config_default.yml", package = "pamflow", mustWork = FALSE)
  }

  if (is.null(path) || !file.exists(path)) {
    if (file.exists("config/config.yml")) {
      path <- "config/config.yml"
    } else if (nzchar(default_template) && file.exists(default_template)) {
      path <- default_template
    } else {
      return(structure(list(paths = list(audio_raw = "data/raw", audio_standardized = "data/standardized", audio_isolated = "data/isolated")), class = c("pam_config", "list")))
    }
  }

  defaults <- if (nzchar(default_template) && file.exists(default_template)) {
    yaml::read_yaml(default_template)
  } else {
    list()
  }

  user <- yaml::read_yaml(path)
  cfg <- utils::modifyList(defaults, user)

  root_dir <- if (!is.null(cfg$paths$project_root)) cfg$paths$project_root else getwd()
  root <- tryCatch(normalizePath(root_dir, winslash = "/", mustWork = FALSE), error = function(e) getwd())

  if (!is.null(cfg$paths)) {
    cfg$paths <- lapply(cfg$paths, function(p) {
      if (fs::is_absolute_path(p)) p else as.character(fs::path(root, p))
    })
    cfg$paths$project_root <- root
  }

  pam_config_validate(cfg)
  structure(cfg, class = c("pam_config", "list"))
}

#' Alias for pam_config_read
#'
#' @param path Path to config file.
#' @return pam_config object.
#' @export
pam_load_config <- function(path = NULL) {
  pam_config_read(path = path)
}

#' Validate a pamflow configuration
#'
#' @param cfg A config list.
#' @return `cfg`, invisibly. Aborts with a clear message on invalid values.
#' @export
pam_config_validate <- function(cfg) {
  problems <- character()
  chk <- function(ok, msg) if (!isTRUE(ok)) problems <<- c(problems, msg)

  if (!is.null(cfg$birdnet)) {
    if (!is.null(cfg$birdnet$min_confidence)) {
      chk(cfg$birdnet$min_confidence >= 0 && cfg$birdnet$min_confidence <= 1, "birdnet$min_confidence must be in [0, 1]")
    }
    if (!is.null(cfg$birdnet$workers)) {
      chk(cfg$birdnet$workers >= 1, "birdnet$workers must be >= 1")
    }
    if (!is.null(cfg$birdnet$overlap_s)) {
      chk(cfg$birdnet$overlap_s >= 0, "birdnet$overlap_s must be >= 0")
    }
    if (!is.null(cfg$birdnet$backend)) {
      chk(identical(cfg$birdnet$backend, "birdnet"),
          "birdnet$backend must be \"birdnet\" (the birdnetR engine was removed); delete the line to use the default")
    }
    if (!is.null(cfg$birdnet$top_k)) {
      chk(is.numeric(cfg$birdnet$top_k) && length(cfg$birdnet$top_k) == 1L &&
            cfg$birdnet$top_k >= 1 && cfg$birdnet$top_k == round(cfg$birdnet$top_k),
          "birdnet$top_k must be a whole number >= 1, or null for no limit")
    }
    for (key in c("py_batch_size", "n_producers")) {
      if (!is.null(cfg$birdnet[[key]])) {
        v <- cfg$birdnet[[key]]
        chk(is.numeric(v) && length(v) == 1L && v >= 1 && v == round(v),
            sprintf("birdnet$%s must be a whole number >= 1", key))
      }
    }
    if (!is.null(cfg$birdnet$sigmoid_sensitivity)) {
      chk(is.numeric(cfg$birdnet$sigmoid_sensitivity) && cfg$birdnet$sigmoid_sensitivity > 0,
          "birdnet$sigmoid_sensitivity must be > 0")
    }
  }

  if (!is.null(cfg$occupancy$occasion_length_days)) {
    chk(cfg$occupancy$occasion_length_days >= 1, "occupancy$occasion_length_days must be >= 1")
  }

  if (!is.null(cfg$filenames$pattern) && nzchar(cfg$filenames$pattern)) {
    chk(!is.na(tryCatch(regexpr(cfg$filenames$pattern, "x", perl = TRUE), error = function(e) NA)), "filenames$pattern is not a valid PCRE regex")
  }

  if (!is.null(cfg$filenames$timezone) && nzchar(cfg$filenames$timezone)) {
    chk(cfg$filenames$timezone %in% OlsonNames(), "filenames$timezone is not a valid Olson timezone")
  }

  if (length(problems)) {
    rlang::abort(c("Invalid pamflow configuration:", stats::setNames(problems, rep("x", length(problems)))))
  }
  invisible(cfg)
}

