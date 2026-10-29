# Read training metrics from a `birdnet-train` log

Extracts the per-epoch history and the final summary that the Analyzer
prints, so runs can be compared (for example with the Analyzer GUI)
without reading the log by hand.

## Usage

``` r
pam_birdnet_train_metrics(log_file)
```

## Arguments

- log_file:

  Path to a training log (`<output>_train.log`).

## Value

A list: `history` (data.frame with `epoch`, `auprc`, `auroc`, `loss`,
`val_auprc`, `val_auroc`, `val_loss`, `learning_rate`), `best` (list
with `auprc`, `auroc`, `loss`, `epoch`, `n_epochs`; NA when not
printed), `n_train`, `n_val`, `n_labels` (NA if not found) and
`evaluated_on` ("validation" or "test").

## Details

The log format is the one printed by BirdNET-Analyzer 2.4.0. If the
trainer prints something else, the fields come back empty or NA rather
than guessed. Terminal progress bars and TensorFlow messages in the log
are ignored.

## Examples

``` r
if (FALSE) { # \dontrun{
m <- pam_birdnet_train_metrics("E:/models/MyModel_train.log")
m$best$auprc
} # }
```
