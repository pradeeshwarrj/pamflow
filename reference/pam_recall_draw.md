# Draw a round of random segments for ground-truth annotation

Samples segments uniformly at random from the recordings, adds them to
`<paths$validation>/ground_truth/recall_segments.csv`, and never draws
the same segment twice. The ground truth belongs to the audio, not to a
detection run, so it can be reused to compare runs (for example filtered
against unfiltered audio).

## Usage

``` r
pam_recall_draw(cfg, n = cfg$recall$n_segments, run_id = cfg$birdnet$run_id)
```

## Arguments

- cfg:

  A `pam_config` object (uses the `recall` section).

- n:

  Segments to draw in this round.

- run_id:

  Detection run. Only recordings that run processed are sampled, because
  recall is measured against that run. NULL samples all recordings.

## Value

Invisibly, the newly added rows.
