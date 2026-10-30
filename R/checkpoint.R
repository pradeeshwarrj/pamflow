#' Read the set of already-processed item IDs
#'
#' @param path Path to a plain-text checkpoint file (one ID per line).
#' @return Character vector of completed IDs (empty if the file doesn't exist).
#' @examples
#' ckpt <- tempfile(fileext = ".txt")
#' pam_checkpoint_read(ckpt)            # no file yet: nothing is done
#' pam_checkpoint_add(c("a.wav", "b.wav"), ckpt)
#' pam_checkpoint_read(ckpt)
#' unlink(ckpt)
#' @export
pam_checkpoint_read <- function(path) {
  if (!file.exists(path)) return(character())
  unique(readLines(path, warn = FALSE))
}

#' Record items as completed
#'
#' Call this *after* the corresponding batch output has been written to disk,
#' so an interruption never marks unwritten work as done.
#'
#' @param ids Character vector of IDs (e.g. file paths relative to the audio root).
#' @param path Checkpoint file path.
#' @return `ids`, invisibly.
#' @examples
#' ckpt <- tempfile(fileext = ".txt")
#' pam_checkpoint_add("a.wav", ckpt)
#' pam_checkpoint_add("b.wav", ckpt)
#' pam_checkpoint_read(ckpt)
#' unlink(ckpt)
#' @export
pam_checkpoint_add <- function(ids, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cat(paste0(ids, "\n"), file = path, append = TRUE, sep = "")
  invisible(ids)
}

#' Split pending work into batches, skipping completed items
#'
#' @param all_ids Character vector of every ID to process.
#' @param checkpoint_path Checkpoint file path.
#' @param batch_size Number of IDs per batch.
#' @return A list of character vectors (empty list if nothing is pending).
#' @examples
#' ckpt <- tempfile(fileext = ".txt")
#' ids <- c("a.wav", "b.wav", "c.wav")
#' pam_pending_batches(ids, ckpt, batch_size = 2)   # all three are pending
#' pam_checkpoint_add("a.wav", ckpt)
#' pam_pending_batches(ids, ckpt, batch_size = 2)   # only b and c are left
#' unlink(ckpt)
#' @export
pam_pending_batches <- function(all_ids, checkpoint_path, batch_size = 500L) {
  pending <- setdiff(all_ids, pam_checkpoint_read(checkpoint_path))
  if (!length(pending)) return(list())
  split(pending, ceiling(seq_along(pending) / batch_size))
}
