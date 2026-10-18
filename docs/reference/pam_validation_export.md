# Export audio clips and spectrograms for the sampled events

For every row of `validation_samples.csv` whose files are missing, cuts
a clip (event plus `validation$clip_pad_s` seconds of context on each
side) from the audio the run read, and draws a spectrogram PNG with
FFmpeg. Existing files are kept, so it can be rerun after each new
round.

## Usage

``` r
pam_validation_export(cfg, run_id = cfg$birdnet$run_id, force = FALSE)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run.

- force:

  Recreate all files.

## Value

Invisibly, list(n_ok, n_failed, failed_ids).
