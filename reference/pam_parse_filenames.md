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
# the second name does not match the pattern, so it is flagged, not dropped
pam_parse_filenames(c(ex$files[1], "not_a_recording.wav"),
                    pattern = ex$cfg$filenames$pattern,
                    timezone = "Asia/Kolkata")
#>                                                                                         file_path
#>                                                                                            <char>
#> 1: /tmp/RtmpcPP94A/pamflow_example_1c4d49945d55/data/standardized/G0059/G0059_20260405_183000.wav
#> 2:                                                                            not_a_recording.wav
#>                    file_name   grid          start_time valid_name
#>                       <char> <char>              <POSc>     <lgcl>
#> 1: G0059_20260405_183000.wav  G0059 2026-04-05 18:30:00       TRUE
#> 2:       not_a_recording.wav   <NA>                <NA>      FALSE
```
