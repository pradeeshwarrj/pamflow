# Simple random sample of segments

Simple random sample of segments

## Usage

``` r
pam_recall_sample(frame, n, seed = 1L, exclude_keys = character())
```

## Arguments

- frame:

  Segments from
  [`pam_recall_frame()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_frame.md).

- n:

  Number of segments.

- seed:

  Random seed.

- exclude_keys:

  `seg_key`s already drawn; never drawn again.

## Value

A data.table of `min(n, available)` segments.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
master <- res$master
master$rel <- file.path(master$grid, master$file_name)   # path relative to the audio folder
master$recording_start <- master$start_time
frame <- pam_recall_frame(master, segment_s = 1)
pick <- pam_recall_sample(frame, n = 3, seed = 1)
as.data.frame(pick)[, c("rel", "seg_start", "seg_end")]
#>                               rel seg_start seg_end
#> 1 G0110/G0110_20260406_060002.wav         0       1
#> 2 G0059/G0059_20260405_183002.wav         1       2
#> 3 G0110/G0110_20260406_060000.wav         0       1
```
