# Stage 1: scan standardized audio and build the master metadata table

Lists WAV/FLAC files, parses filenames, reads headers (cached, so
re-runs only read new files and an interrupted run resumes), joins
deployments, adds QC flags, and writes the master table and summaries.

## Usage

``` r
pam_scan_audio(cfg, force = FALSE)
```

## Arguments

- cfg:

  A `pam_config` object.

- force:

  If TRUE, discard the header cache and re-read every file.

## Value

A list: `master`, `deployments`, `summary`.

## Details

Writes `metadata/audio_headers.csv` (cache),
`metadata/audio_master.csv`, `outputs/audio_summary_per_grid.csv` and
`outputs/deployment_issues.csv`. Times in CSV files are written as UTC
(ISO 8601) by
[`data.table::fwrite`](https://rdrr.io/pkg/data.table/man/fwrite.html).
Run with `pam_run_stage("01_scan", pam_scan_audio, cfg)` for logging.

Audio discovery uses
[`pam_list_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_list_audio.md)
(WAV + FLAC). Header reading uses
[`pam_audio_info()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_info.md).

## Examples

``` r
ex <- pam_example_project()
res <- suppressMessages(pam_scan_audio(ex$cfg))
res$summary$overall
#>    n_files n_grids total_hours n_invalid_name n_unreadable n_truncated n_short
#>      <int>   <int>       <num>          <int>        <int>       <int>   <int>
#> 1:       6       2 0.003333333              0            0           0       0
#>    n_duplicate n_gaps n_outside_deployment n_qc_pass
#>          <int>  <int>                <int>     <int>
#> 1:           0      0                    0         6
# the master table and summaries are also written to the project
list.files(ex$cfg$paths$metadata)
#> [1] "audio_headers.csv" "audio_master.csv"  "deployments.csv"  
```
