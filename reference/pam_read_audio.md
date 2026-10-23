# Read Audio File as a tuneR Wave Object (WAV or FLAC)

Decodes FLAC to a temporary WAV internally when needed. Returned object
is always a standard
[`tuneR::Wave`](https://rdrr.io/pkg/tuneR/man/Wave.html) S4 object
usable by `seewave` and `soundecology`.

## Usage

``` r
pam_read_audio(path, from = NULL, to = NULL)
```

## Arguments

- path:

  Character. Audio file path.

- from:

  Numeric. Optional start time in seconds.

- to:

  Numeric. Optional end time in seconds.

## Value

A [`tuneR::Wave`](https://rdrr.io/pkg/tuneR/man/Wave.html) S4 object.
