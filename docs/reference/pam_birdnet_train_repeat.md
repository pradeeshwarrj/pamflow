# Train the same classifier several times and summarise the metrics

Each run uses a different random validation split and initialisation, so
a single score can be lucky or unlucky. Repeating the run shows how much
the metrics vary, which is the yardstick for comparing settings, or
pamflow against the Analyzer GUI, fairly.

## Usage

``` r
pam_birdnet_train_repeat(data_dir, output, n = 5L, params = list(), ...)
```

## Arguments

- data_dir:

  Training folder (see
  [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md)).

- output:

  Output path prefix; run `k` is written to `<output>_run<kk>` (two
  digits).

- n:

  Number of runs.

- params:

  Named list of training parameters (see
  [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md)).

- ...:

  Further arguments passed to
  [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md)
  (for example `test_data`, `envdir`, `live`, `overwrite`).

## Value

A list: `runs` (data.frame with `run`, `status`, `auprc`, `auroc`,
`loss`, `best_epoch`, `elapsed_min`, `output`) and `summary` (data.frame
with `metric`, `n`, `mean`, `sd`, `min`, `max` over the successful
runs).

## Details

This is a standalone tool: it is not a stage of the workflow and no
workflow function calls it. Use the trained model by pointing the
`birdnet:` section of the config at it.

A failed run is recorded and does not stop the others. With a fixed
`test_data` folder every run is scored on the same clips, so the spread
then reflects training randomness only.

## Examples

``` r
if (FALSE) { # \dontrun{
rep5 <- pam_birdnet_train_repeat("E:/clips", "E:/models/Check", n = 5)
rep5$summary
} # }
```
