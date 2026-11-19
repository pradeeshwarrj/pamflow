# Stage 4: clean the detections of a run

Assembles the run's detections, applies
[`pam_clean_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_clean_detections.md)
using the `processing` settings of the config, and writes the results to
`<detections>/<run_id>/processed/`.

## Usage

``` r
pam_process_detections(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections). Defaults to
  birdnet\$run_id.

## Value

A list: `clean`, `removed`, `steps` (see
[`pam_clean_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_clean_detections.md)).

## Details

Writes `detections_clean.csv`, `removed_detections.csv` (with the reason
for each removal) and `processing_steps.csv`. Times are written as
local-time text. Run with
`pam_run_stage("04_process", pam_process_detections, cfg, run_id = "...")`.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
out <- suppressMessages(pam_process_detections(ex$cfg))
out$steps
#>                                                    rule n_before n_removed
#>                                                  <char>    <int>     <int>
#> 1:                     invalid confidence or timestamps       19         0
#> 2:                             file not in master table       19         0
#> 3:                              beyond end of recording       19         1
#> 4:                            outside deployment window       18         0
#> 5:                           below confidence threshold       18         3
#> 6: merged overlapping windows into events (not removed)       15         5
# the results are also written to the run folder
list.files(file.path(ex$cfg$paths$detections, "run01", "processed"))
#> [1] "detections_clean.csv"   "processing_steps.csv"   "removed_detections.csv"
```
