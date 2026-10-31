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

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
w <- pam_read_audio(ex$files[1], from = 0.5, to = 1.5)
#> Error in pam_read_audio(ex$files[1], from = 0.5, to = 1.5): could not find function "pam_read_audio"
length(w@left) / w@samp.rate   # seconds read
#> Error: object 'w' not found
```
