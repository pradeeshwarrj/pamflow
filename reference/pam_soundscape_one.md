# Compute Ecoacoustic Soundscape Indices for a Single Audio File

Compute Ecoacoustic Soundscape Indices for a Single Audio File

## Usage

``` r
pam_soundscape_one(wav_path, low_stop_hz = NULL, cfg = NULL, window_sec = NULL)
```

## Arguments

- wav_path:

  Character. Path to input WAV file.

- low_stop_hz:

  Numeric. Highpass low-stop frequency in Hz (default 500).

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- window_sec:

  Numeric. Optional window duration in seconds.

## Value

A `data.table` with file/window metadata and index values.
