# Parse grid and start time from recording filenames

Parse grid and start time from recording filenames

## Usage

``` r
pam_parse_filenames(files, pattern, timezone)
```

## Arguments

- files:

  Character vector of file paths.

- pattern:

  PCRE regex with named groups `grid`, `date` (YYYYMMDD) and `time`
  (HHMMSS), applied to the file name only.

- timezone:

  Olson timezone of the filename timestamps (local time).

## Value

A data.table with `file_path`, `file_name`, `grid`, `start_time`
(POSIXct) and `valid_name`. Files that don't match get NA and
`valid_name = FALSE`; they are never dropped.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the second name does not match the pattern, so it is flagged, not dropped
pam_parse_filenames(c(ex$files[1], "not_a_recording.wav"),
                    pattern = ex$cfg$filenames$pattern,
                    timezone = "Asia/Kolkata")
#> Error: object 'ex' not found
```
