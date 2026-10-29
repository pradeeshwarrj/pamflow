# Train a custom BirdNET classifier from R

Runs BirdNET-Analyzer's own `birdnet-train` command inside pamflow's
training environment, so the trained model is the same kind of file the
Analyzer GUI produces. The training runs in a separate process: an error
or crash cannot take down your R session.

## Usage

``` r
pam_birdnet_train(
  data_dir,
  output,
  params = list(),
  test_data = NULL,
  load_params = NULL,
  cache_mode = NULL,
  cache_file = NULL,
  envdir = pam_birdnet_env_dir("training"),
  live = FALSE,
  overwrite = FALSE,
  log_dir = NULL
)
```

## Arguments

- data_dir:

  Training folder with one sub-folder per class. Use
  [`pam_birdnet_train_prepare()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_prepare.md)
  first.

- output:

  Output path prefix, e.g. `"E:/models/MyModel"`. The Analyzer writes
  `<output>.tflite`, `<output>_Labels.txt`, `<output>_Params.csv` and
  `<output>_sample_counts.csv`. pamflow adds `<output>_run.yml` (what
  was run) and `<output>_train.log` (everything the trainer printed) and
  uses `<output>_cache.npz` only if you set `cache_mode`.

- params:

  Named list of training parameters. Names: epochs, val_split,
  learning_rate, batch_size, threads, crop_mode, overlap, fmin, fmax,
  audio_speed, hidden_units, dropout, focal_loss, focal_loss_gamma,
  focal_loss_alpha, label_smoothing, mixup, upsampling_ratio,
  upsampling_mode, model_save_mode, model_format ("tflite", "raven" or
  "both"), autotune, autotune_trials, autotune_executions_per_trial.
  Yes/no options are on/off switches: `TRUE` turns them on, `FALSE`
  leaves them off. Anything you do not set is left to the installed
  Analyzer, so a plain run uses the same defaults as that version's own
  command line. The values it actually used are written to
  `<output>_Params.csv`.

- test_data:

  Optional separate test folder; if NULL the Analyzer holds out
  `val_split` of the training data.

- load_params:

  Optional path to an earlier run's parameters file, passed as
  `--load_params`. Only Analyzer versions that provide that option
  accept it; otherwise pamflow stops with a clear message.

- cache_mode:

  NULL (default), "save" or "load": passed as `--cache_mode`. Left off
  by default so a plain run behaves exactly like the Analyzer. With
  "load" the features are read from `cache_file` instead of the audio
  (the training folder may then be NULL).

- cache_file:

  Cache file for `cache_mode`; defaults to `<output>_cache.npz`. A
  relative path is taken relative to the folder of `output`, not the
  working directory.

- envdir:

  Training environment folder (from `pam_birdnet_setup("training")`).

- live:

  If TRUE, also show the trainer's output on the console while it runs.
  The log file is written either way.

- overwrite:

  If FALSE (default), refuse to overwrite an existing model.

- log_dir:

  Optional folder for a log file (`birdnet_train.log`).

## Value

Invisibly, a list: `status` ("ok" or "failed"), `output`, `files` (named
logical: which expected files exist), `elapsed` (difftime), `log`,
`run_record`, `args`, and `metrics` (from
[`pam_birdnet_train_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_metrics.md),
NULL if the log could not be read) and `evaluation` (with a separate
`test_data` folder: a list with `overall`, `classes` and `path` read
from `<output>_evaluation.csv`, one row per class with precision,
recall, F1, AUPRC and AUROC; otherwise NULL) and, when a cache was used,
`cache` (what the trainer reported: see `pam_train_cache_notes()`).

## Details

This is a standalone tool: it is not a stage of the workflow and no
workflow function calls it. Use the trained model by pointing the
`birdnet:` section of the config at it.

This is a standalone tool, not a pipeline stage: it needs no config file
and nothing in the workflow calls it. Assumptions: BirdNET-Analyzer is
installed in the training environment and provides the `birdnet-train`
command. Hyperparameter autotuning needs the Analyzer's `train` extra
(`pam_birdnet_setup("training", packages = "birdnet-analyzer[train]", recreate = TRUE)`).
Before running, pamflow checks that every option it passes appears in
the installed `birdnet-train --help` and stops with a clear message if
one does not.

## Examples

``` r
if (FALSE) { # \dontrun{
prep <- pam_birdnet_train_prepare("E:/training_clips")
res <- pam_birdnet_train("E:/training_clips", "E:/models/MyModel",
                         params = list(epochs = 100, hidden_units = 512))
# reproduce an earlier run from its parameters file
pam_birdnet_train("E:/training_clips", "E:/models/Rerun",
                  load_params = "E:/models/BirdNet_v2_custom_Params.csv")
} # }
```
