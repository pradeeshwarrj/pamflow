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

## Examples

``` r
ex <- pam_example_project()
# the later stages read the master table that the scan builds
res <- suppressMessages(pam_scan_audio(ex$cfg))
# run_id = NULL: sample all recordings (a real run would restrict to the files it processed)
new <- suppressMessages(pam_recall_draw(ex$cfg, n = 4, run_id = NULL))
as.data.frame(new)[, c("segment_id", "rel", "seg_start", "seg_end")]
#>   segment_id                             rel seg_start seg_end
#> 1          1 G0059/G0059_20260405_183004.wav         0       1
#> 2          2 G0059/G0059_20260405_183004.wav         1       2
#> 3          3 G0110/G0110_20260406_060004.wav         0       1
#> 4          4 G0110/G0110_20260406_060000.wav         1       2
```
