# Compute Ecoacoustic Soundscape Indices for a Single Audio File

Reads a WAV file, applies an optional low-stop (highpass) filter,
resamples high-sample-rate audio to 24 kHz for ecoacoustic frequency
bounds (max 11-12 kHz), splits the recording into internal analysis
windows, and computes ecoacoustic indices dynamically configured in
`cfg$soundscape$acoustic_indices`.

## Usage

``` r
pam_soundscape_one(wav_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL)
```

## Arguments

- wav_path:

  Character. Path to input WAV file.

- low_stop_hz:

  Numeric. Highpass low-stop frequency in Hz (default 500). Pass NULL or
  0 to skip filtering.

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- window_sec:

  Numeric. Optional window duration in seconds (e.g. 600 for 10
  minutes).

## Value

A `data.table` with columns for `file_id`, `window_index`,
`window_start_sec`, `window_end_sec`, and computed index values.
