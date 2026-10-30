# All possible annotation segments of the recordings

Cuts every QC-passed, in-deployment recording into consecutive,
non-overlapping segments of `segment_s` seconds (a final piece shorter
than a segment is dropped).

## Usage

``` r
pam_recall_frame(master, segment_s = 60, hours = NULL)
```

## Arguments

- master:

  Table with `rel`, `grid`, `recording_start` (POSIXct, local),
  `duration_s`, `qc_pass`, `in_deployment`.

- segment_s:

  Segment length in seconds.

- hours:

  Optional c(from, to): keep only segments whose local start hour is \>=
  from and \< to (e.g. c(4, 18)).

## Value

A data.table with one row per segment: `rel`, `grid`, `recording_start`,
`seg_start`, `seg_end` (seconds into the file), `slot_time`, `hour`,
`seg_key`.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
master <- res$master
master$rel <- file.path(master$grid, master$file_name)   # path relative to the audio folder
master$recording_start <- master$start_time
# the example recordings are 2 s long, so use 1 s segments (the default is 60 s)
frame <- pam_recall_frame(master, segment_s = 1)
nrow(frame)
#> [1] 12
as.data.frame(frame)[1:3, c("rel", "seg_start", "seg_end")]
#>                               rel seg_start seg_end
#> 1 G0059/G0059_20260405_183000.wav         0       1
#> 2 G0059/G0059_20260405_183000.wav         1       2
#> 3 G0059/G0059_20260405_183002.wav         0       1
```
