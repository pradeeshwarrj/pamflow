# Open the validation app

Shows the exported spectrogram and audio of each sampled event in random
order and records "correct", "incorrect" (plus the true species) or
"unsure". Every save is written immediately to `validation_results.csv`,
so you can stop at any time and continue later.

## Usage

``` r
pam_validate(
  cfg,
  run_id = cfg$birdnet$run_id,
  reviewer = pam_or(cfg$validation$reviewer, ""),
  show_confidence = isTRUE(cfg$validation$show_confidence),
  lang = NULL
)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run.

- reviewer:

  Name pre-filled in the app.

- show_confidence:

  Show the model's confidence while reviewing. Hidden by default
  (`validation$show_confidence`) to avoid biasing the reviewer.

- lang:

  Interface language code (for example `"en"`); `NULL` chooses it as
  [`pam_train_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_train_app.md)
  does. Translations live in `inst/i18n/<code>.yml`.

## Value

Nothing; runs until the app is closed.

## Examples

``` r
if (interactive() && nzchar(Sys.which("ffmpeg"))) {
  ex <- pam_example_project()
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 5))
  out <- suppressMessages(pam_validation_export(ex$cfg))   # clips and spectrograms to review
  pam_validate(ex$cfg)
}
```
