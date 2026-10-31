# Read Audio File Metadata (WAV or FLAC)

Reads header information (sample rate, duration, channels, bit depth)
for one or more WAV/FLAC files without loading sample data into memory.
Returns a data.table with readable status; errors for individual
unreadable files are caught gracefully and flagged with
`readable = FALSE`.

## Usage

``` r
pam_audio_info(paths)

pam_audio_info_dt(paths)
```

## Arguments

- paths:

  Character vector of file paths.

## Value

A `data.table` with columns `file_path`, `file_size_b`, `sample_rate`,
`channels`, `bits`, `duration_s`, `readable`.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
pam_audio_info(ex$files)
#> Error: object 'ex' not found
```
