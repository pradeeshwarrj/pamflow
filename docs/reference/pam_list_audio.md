# List Audio Files in a Directory (WAV + FLAC)

List Audio Files in a Directory (WAV + FLAC)

## Usage

``` r
pam_list_audio(dir, recursive = TRUE)
```

## Arguments

- dir:

  Character. Directory to scan.

- recursive:

  Logical. Recurse into subdirectories.

## Value

Character vector of file paths.

## Examples

``` r
ex <- pam_example_project()
basename(pam_list_audio(ex$audio_dir))
#> [1] "G0059_20260405_183000.wav" "G0059_20260405_183002.wav"
#> [3] "G0059_20260405_183004.wav" "G0110_20260406_060000.wav"
#> [5] "G0110_20260406_060002.wav" "G0110_20260406_060004.wav"
```
