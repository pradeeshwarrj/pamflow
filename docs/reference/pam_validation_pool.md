# Build the pool of candidate events for validation

Takes the run's assembled detections through the Stage 4 rules
(deployment window, species lists, merging of windows into events) but
with the confidence cutoff set to the lowest stored confidence and no
species thresholds or seasons, so that events below your intended cutoff
can also be reviewed.

## Usage

``` r
pam_validation_pool(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections).

## Value

A data.table of events with `event_id` (rel\|species\|start).

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
pool <- suppressMessages(pam_validation_pool(ex$cfg))
#> Error: object 'ex' not found
as.data.frame(pool)[, c("species", "confidence", "n_windows", "start_time")]
#> Error: object 'pool' not found
```
