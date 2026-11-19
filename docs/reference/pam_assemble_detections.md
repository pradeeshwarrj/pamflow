# Assemble raw detection batches into one detections table

Reads all batch files of a run, removes duplicates (from interrupted
runs), joins recording metadata from the Stage 1 master table, and
writes `<detections>/<run_id>/detections.csv`.

## Usage

``` r
pam_assemble_detections(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Name of the detection run (a sub-folder of paths\$detections).
  Defaults to birdnet\$run_id.

## Value

A data.table with `filename`, `species`, `scientific_name`,
`common_name`, `confidence`, `start_time` and `end_time` (seconds into
the recording), `site` (= grid), `grid`, `recorder`, `deployment_id`,
`in_deployment`, `recording_date`, `recording_start` and
`detection_datetime` (local time), `rel`.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
det <- suppressMessages(pam_assemble_detections(ex$cfg))
nrow(det)   # the batch file had one duplicate row, which is dropped
#> [1] 19
as.data.frame(det)[, c("filename", "species", "confidence", "start_time", "end_time")]
#>                     filename                                    species
#> 1  G0059_20260405_183000.wav Psittacula longicauda_Long-tailed Parakeet
#> 2  G0059_20260405_183000.wav  Ducula nicobarica_Nicobar Imperial-Pigeon
#> 3  G0059_20260405_183000.wav Psittacula longicauda_Long-tailed Parakeet
#> 4  G0059_20260405_183002.wav Psittacula longicauda_Long-tailed Parakeet
#> 5  G0059_20260405_183002.wav  Ducula nicobarica_Nicobar Imperial-Pigeon
#> 6  G0059_20260405_183002.wav         Gracula religiosa_Common Hill Myna
#> 7  G0059_20260405_183002.wav Psittacula longicauda_Long-tailed Parakeet
#> 8  G0059_20260405_183004.wav Psittacula longicauda_Long-tailed Parakeet
#> 9  G0059_20260405_183004.wav Psittacula longicauda_Long-tailed Parakeet
#> 10 G0059_20260405_183004.wav Psittacula longicauda_Long-tailed Parakeet
#> 11 G0110_20260406_060000.wav Psittacula longicauda_Long-tailed Parakeet
#> 12 G0110_20260406_060000.wav  Ducula nicobarica_Nicobar Imperial-Pigeon
#> 13 G0110_20260406_060000.wav         Gracula religiosa_Common Hill Myna
#> 14 G0110_20260406_060000.wav Psittacula longicauda_Long-tailed Parakeet
#> 15 G0110_20260406_060002.wav Psittacula longicauda_Long-tailed Parakeet
#> 16 G0110_20260406_060002.wav  Ducula nicobarica_Nicobar Imperial-Pigeon
#> 17 G0110_20260406_060002.wav Psittacula longicauda_Long-tailed Parakeet
#> 18 G0110_20260406_060004.wav Psittacula longicauda_Long-tailed Parakeet
#> 19 G0110_20260406_060004.wav Psittacula longicauda_Long-tailed Parakeet
#>    confidence start_time end_time
#> 1        0.92        0.0      3.0
#> 2        0.71        0.0      3.0
#> 3        0.88        1.5      4.5
#> 4        0.81        0.0      3.0
#> 5        0.64        0.0      3.0
#> 6        0.31        0.0      3.0
#> 7        0.77        1.5      4.5
#> 8        0.66        0.0      3.0
#> 9        0.52        1.5      4.5
#> 10       0.60        4.0      7.0
#> 11       0.74        0.0      3.0
#> 12       0.83        0.0      3.0
#> 13       0.95        0.0      3.0
#> 14       0.69        1.5      4.5
#> 15       0.58        0.0      3.0
#> 16       0.58        0.0      3.0
#> 17       0.55        1.5      4.5
#> 18       0.45        0.0      3.0
#> 19       0.35        1.5      4.5
```
