# Export audio and spectrograms for the ground-truth segments

Cuts each segment from the audio chosen by `recall$audio`
("standardized" by default, so the truth does not depend on the
high-pass filter) and draws a wide spectrogram. Existing files are kept.

## Usage

``` r
pam_recall_export(cfg, force = FALSE)
```

## Arguments

- cfg:

  A `pam_config` object.

- force:

  Recreate all files.

## Value

Invisibly, list(n_ok, n_failed, failed_ids).
