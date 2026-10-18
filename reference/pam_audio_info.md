# Read WAV header information without loading audio

Read WAV header information without loading audio

## Usage

``` r
pam_audio_info(paths)
```

## Arguments

- paths:

  Character vector of WAV paths.

## Value

A data.table with `file_path`, `file_size_b`, `sample_rate`, `channels`,
`bits`, `duration_s`, `readable`. Unreadable (corrupted) files get
`readable = FALSE` and NA fields; errors never propagate.
