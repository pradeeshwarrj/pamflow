# Shared fixtures for the training-app tests. testthat loads this file before the tests.

# Raw trainer output modelled on a real birdnet-train log
ansi <- function(code, x) paste0("\033[", code, "m", x, "\033[0m")

# raw trainer output: TensorFlow noise, ANSI colours, carriage-return progress bars
raw_log_fixture <- function(through = c("end", "download", "loading", "training")) {
  through <- match.arg(through)
  blocks <- list(
    download = paste0(
      "WARNING: All log messages before absl::InitializeLog() is called are written to STDERR\n",
      "I0000 00:00:1793256300.108937   17360 port.cc:153] oneDNN custom operations are on.\n",
      "Missing BirdNET_GLOBAL_6K_V2.4_Model/variables/variables.data-00000-of-00001\n",
      "Downloading model:   0%|          | 0.00/224M [00:00<?, ?B/s]\r",
      "Downloading model:  50%|\u2588\u2588\u2588\u2588\u2588     | 112M/224M [15:00<15:00, 120kiB/s]\n"),
    loading = paste0(
      "Downloading model: 100%|\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588| 224M/224M [30:58<00:00, 121kiB/s]\n",
      "Loading training data...\n",
      "\t...train data path: E:/clips\n",
      " - loading 'Aethopyga siparaja_Crimson Sunbird':   0%|          | 0/21 [00:00<?, ?f/s]\r",
      " - loading 'Aethopyga siparaja_Crimson Sunbird': 100%|\u2588\u2588\u2588\u2588| 21/21 [00:05<00:00,  3.55f/s]\r",
      " - loading 'Aethopyga siparaja_Crimson Sunbird': 100%|\u2588\u2588\u2588\u2588| 21/21 [00:05<00:00,  3.55f/s]\n",
      " - loading 'Catharus ustulatus_Swainson's Thrush':  50%|\u2588\u2588| 10/20 [00:03<00:03,  3.0f/s]\r"),
    training = paste0(
      " - loading 'Catharus ustulatus_Swainson's Thrush': 100%|\u2588\u2588\u2588\u2588| 20/20 [00:06<00:00,  3.3f/s]\n",
      "...Done. Loaded 41 training samples and 2 labels.\n",
      "Building model...\n", "...Done.\n", "Training model...\n",
      "Training on 33 samples, validating on 8 samples.\n",
      "Epoch 1/3\n",
      ansi("1", " 1/2"), " ", ansi("37", "\u2501\u2501\u2501"), " ", ansi("1", "7s"),
      " 387ms/step - AUPRC: 0.0412 - AUROC: 0.5056 - loss: 13.2691\n",
      ansi("1", "2/2"), " ", ansi("32", "\u2501\u2501\u2501"), " ", ansi("1", "1s"),
      " 9ms/step - AUPRC: 0.0572 - AUROC: 0.5293 - loss: 12.6670 - val_AUPRC: 0.0612 - val_AUROC: 0.5271 - val_loss: 12.1901 - learning_rate: 2.0000e-05\n",
      "Epoch 2/3\n"),
    end = paste0(
      ansi("1", "2/2"), " ", ansi("32", "\u2501\u2501\u2501"), " 0s 3ms/step - AUPRC: 0.0645 - AUROC: 0.5858 - loss: 5.3451 - val_AUPRC: 0.0611 - val_AUROC: 0.5939 - val_loss: 4.7322 - learning_rate: 9.7286e-05\n",
      "Epoch 3/3\n",
      ansi("1", "2/2"), " 0s 3ms/step - AUPRC: 0.0700 - AUROC: 0.6000 - loss: 5.0000 - val_AUPRC: 0.0700 - val_AUROC: 0.6100 - val_loss: 4.5000 - learning_rate: 5.0000e-05\n",
      "Restoring model weights from the end of the best epoch: 3.\n",
      "Saving model...\n",
      "Saved artifact at 'C:\\Users\\X\\Temp\\tmpabc'. The following endpoints are available:\n",
      "* Endpoint 'serve'\n",
      "WARNING:absl:Importing a function (__inference_embeddings_17928) with ops with unsaved custom gradients.\n",
      "  2236623533072: TensorSpec(shape=(), dtype=tf.resource, name=None)\n",
      "No separate test data provided for evaluation. Using validation metrics.\n",
      "...Done. Best AUPRC: 0.0700, Best AUROC: 0.6100, Best Loss: 4.5000 (epoch 3/3)\n"))
  idx <- switch(through, download = 1L, loading = 1:2, training = 1:3, end = 1:4)
  paste(unlist(blocks[c("download", "loading", "training", "end")][idx]), collapse = "")
}


