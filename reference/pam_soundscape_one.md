# Calculate Soundscape Indices for One Audio File

Calculate Soundscape Indices for One Audio File

## Usage

``` r
pam_soundscape_one(
  file_path,
  low_stop_hz = 500,
  anthrophony_range = c(1000, 2000),
  biophony_range = c(2000, 11000)
)
```

## Arguments

- file_path:

  Character path to a WAV audio file.

- low_stop_hz:

  Numeric frequency (Hz) for highpass low-stop filter. Default 500.

- anthrophony_range:

  Numeric length-2 vector for anthrophony band (Hz). Default c(1000,
  2000).

- biophony_range:

  Numeric length-2 vector for biophony band (Hz). Default c(2000,
  11000).

## Value

A data.table with 1 row and columns for all 7 indices (ACI, ADI, AEve,
Bio, H, M, NDSI).
