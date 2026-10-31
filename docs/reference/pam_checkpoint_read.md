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

## Examples

``` r
ckpt <- tempfile(fileext = ".txt")
pam_checkpoint_read(ckpt)            # no file yet: nothing is done
#> character(0)
pam_checkpoint_add(c("a.wav", "b.wav"), ckpt)
pam_checkpoint_read(ckpt)
#> [1] "a.wav" "b.wav"
unlink(ckpt)
```
