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
