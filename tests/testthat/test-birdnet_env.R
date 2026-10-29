test_that("probe output is parsed and log noise is ignored", {
  lines <- c("2026-10-29 tensorflow: some noisy log line",
             "PAMPROBE python=3.11.9",
             "PAMPROBE pkg_tensorflow=2.19.0",
             "PAMPROBE pkg_birdnet=missing",
             "W0000 another noisy line with = sign",
             "PAMPROBE tf_gpus=0")
  p <- pam_birdnet_parse_probe(lines)
  expect_equal(p$python, "3.11.9")
  expect_equal(p$pkg_tensorflow, "2.19.0")
  expect_equal(p$pkg_birdnet, "missing")
  expect_equal(p$tf_gpus, "0")
  expect_length(p, 4L)
})

test_that("probe parsing returns an empty list when there are no probe lines", {
  expect_equal(pam_birdnet_parse_probe(character()), list())
  expect_equal(pam_birdnet_parse_probe(c("hello", "world")), list())
})

test_that("probe of a missing python executable is empty, not an error", {
  expect_equal(pam_birdnet_probe(file.path(tempdir(), "no", "python")), list())
  expect_equal(pam_birdnet_probe(""), list())
})

test_that("python path follows the platform layout", {
  p <- pam_birdnet_python_path("envdir")
  if (.Platform$OS.type == "windows") {
    expect_match(p, "Scripts[/\\\\]python\\.exe$")
  } else {
    expect_match(p, "bin/python$")
  }
})

test_that("default requirements keep inference and training separate", {
  req <- pam_birdnet_default_requirements()
  expect_named(req, c("inference", "training"))
  expect_true(any(grepl("^birdnet>=", req$inference)))
  expect_true(any(grepl("birdnet-analyzer", req$training)))
})

test_that("doctor reports missing environments as failures without erroring", {
  envs <- list(inference = file.path(tempdir(), "no_inference_env"),
               training = file.path(tempdir(), "no_training_env"))
  res <- suppressMessages(pam_birdnet_doctor(envs = envs, quiet = TRUE))
  expect_s3_class(res, "pam_birdnet_doctor")
  expect_named(res, c("check", "status", "detail"))
  expect_true(all(res$status %in% c("ok", "warn", "fail", "info")))
  expect_equal(res$status[res$check == "env_inference"], "fail")
  expect_equal(res$status[res$check == "env_training"], "fail")
})

test_that("setup dry run returns the plan and creates nothing", {
  dir <- file.path(tempdir(), "dry_run_env")
  plan <- pam_birdnet_setup("training", python_version = "3.11", envdir = dir, dry_run = TRUE)
  expect_equal(plan$envdir, dir)
  expect_equal(plan$python_version, "3.11")
  expect_true("birdnet-analyzer" %in% plan$packages)
  expect_false(dir.exists(dir))
})

test_that("setup rejects an unknown component", {
  expect_error(pam_birdnet_setup("embedding", dry_run = TRUE))
})

test_that("uv lookup returns NA or an existing file", {
  uv <- pam_find_uv()
  expect_length(uv, 1L)
  expect_true(is.na(uv) || file.exists(uv))
})

test_that("default environment folders use forward slashes", {
  expect_false(grepl("\\\\", pam_birdnet_env_dir("inference")))
})
