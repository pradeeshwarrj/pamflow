# Simple random sample of segments

Simple random sample of segments

## Usage

``` r
pam_recall_sample(frame, n, seed = 1L, exclude_keys = character())
```

## Arguments

- frame:

  Segments from
  [`pam_recall_frame()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_recall_frame.md).

- n:

  Number of segments.

- seed:

  Random seed.

- exclude_keys:

  `seg_key`s already drawn; never drawn again.

## Value

A data.table of `min(n, available)` segments.
