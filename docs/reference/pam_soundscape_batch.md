# Batch Process Audio Files for Soundscape Indices

Processes a list of audio files in batches of 50, appending results to
`soundscape_raw.csv` and writing checkpoints to `done.txt`.

## Usage

``` r
pam_soundscape_batch(file_list, cfg, test_n = NULL)
```

## Arguments

- file_list:

  Character vector. File paths to audio files.

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- test_n:

  Integer. Optional. Process only this many files (for tests).

## Value

A `data.table` containing raw soundscape index values.