# Form values as the app collects them (defaults plus overrides)
form_values <- function(train_dir = tempdir(), out_dir = tempdir(), ...) {
  d <- pam_train_defaults()
  base <- list(train_dir = train_dir, test_dir = "", out_dir = out_dir, clf_name = d$clf_name,
               out_format = d$out_format, cache_mode = "none", cache_file = "", fmin = d$fmin,
               fmax = d$fmax, audio_speed = d$audio_speed, crop_mode = d$crop_mode,
               crop_overlap = d$crop_overlap, autotune = FALSE, at_trials = d$at_trials,
               at_exec = d$at_exec, epochs = d$epochs, batch_size = d$batch_size,
               learning_rate = d$learning_rate, hidden_units = d$hidden_units,
               dropout = d$dropout, val_split = d$val_split, label_smoothing = FALSE,
               ups_mode = d$ups_mode, ups_ratio = d$ups_ratio, mixup = FALSE, focal = FALSE,
               f_gamma = d$focal_gamma, f_alpha = d$focal_alpha, save_mode = d$save_mode,
               threads = NA_real_, overwrite = FALSE, n_runs = 1)
  utils::modifyList(base, list(...), keep.null = TRUE)
}


# Write a run record like the ones pam_train_finish() produces
write_run <- function(dir, name, finished, exit_status = 0L, best = TRUE, hidden = 0L) {
  rec <- list(finished = finished, elapsed_min = 2.1, exit_status = exit_status,
              files_present = list(model = exit_status == 0L),
              params = list(hidden_units = hidden, epochs = 100L, learning_rate = 1e-4),
              effective = list(n_epochs = 100L, n_train = 658L, n_val = 171L))
  if (best) rec$best <- list(auprc = 0.9, auroc = 0.95, loss = 1.1)
  yaml::write_yaml(rec, file.path(dir, paste0(name, "_run.yml")))
}


# A training environment with a fake birdnet-train executable
fake_train_env <- function() {
  envdir <- withr::local_tempdir(.local_envir = parent.frame())
  bin <- pam_birdnet_train_bin(envdir)
  dir.create(dirname(bin), recursive = TRUE)
  file.create(bin)
  envdir
}

# A training folder with a few classes and files
make_class_dir <- function() {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  for (cl in c("species_a", "species_b", "noise")) {
    dir.create(file.path(root, cl))
    file.create(file.path(root, cl, paste0(cl, 1:3, ".wav")))
  }
  root
}

rscript_path <- function() {
  file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
}

wait_until <- function(cond, timeout = 20) {
  t0 <- Sys.time()
  while (!isTRUE(cond()) && as.numeric(Sys.time() - t0, units = "secs") < timeout) Sys.sleep(0.1)
  isTRUE(cond())
}

# Set every form input of the app in a testServer() session
set_form <- function(session, ...) {
  v <- utils::modifyList(form_values(train_dir = "", out_dir = ""), list(...), keep.null = TRUE)
  do.call(session$setInputs, v)
}

# Give child R processes their own temp folder, so a killed child cannot leave
# files (Rscript<hex>) in the check's temp directory
local_child_tmp <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(c(TMPDIR = dir, TMP = dir, TEMP = dir), .local_envir = env)
  invisible(dir)
}
