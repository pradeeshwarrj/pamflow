# Parse Datetime from Audio Filename or Metadata

Automatically detects and extracts recording timestamp from filename
(ISO formats, 14-digit, 12-digit) or falls back to file modification
time. Timestamps are returned as local time strings.

## Usage

``` r
pam_parse_datetime(filename, file_path = NULL, timezone = "Asia/Kolkata")
```

## Arguments

- filename:

  Character, filename or base name.

- file_path:

  Optional character path to file for metadata fallback.

- timezone:

  Character string timezone (e.g. "Asia/Kolkata").

## Value

Character string timestamp in "YYYYMMDD_HHMMSS" format.

## Examples

``` r
pam_parse_datetime("G0059_20260405_183000.wav")
#> [1] "20260405_183000"
pam_parse_datetime("SM4_260405183000.wav")   # 12-digit stamp: yymmddhhmmss
#> [1] "20260405_183000"
```
