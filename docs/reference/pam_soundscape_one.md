# Compute Ecoacoustic Soundscape Indices for a Single Audio File

Reads WAV or FLAC via
[`pam_read_audio`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_audio.md),
optionally downsamples to 24 kHz, applies a high-pass filter at
sub-window level, and computes configured acoustic indices (ACI, ADI,
AEve, Bio, H, M, NDSI).

## Usage

``` r
pam_soundscape_one(
  audio_path,
  low_stop_hz = NULL,
  cfg = NULL,
  window_sec = NULL
)
```

## Arguments

- audio_path:

  Character. Path to input audio file (`.wav` or `.flac`).

- low_stop_hz:

  Numeric. Highpass low-stop frequency in Hz (default 500).

- cfg:

  List. Parsed configuration structure from
  [`pam_config_read`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- window_sec:

  Numeric. Optional window duration in seconds.

## Value

A `data.table` with file/window metadata and index values.
