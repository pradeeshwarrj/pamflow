#' Audio I/O Utilities (WAV + FLAC)
#'
#' Centralized helpers for cross-format audio reading, metadata inspection, and
#' lossless clip extraction. All downstream pamflow stages route through this
#' module so WAV and FLAC are handled uniformly.
#'
#' @name utils_audio
NULL

#' Supported Audio File Extensions
#'
#' @return Character vector of supported audio extensions (lowercase).
#' @examples
#' pam_audio_exts()
#' @export
pam_audio_exts <- function() {
  c("wav", "flac")
}

#' Regex Pattern Matching Supported Audio Files
#'
#' @return Character scalar regex pattern (case-insensitive).
#' @examples
#' grepl(pam_audio_pattern(), c("a.wav", "b.FLAC", "c.mp3"))
#' @export
pam_audio_pattern <- function() {
  "\\.(wav|flac|WAV|FLAC)$"
}

#' Check if a File is a FLAC File
#'
#' @param path Character. File path or vector of paths.
#' @return Logical scalar or vector.
#' @examples
#' pam_is_flac(c("a.flac", "b.wav"))
#' @export
pam_is_flac <- function(path) {
  tolower(tools::file_ext(path)) == "flac"
}

#' Read Audio File Metadata (WAV or FLAC)
#'
#' Reads header information (sample rate, duration, channels, bit depth)
#' for one or more WAV/FLAC files without loading sample data into memory.
#' Returns a data.table with readable status; errors for individual unreadable
#' files are caught gracefully and flagged with \code{readable = FALSE}.
#'
#' @param paths Character vector of file paths.
#' @return A \code{data.table} with columns \code{file_path}, \code{file_size_b},
#'   \code{sample_rate}, \code{channels}, \code{bits}, \code{duration_s},
#'   \code{readable}.
#' @examples
#' ex <- pam_example_project()
#' pam_audio_info(ex$files)
#' @export
pam_audio_info <- function(paths) {
  if (length(paths) == 0) {
    return(data.table::data.table(
      file_path   = character(0),
      file_size_b = numeric(0),
      sample_rate = integer(0),
      channels    = integer(0),
      bits        = integer(0),
      duration_s  = numeric(0),
      readable    = logical(0)
    ))
  }

  n <- length(paths)
  out <- vector("list", n)

  for (i in seq_len(n)) {
    p <- paths[i]
    out[[i]] <- tryCatch({
      if (!file.exists(p)) {
        list(sample_rate = NA_integer_, channels = NA_integer_, bits = NA_integer_,
             duration_s = NA_real_, readable = FALSE)
      } else if (pam_is_flac(p)) {
        if (!requireNamespace("av", quietly = TRUE)) {
          stop("Package 'av' is required to read FLAC metadata. Run install.packages('av').")
        }
        info <- av::av_media_info(p)
        audio <- info$audio
        list(
          sample_rate = as.integer(audio$sample_rate[1]),
          channels    = as.integer(audio$channels[1]),
          bits        = NA_integer_,
          duration_s  = as.numeric(info$duration),
          readable    = TRUE
        )
      } else {
        hdr <- tuneR::readWave(p, header = TRUE)
        if (is.null(hdr) || is.null(hdr$samples) || is.na(hdr$samples) || is.null(hdr$sample.rate) || is.na(hdr$sample.rate)) {
          list(sample_rate = NA_integer_, channels = NA_integer_, bits = NA_integer_,
               duration_s = NA_real_, readable = FALSE)
        } else {
          list(
            sample_rate = as.integer(hdr$sample.rate),
            channels    = as.integer(hdr$channels),
            bits        = as.integer(hdr$bits),
            duration_s  = as.numeric(hdr$samples / hdr$sample.rate),
            readable    = TRUE
          )
        }
      }
    }, error = function(e) {
      list(sample_rate = NA_integer_, channels = NA_integer_, bits = NA_integer_,
           duration_s = NA_real_, readable = FALSE)
    })
  }

  info <- data.table::rbindlist(out)
  info[, file_path := paths]
  info[, file_size_b := suppressWarnings(as.numeric(file.size(paths)))]
  data.table::setcolorder(info, c("file_path", "file_size_b", "sample_rate", "channels", "bits", "duration_s", "readable"))
  info[]
}

