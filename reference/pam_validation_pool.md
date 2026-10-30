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
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
pool <- suppressMessages(pam_validation_pool(ex$cfg))
as.data.frame(pool)[, c("species", "confidence", "n_windows", "start_time")]
#>                                       species confidence n_windows start_time
#> 1   Ducula nicobarica_Nicobar Imperial-Pigeon       0.71         1          0
#> 2  Psittacula longicauda_Long-tailed Parakeet       0.92         2          0
#> 3   Ducula nicobarica_Nicobar Imperial-Pigeon       0.64         1          0
#> 4          Gracula religiosa_Common Hill Myna       0.31         1          0
#> 5  Psittacula longicauda_Long-tailed Parakeet       0.81         2          0
#> 6  Psittacula longicauda_Long-tailed Parakeet       0.66         2          0
#> 7   Ducula nicobarica_Nicobar Imperial-Pigeon       0.83         1          0
#> 8          Gracula religiosa_Common Hill Myna       0.95         1          0
#> 9  Psittacula longicauda_Long-tailed Parakeet       0.74         2          0
#> 10  Ducula nicobarica_Nicobar Imperial-Pigeon       0.58         1          0
#> 11 Psittacula longicauda_Long-tailed Parakeet       0.58         2          0
#> 12 Psittacula longicauda_Long-tailed Parakeet       0.45         2          0
```
