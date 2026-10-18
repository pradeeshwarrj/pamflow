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
