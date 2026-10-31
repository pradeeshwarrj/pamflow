# Launch the BirdNET classifier training app

A standalone tool, not a workflow stage: a point-and-click interface for
training a custom BirdNET classifier, laid out like the training tab of
the BirdNET-Analyzer GUI: training data, cache, frequency and speed,
cropping, autotune, training settings and the model save mode. It shows
the progress and the learning curves while training runs, can repeat a
training several times to show how much the scores vary, keeps a history
of earlier runs, and gives the `birdnet:` config lines that use the
trained model.

## Usage

``` r
pam_train_app(
  cfg = NULL,
  data_dir = NULL,
  output_dir = NULL,
  lang = NULL,
  envdir = pam_birdnet_env_dir("training")
)
```

## Arguments

- cfg:

  Optional configuration from
  [`pam_load_config()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_load_config.md);
  its `birdnet$model_dir` is used as the default output folder.

- data_dir:

  Optional training folder to start with (one sub-folder per class).

- output_dir:

  Optional output folder to start with.

- lang:

  Interface language code (for example `"en"`). `NULL` chooses from
  `options(pamflow.lang)`, the `PAMFLOW_LANG` variable or the system
  language, and falls back to English. Translations live in
  `inst/i18n/<code>.yml`; a translation only needs the texts it changes.

- envdir:

  Folder of the training Python environment (see
  `pam_birdnet_setup("training")`).

## Value

A Shiny app object. Printing it at the console starts it, or pass it to
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

## Details

This is a standalone tool: it is not a stage of the workflow and no
workflow function calls it. Use the trained model by pointing the
`birdnet:` section of the config at it.

Training runs in a separate process, so the app stays responsive and
Stop ends the training and everything it started. Closing the app also
stops a running training. The settings shown are the BirdNET-Analyzer
2.4.0 defaults; each value you see is the value used, and it is recorded
in the run's `_run.yml`. The first training downloads the base BirdNET
model (about 224 MB) once.

The scores shown come from clips held out of the training folder and are
therefore optimistic; give a separate test folder for a more honest
estimate.

## Examples

``` r
if (interactive()) {
  pam_train_app()
}
if (FALSE) { # \dontrun{
pam_train_app(data_dir = "E:/clips", output_dir = "E:/models", lang = "en")
} # }
```
