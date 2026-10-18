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
