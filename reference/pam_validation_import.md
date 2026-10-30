# Join the reviewed verdicts to the sample table

Join the reviewed verdicts to the sample table

## Usage

``` r
pam_validation_import(cfg, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run.

## Value

A data.table: one row per reviewed sample, with `verdict` ("correct",
"incorrect", "unsure"), `true_species`, `note`, `reviewer`,
`reviewed_at` added to the sample columns.

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 8))
val_dir <- file.path(ex$cfg$paths$detections, "run01", "validation")
# normally the review app writes this file; here the verdicts are made up
results <- data.frame(sample_id = new$sample_id,
                      verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
                      true_species = NA_character_, note = "", reviewer = "example",
                      reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)
val <- pam_validation_import(ex$cfg)
as.data.frame(val)[, c("sample_id", "species", "confidence", "verdict")]
#>   sample_id                                    species confidence   verdict
#> 1         1 Psittacula longicauda_Long-tailed Parakeet       0.81   correct
#> 2         2 Psittacula longicauda_Long-tailed Parakeet       0.66   correct
#> 3         3 Psittacula longicauda_Long-tailed Parakeet       0.58 incorrect
#> 4         4         Gracula religiosa_Common Hill Myna       0.95   correct
#> 5         5  Ducula nicobarica_Nicobar Imperial-Pigeon       0.71   correct
#> 6         6 Psittacula longicauda_Long-tailed Parakeet       0.45 incorrect
#> 7         7 Psittacula longicauda_Long-tailed Parakeet       0.74   correct
#> 8         8         Gracula religiosa_Common Hill Myna       0.31   correct
```
