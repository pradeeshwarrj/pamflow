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
#> Error in pam_example_project(): could not find function "pam_example_project"
basename(pam_list_audio(ex$audio_dir))
#> Error: object 'ex' not found
```
