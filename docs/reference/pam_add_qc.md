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
but do not fail QC. Truncation checks apply to PCM WAV files (where bit
depth is non-NA).

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
cfg <- ex$cfg
#> Error: object 'ex' not found
master <- pam_parse_filenames(ex$files, cfg$filenames$pattern, cfg$filenames$timezone)
#> Error: object 'ex' not found
master <- merge(master, pam_audio_info(ex$files), by = "file_path")
#> Error: object 'master' not found
master <- pam_add_qc(master, cfg)
#> Error: object 'cfg' not found
as.data.frame(master)[, c("file_name", "gap_s", "qc_pass")]
#> Error: object 'master' not found
```
