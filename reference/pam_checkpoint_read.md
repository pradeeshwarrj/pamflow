# Read the set of already-processed item IDs

Read the set of already-processed item IDs

## Usage

``` r
pam_checkpoint_read(path)
```

## Arguments

- path:

  Path to a plain-text checkpoint file (one ID per line).

## Value

Character vector of completed IDs (empty if the file doesn't exist).
