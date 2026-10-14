#' Read and validate a pamflow configuration file
#'
#' @param path Path to a YAML config file.
#' @return A named list of class `pam_config`, with all paths resolved
#'   against `paths$project_root`.
#' @details Missing keys fall back to the template defaults.
#' @export
#' @examples
#' \dontrun{
#' cfg <- pam_config_read("config/config.yml")
#' }
pam_config_read <- function(path) {
  if (!file.exists(path)) {
    rlang::abort(sprintf("Config file not found: %s", path))
  }
  defaults <- yaml::read_yaml(
    system.file("extdata", "config_template.yml", package = "pamflow", mustWork = TRUE)
  )
  user <- yaml::read_yaml(path)
  cfg <- utils::modifyList(defaults, user)

  root <- normalizePath(cfg$paths$project_root, winslash = "/", mustWork = FALSE)
  cfg$paths <- lapply(cfg$paths, function(p) {
    if (fs::is_absolute_path(p)) p else as.character(fs::path(root, p))
  })
  cfg$paths$project_root <- root

  pam_config_validate(cfg)
  structure(cfg, class = c("pam_config", "list"))
}

#' Validate a pamflow configuration
#'
#' @param cfg A config list.
#' @return `cfg`, invisibly. Aborts with a clear message on invalid values.
#' @export
pam_config_validate <- function(cfg) {
  problems <- character()
  chk <- function(ok, msg) if (!isTRUE(ok)) problems <<- c(problems, msg)

  chk(cfg$birdnet$min_confidence >= 0 && cfg$birdnet$min_confidence <= 1,
      "birdnet$min_confidence must be in [0, 1]")
  chk(cfg$birdnet$workers >= 1, "birdnet$workers must be >= 1")
  chk(cfg$birdnet$overlap_s >= 0, "birdnet$overlap_s must be >= 0")
  chk(cfg$occupancy$occasion_length_days >= 1,
      "occupancy$occasion_length_days must be >= 1")
  chk(!is.na(tryCatch(regexpr(cfg$filenames$pattern, "x", perl = TRUE),
                      error = function(e) NA)),
      "filenames$pattern is not a valid PCRE regex")
  chk(cfg$filenames$timezone %in% OlsonNames(),
      "filenames$timezone is not a valid Olson timezone")

  if (length(problems)) {
    rlang::abort(c("Invalid pamflow configuration:",
                   stats::setNames(problems, rep("x", length(problems)))))
  }
  invisible(cfg)
}
