# Segment-level recall, precision and F1 against ground truth

The unit is a segment x species: a species is "detected" in a segment if
the detector has an event of that species overlapping the segment at or
above the threshold, and "present" if the annotator marked it.
Possibly-present pairs are left out of the counts.

## Usage

``` r
pam_recall_metrics(
  truth,
  segments,
  events,
  classes = NULL,
  thresholds = c(0.3, 0.4, 0.5, 0.7)
)
```

## Arguments

- truth:

  Annotation table (`segment_id`, `present`, `possible`).

- segments:

  Segment table (`segment_id`, `rel`, `seg_start`, `seg_end`).

- events:

  Detector events from
  [`pam_validation_pool()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_pool.md)
  (`rel`, `start_time`, `end_time`, `scientific_name`, `confidence`).

- classes:

  Scientific names of the classifier's classes.

- thresholds:

  Confidence thresholds to evaluate.

## Value

A data.table with one row per species (and "ALL", summed over species)
and threshold: `tp`, `fn`, `fp`, `tn`, `n_present`, `recall`,
`recall_low`, `recall_high`, `precision`, `precision_low`,
`precision_high`, `f1`.

## Details

With simple random sampling of segments the estimates apply to the
sampled recordings and hours. A species that is rarely present in random
segments has few `n_present` and an uncertain recall.
