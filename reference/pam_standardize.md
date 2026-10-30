# Standardize Raw PAM Audio Files (Stage 00 Engine)

Standardizes raw audio datasets by organizing folders, parsing
timestamps, converting formats (WAV/FLAC), resampling, mixing channels
to mono, isolating non-audio/memos, and logging results.

## Usage

``` r
pam_standardize(
  cfg = NULL,
  raw_dir = NULL,
  standardized_dir = NULL,
  isolated_dir = NULL,
  dry_run = NULL,
  prefix = NULL,
  target_format = NULL,
  target_hz = NULL,
  channels = NULL,
  min_duration_s = NULL,
  organize_folders = NULL,
  rename_strategy = NULL,
  isolate_non_audio = NULL,
  isolate_short = NULL,
  timezone = NULL
)
```

## Arguments

- cfg:

  Optional configuration object from
  [`pam_load_config()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_load_config.md).

- raw_dir:

  Directory containing raw audio files.

- standardized_dir:

  Directory to save standardized audio.

- isolated_dir:

  Directory to save isolated non-audio and memo files.

- dry_run:

  Logical, if TRUE simulates actions without modifying disk.

- prefix:

  Prefix string prepended to standardized filenames.

- target_format:

  Output format: "flac" or "wav".

- target_hz:

  Target sample rate (Hz). If NULL or higher than input, original rate
  is kept.

- channels:

  Target audio channels (1 = mono, 2 = stereo).

- min_duration_s:

  Minimum duration threshold for valid recordings (default 60s).

- organize_folders:

  Subfolder structure: "grid" (G0059/), "date" (YYYY/MM/DD), "grid_date"
  (G0059/YYYY/MM/DD), "preserve", or "flat".

- rename_strategy:

  Naming strategy: "auto" (uses extracted datetime) or "keep".

- isolate_non_audio:

  Logical, isolate non-audio files?

- isolate_short:

  Logical, isolate short audio clips?

- timezone:

  Timezone string (default "Asia/Kolkata").

## Value

data.table containing audit log of standardization operations.

## Examples

``` r
ex <- pam_example_project()
demo <- tempfile("pamflow_std_")

# dry_run = TRUE only plans what would happen; nothing is written
plan <- suppressMessages(pam_standardize(
  ex$cfg, raw_dir = ex$audio_dir, standardized_dir = file.path(demo, "standardized"),
  isolated_dir = file.path(demo, "isolated"), dry_run = TRUE,
  target_format = "wav", min_duration_s = 1))
table(plan$action)
#> 
#> PLANNED_COPY_COMPLIANT 
#>                      6 

# \donttest{
if (requireNamespace("av", quietly = TRUE)) {
  # convert for real: the example WAV files become FLAC
  done <- suppressMessages(pam_standardize(
    ex$cfg, raw_dir = ex$audio_dir, standardized_dir = file.path(demo, "standardized"),
    isolated_dir = file.path(demo, "isolated"), target_format = "flac", min_duration_s = 1))
  table(done$action)
}
#> 
#> TRANSCODED 
#>          6 
# }
unlink(demo, recursive = TRUE)
```
