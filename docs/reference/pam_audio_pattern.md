# Regex Pattern Matching Supported Audio Files

Regex Pattern Matching Supported Audio Files

## Usage

``` r
pam_audio_pattern()
```

## Value

Character scalar regex pattern (case-insensitive).

## Examples

``` r
grepl(pam_audio_pattern(), c("a.wav", "b.FLAC", "c.mp3"))
#> [1]  TRUE  TRUE FALSE
```
