#' Read and validate a pamflow configuration file
#'
#' @param path Path to a YAML config file (required). There is no default:
#'   pamflow never looks for a configuration in the working directory.
#' @return A named list of class `pam_config`, with all paths resolved
#'   against `paths$project_root`.
#' @details Missing keys fall back to the template defaults
#'   (`system.file("extdata", "config_template.yml", package = "pamflow")`).
#'   A relative `paths$project_root` is resolved against the folder that holds
#'   the config file, not the working directory. The template uses `".."`, so a
#'   config saved as `<project>/config/config.yml` points at `<project>`.
#' @export
#' @examples
#' ex <- pam_example_project()
#' cfg <- pam_config_read(ex$config)
#' cfg$birdnet$run_id
#' cfg$paths$audio_standardized
pam_config_read <- function(path) {
  if (missing(path) || is.null(path) || !is.character(path) || length(path) != 1L ||
      is.na(path) || !nzchar(path)) {
    rlang::abort(c("`path` must be the path to your config file.",
                   i = "For example: pam_config_read(\"E:/MyProject/config/config.yml\")."))
  }
  if (!file.exists(path)) {
    rlang::abort(sprintf("Config file not found: %s", path))
  }

  default_template <- system.file("extdata", "config_template.yml", package = "pamflow", mustWork = FALSE)
  defaults <- if (nzchar(default_template) && file.exists(default_template)) {
    yaml::read_yaml(default_template)
  } else {
    list()
  }

  user <- yaml::read_yaml(path)
  if (!is.list(user)) user <- list()
  cfg <- utils::modifyList(defaults, user)

  config_dir <- dirname(normalizePath(path, winslash = "/", mustWork = TRUE))
  root_dir <- pam_or(cfg$paths$project_root, ".")
  if (!fs::is_absolute_path(root_dir)) root_dir <- file.path(config_dir, root_dir)
  root <- normalizePath(root_dir, winslash = "/", mustWork = FALSE)

  if (!is.null(cfg$paths)) {
    cfg$paths <- lapply(cfg$paths, function(p) {
      if (fs::is_absolute_path(p)) p else as.character(fs::path(root, p))
    })
  }
  cfg$paths$project_root <- root

  pam_config_validate(cfg)
  structure(cfg, class = c("pam_config", "list"))
}

#' Project folder of a configuration
#'
#' @param cfg A config list.
#' @return `cfg$paths$project_root`. Aborts when it is missing, so no output
#'   is ever written relative to the working directory by default.
#' @keywords internal
#' @noRd
pam_project_root <- function(cfg) {
  root <- cfg$paths$project_root
  if (is.null(root) || length(root) != 1L || is.na(root) || !nzchar(root)) {
    rlang::abort(c("The configuration has no `paths$project_root`.",
                   i = "Read it with pam_config_read(\"<path to config.yml>\")."))
  }
  root
}

#' Alias for pam_config_read
#'
#' @param path Path to config file (required).
#' @return pam_config object.
#' @examples
#' ex <- pam_example_project()
#' cfg <- pam_load_config(ex$config)
#' cfg$filenames$timezone
#' @export
pam_load_config <- function(path) {
  pam_config_read(path = path)
}

#' Validate a pamflow configuration
#'
#' @param cfg A config list.
#' @return `cfg`, invisibly. Aborts with a clear message on invalid values.
#' @examples
#' ex <- pam_example_project()
#' pam_config_validate(ex$cfg)          # fine: returns the config invisibly
#'
#' bad <- ex$cfg
#' bad$birdnet$min_confidence <- 2      # must be between 0 and 1
#' res <- try(pam_config_validate(bad), silent = TRUE)
#' inherits(res, "try-error")
#' @export
pam_config_validate <- function(cfg) {
  acc <- new.env(parent = emptyenv())   # local accumulator (no `<<-`)
  acc$problems <- character()
  chk <- function(ok, msg) if (!isTRUE(ok)) acc$problems <- c(acc$problems, msg)

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

  if (length(acc$problems)) {
    rlang::abort(c("Invalid pamflow configuration:", stats::setNames(acc$problems, rep("x", length(acc$problems)))))
  }
  invisible(cfg)
}

