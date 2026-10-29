#' Normalise a BirdNET prediction table to a fixed schema
#'
#' Accepts the layout written by the Python batch runner (`start_time`/`end_time`/
#' `species_name` as "Scientific name_Common name") and the older layout
#' (`start`/`end`/`scientific_name`/`common_name`).
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
