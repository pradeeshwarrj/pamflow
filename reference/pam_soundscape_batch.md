# Batch Process Audio Files for Soundscape Indices

Batch Process Audio Files for Soundscape Indices

## Usage

``` r
pam_soundscape_batch(file_list, cfg, test_n = NULL)
```

## Arguments

- file_list:

  Character vector. File paths to audio files.

- cfg:

  List. Parsed configuration structure.

- test_n:

  Integer. Optional. Process only this many files (for tests).

## Value

A `data.table` containing raw soundscape index values.
