# Extract Grid, Recorder, or Site Identifier from Filename

Helper function to parse site/grid/recorder identifier from filename
using pattern capture groups or leading token prior to first underscore.

## Usage

``` r
pam_extract_grid(filename, pattern = NULL)
```

## Arguments

- filename:

  Character, filename or base name.

- pattern:

  Optional regular expression pattern (e.g., cfg\$filenames\$pattern).

## Value

Character string identifier or "unassigned".

## Examples

``` r
pam_extract_grid("G0059_20260405_183000.wav")
#> Error in pam_extract_grid("G0059_20260405_183000.wav"): could not find function "pam_extract_grid"
pam_extract_grid("recording.wav")   # no recognisable identifier
#> Error in pam_extract_grid("recording.wav"): could not find function "pam_extract_grid"
```
