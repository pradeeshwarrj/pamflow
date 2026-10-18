# Split pending work into batches, skipping completed items

Split pending work into batches, skipping completed items

## Usage

``` r
pam_pending_batches(all_ids, checkpoint_path, batch_size = 500L)
```

## Arguments

- all_ids:

  Character vector of every ID to process.

- checkpoint_path:

  Checkpoint file path.

- batch_size:

  Number of IDs per batch.

## Value

A list of character vectors (empty list if nothing is pending).
