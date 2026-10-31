# Precision by species and confidence band, and by confidence threshold

Precision by species and confidence band, and by confidence threshold

## Usage

``` r
pam_validation_metrics(val, pool, bands)
```

## Arguments

- val:

  Reviewed samples from
  [`pam_validation_import()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_import.md).

- pool:

  Pool of all events from
  [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md);
  its cell sizes weight the threshold estimates, because sampling is
  stratified.

- bands:

  Confidence band edges used when sampling.

## Value

A list:

- `cells`: per species x band: `n_pool`, `n_reviewed`, `n_correct`,
  `n_incorrect`, `n_unsure`, `n_judged`, `precision` and its 95% Wilson
  interval (unsure verdicts are excluded from precision).

- `thresholds`: for each species (and "ALL") and each band edge, the
  estimated precision of all events at or above that confidence,
  weighted by band size, plus `coverage` (share of those events that sit
  in bands with at least one judged sample).

- `confusion`: counts of predicted species vs the true species entered
  for incorrect verdicts.

## Details

Recall, false negatives and F1 cannot be estimated from reviewing
detections alone: they need a set of recordings in which every call has
been annotated independently of the detector.

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
pool <- suppressMessages(pam_validation_pool(ex$cfg))
#> Error: object 'ex' not found
metrics <- pam_validation_metrics(val, pool, bands = unlist(ex$cfg$validation$bands))
#> Error: object 'val' not found
as.data.frame(metrics$cells)[, c("scientific_name", "band", "n_pool", "n_reviewed", "precision")]
#> Error: object 'metrics' not found
```
