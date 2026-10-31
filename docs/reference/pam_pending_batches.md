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

## Examples

``` r
ckpt <- tempfile(fileext = ".txt")
ids <- c("a.wav", "b.wav", "c.wav")
pam_pending_batches(ids, ckpt, batch_size = 2)   # all three are pending
#> $`1`
#> [1] "a.wav" "b.wav"
#> 
#> $`2`
#> [1] "c.wav"
#> 
pam_checkpoint_add("a.wav", ckpt)
pam_pending_batches(ids, ckpt, batch_size = 2)   # only b and c are left
#> $`1`
#> [1] "b.wav" "c.wav"
#> 
unlink(ckpt)
```
