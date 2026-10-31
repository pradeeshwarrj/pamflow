# Inspect Raw Audio Directory

Recursively scans a raw data directory, classifies files (audio, short
clips/memos, non-audio, corrupt), extracts audio properties, and parses
recording datetimes.

## Usage

``` r
pam_inspect_raw(
  raw_dir,
  recursive = TRUE,
  min_duration_s = 60,
  timezone = "Asia/Kolkata",
  pattern = NULL
)
```

## Arguments

- raw_dir:

  Path to raw data folder.

- recursive:

  Logical, scan subfolders recursively?

- min_duration_s:

  Minimum duration in seconds for standard audio clips (default 60s).

- timezone:

  Timezone string for timestamp parsing.

- pattern:

  Optional filename regex pattern.

## Value

data.table containing detailed file metadata and triage categorization.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
# the example audio stands in for a raw dump; recordings under 1 s would count as memos
insp <- suppressMessages(pam_inspect_raw(ex$audio_dir, min_duration_s = 1))
#> Error in pam_inspect_raw(ex$audio_dir, min_duration_s = 1): could not find function "pam_inspect_raw"
as.data.frame(insp)[, c("filename", "duration_s", "grid", "category")]
#> Error: object 'insp' not found
```
