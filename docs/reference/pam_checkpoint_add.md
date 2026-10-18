# Record items as completed

Call this *after* the corresponding batch output has been written to
disk, so an interruption never marks unwritten work as done.

## Usage

``` r
pam_checkpoint_add(ids, path)
```

## Arguments

- ids:

  Character vector of IDs (e.g. file paths relative to the audio root).

- path:

  Checkpoint file path.

## Value

`ids`, invisibly.
