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
#> Error in pam_example_project(): could not find function "pam_example_project"
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
new <- suppressMessages(pam_validation_draw(ex$cfg, strategy = "random", n = 8))
#> Error: object 'ex' not found
val_dir <- file.path(ex$cfg$paths$detections, "run01", "validation")
#> Error: object 'ex' not found
# normally the review app writes this file; here the verdicts are made up
results <- data.frame(sample_id = new$sample_id,
                      verdict = rep_len(c("correct", "correct", "incorrect"), nrow(new)),
                      true_species = NA_character_, note = "", reviewer = "example",
                      reviewed_at = format(Sys.time()), stringsAsFactors = FALSE)
#> Error in new$sample_id: object of type 'closure' is not subsettable
utils::write.csv(results, file.path(val_dir, "validation_results.csv"), row.names = FALSE)
#> Error in eval(expr, p): object 'results' not found
val <- pam_validation_import(ex$cfg)
#> Error: object 'ex' not found
as.data.frame(val)[, c("sample_id", "species", "confidence", "verdict")]
#> Error: object 'val' not found
```