#' Alias for pam_audio_info
#'
#' @rdname pam_audio_info
#' @export
pam_audio_info_dt <- pam_audio_info

#' Read Audio File as a tuneR Wave Object (WAV or FLAC)
#'
#' Decodes FLAC to a temporary WAV internally when needed. Returned object is
#' always a standard \code{tuneR::Wave} S4 object usable by \code{seewave} and
#' \code{soundecology}.
#'
#' @param path Character. Audio file path.
#' @param from Numeric. Optional start time in seconds.
#' @param to Numeric. Optional end time in seconds.
#' @return A \code{tuneR::Wave} S4 object.
#' @examples
#' ex <- pam_example_project()
#' w <- pam_read_audio(ex$files[1], from = 0.5, to = 1.5)
#' length(w@left) / w@samp.rate   # seconds read
#' @export
pam_read_audio <- function(path, from = NULL, to = NULL) {
  if (!file.exists(path)) stop(glue::glue("Audio file not found: {path}"))

  read_path <- path
  temp_wav <- NULL
  if (pam_is_flac(path)) {
    if (!requireNamespace("av", quietly = TRUE)) {
      stop("Package 'av' is required to decode FLAC files. Run install.packages('av').")
    }
    temp_wav <- tempfile(fileext = ".wav")
    on.exit(unlink(temp_wav), add = TRUE)
    suppressMessages(av::av_audio_convert(path, temp_wav, verbose = FALSE))
    read_path <- temp_wav
  }

  if (!is.null(from) && !is.null(to)) {
    return(tuneR::readWave(read_path, from = from, to = to, units = "seconds"))
  }
  tuneR::readWave(read_path)
}

#' Cut Audio Clip Preserving Source Format
#'
#' Extracts a sub-section of an audio file and writes it to disk, preserving
#' the source file extension when possible.
#'
#' @param in_path Character. Source audio file path.
#' @param out_path Character. Output file path.
#' @param from Numeric. Start time in seconds.
#' @param to Numeric. End time in seconds.
#' @return Invisibly returns \code{out_path}.
#' @examples
#' ex <- pam_example_project()
#' out <- tempfile(fileext = ".wav")
#' pam_cut_audio(ex$files[1], out, from = 0.5, to = 1.5)
#' pam_audio_info(out)$duration_s
#' unlink(out)
#' @export
pam_cut_audio <- function(in_path, out_path, from, to) {
  if (!file.exists(in_path)) stop(glue::glue("Source audio file not found: {in_path}"))

  wave <- pam_read_audio(in_path, from = from, to = to)
  out_ext <- tolower(tools::file_ext(out_path))

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

  if (out_ext == "flac") {
    if (!requireNamespace("av", quietly = TRUE)) {
      stop("Package 'av' is required to write FLAC files. Run install.packages('av').")
    }
    tmp_wav <- tempfile(fileext = ".wav")
    on.exit(unlink(tmp_wav), add = TRUE)
    tuneR::writeWave(wave, tmp_wav)
    suppressMessages(av::av_audio_convert(tmp_wav, out_path, format = "flac", verbose = FALSE))
  } else {
    tuneR::writeWave(wave, out_path)
  }

  invisible(out_path)
}

#' List Audio Files in a Directory (WAV + FLAC)
#'
#' @param dir Character. Directory to scan.
#' @param recursive Logical. Recurse into subdirectories.
#' @return Character vector of file paths.
#' @examples
#' ex <- pam_example_project()
#' basename(pam_list_audio(ex$audio_dir))
#' @export
pam_list_audio <- function(dir, recursive = TRUE) {
  list.files(dir, pattern = pam_audio_pattern(), full.names = TRUE, recursive = recursive)
}
