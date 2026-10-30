# Cut Audio Clip Preserving Source Format

Extracts a sub-section of an audio file and writes it to disk,
preserving the source file extension when possible.

## Usage

``` r
pam_cut_audio(in_path, out_path, from, to)
```

## Arguments

- in_path:

  Character. Source audio file path.

- out_path:

  Character. Output file path.

- from:

  Numeric. Start time in seconds.

- to:

  Numeric. End time in seconds.

## Value

Invisibly returns `out_path`.

## Examples

``` r
ex <- pam_example_project()
out <- tempfile(fileext = ".wav")
pam_cut_audio(ex$files[1], out, from = 0.5, to = 1.5)
pam_audio_info(out)$duration_s
#> [1] 1
unlink(out)
```
