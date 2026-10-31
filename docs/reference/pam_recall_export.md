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

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("ffmpeg"))) {
  ex <- pam_example_project()
  # the later stages read the master table that the scan builds
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  new <- suppressMessages(pam_recall_draw(ex$cfg, n = 3, run_id = NULL))
  out <- suppressMessages(pam_recall_export(ex$cfg))
  out$n_ok
}
#> Error in pam_example_project(): could not find function "pam_example_project"
# }
```
