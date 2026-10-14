test_that("pending batches skip completed ids", {
  ck <- tempfile()
  ids <- letters[1:9]
  pam_checkpoint_add(c("a", "b", "c"), ck)
  b <- pam_pending_batches(ids, ck, batch_size = 4)
  expect_equal(unlist(b, use.names = FALSE), letters[4:9])
  expect_length(b, 2)
})
