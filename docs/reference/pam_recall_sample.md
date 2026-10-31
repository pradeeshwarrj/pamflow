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
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
master <- res$master
#> Error: object 'res' not found
master$rel <- file.path(master$grid, master$file_name)   # path relative to the audio folder
#> Error: object 'master' not found
master$recording_start <- master$start_time
#> Error: object 'master' not found
frame <- pam_recall_frame(master, segment_s = 1)
#> Error: object 'master' not found
pick <- pam_recall_sample(frame, n = 3, seed = 1)
#> Error in pam_recall_sample(frame, n = 3, seed = 1): object 'seg_key' not found
as.data.frame(pick)[, c("rel", "seg_start", "seg_end")]
#> Error: object 'pick' not found
```
