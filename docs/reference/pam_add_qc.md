# Add QC flags to a master audio table

Add QC flags to a master audio table

## Usage

``` r
pam_add_qc(master, cfg)
```

## Arguments

- master:

  data.table from
  [`pam_parse_filenames()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_parse_filenames.md)
  joined with
  [`pam_audio_info()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_info.md).

- cfg:

  A `pam_config` object (uses `qc$gap_tolerance_s` and
  `audio$min_duration_s`).

## Value

`master` with `end_time`, `truncated`, `short`, `duplicate`, `gap_s`,
`gap_before`, `overlap_before` and `qc_pass`. Sorted by grid and start
time.

## Details

Gaps are measured between the end of one file and the start of the next
within a grid. `qc_pass` requires a valid name, a readable and
untruncated file, and no duplicate; `short` files and gaps are reported
but do not fail QC.
