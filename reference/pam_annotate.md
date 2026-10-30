# Open the ground-truth annotation app

Shows random recording segments, one at a time, in shuffled order, with
a spectrogram and audio. The model's detections are never shown, so the
annotation is independent of the detector. Record every species you
hear; mark doubtful ones as "possibly present". Each save is written
immediately to `recall_annotations.csv`, so you can stop and resume.

## Usage

``` r
pam_annotate(cfg, reviewer = pam_or(cfg$recall$reviewer, ""))
```

## Arguments

- cfg:

  A `pam_config` object.

- reviewer:

  Annotator name pre-filled in the app.

## Value

Nothing; runs until the app is closed.

## Examples

``` r
if (interactive() && nzchar(Sys.which("ffmpeg"))) {
  ex <- pam_example_project()
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  new <- suppressMessages(pam_recall_draw(ex$cfg, n = 5, run_id = NULL))
  out <- suppressMessages(pam_recall_export(ex$cfg))
  pam_annotate(ex$cfg)
}
```
