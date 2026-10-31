# Choose a confidence threshold for each species from the validation results

Species differ a lot in how reliable BirdNET is, so one confidence
cut-off for all species is rarely right. This function reads the
reviewed verdicts of Stage 5 and gives every species its own threshold,
without asking you for a precision target.

## Usage

``` r
pam_species_thresholds(
  cfg,
  run_id = cfg$birdnet$run_id,
  tolerance = 0.05,
  min_judged = 10,
  min_coverage = 0.5,
  manual = NULL,
  write = FALSE
)
```

## Arguments

- cfg:

  A `pam_config` object.

- run_id:

  Detection run (sub-folder of paths\$detections).

- tolerance:

  How far below its own best estimated precision a species may fall (a
  number between 0 and 1, default 0.05).

- min_judged:

  Minimum number of judged samples (correct or incorrect) a species
  needs; species with fewer get the default threshold.

- min_coverage:

  A confidence level only counts when at least this share of the
  species' events at or above it lies in bands that were reviewed
  (default 0.5).

- manual:

  Optional data frame, or path to a CSV file, with the columns
  `scientific_name` and `threshold`. These species use your value
  instead of the estimate.

- write:

  If `TRUE`, save the table as
  `<detections>/<run_id>/validation/species_thresholds.csv`. Nothing is
  written by default.

## Value

A data.table with one row per species: `scientific_name`, `threshold`,
`method`, `precision_est` (estimated precision of the events kept),
`coverage`, `n_judged`, `n_events_kept` and `reason`.

## Details

### Plateau rule

For each species, the estimated precision of all events at or above each
confidence band edge comes from
[`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md).
The species' best estimated precision is found, and the **lowest**
confidence whose precision is within `tolerance` of that best value is
chosen. Going higher than that would discard detections without making
them noticeably more reliable. A species with a flat precision curve
therefore keeps a low threshold, and one that needs a high threshold
gets one.

### Defaults

A species with too few judged samples, or no confidence level with
enough reviewed events, gets `processing$min_confidence` and
`method = "default"`; the `reason` column says why. Manual values always
win (`method = "manual"`).

### Using the result

Save it with `write = TRUE` and set `processing$species_thresholds_file`
in the config to that file. Stage 4 and Stage 6 read it; the columns
they do not need are ignored.

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
thr <- suppressMessages(pam_species_thresholds(ex$cfg, min_judged = 1))
#> Error in pam_species_thresholds(ex$cfg, min_judged = 1): could not find function "pam_species_thresholds"
as.data.frame(thr)[, c("scientific_name", "threshold", "method")]
#> Error: object 'thr' not found
```
