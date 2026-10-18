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
  show_confidence = isTRUE(cfg$validation$show_confidence)
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

## Value

Nothing; runs until the app is closed.
