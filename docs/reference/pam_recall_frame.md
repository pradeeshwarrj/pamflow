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
# the example recordings are 2 s long, so use 1 s segments (the default is 60 s)
frame <- pam_recall_frame(master, segment_s = 1)
#> Error: object 'master' not found
nrow(frame)
#> NULL
as.data.frame(frame)[1:3, c("rel", "seg_start", "seg_end")]
#> Error in as.data.frame.default(frame): cannot coerce class '"function"' to a data.frame
```
