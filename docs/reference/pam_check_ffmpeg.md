# Check that FFmpeg is installed and supports the filter chain

Check that FFmpeg is installed and supports the filter chain

## Usage

``` r
pam_check_ffmpeg(ffmpeg = "ffmpeg", filter = NULL)
```

## Arguments

- ffmpeg:

  Executable name or full path.

- filter:

  Filter string to test on 0.1 s of silence.

## Value

The first line of FFmpeg's version output. Aborts with install advice if
FFmpeg is missing or too old for the filter.

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("ffmpeg"))) {
  pam_check_ffmpeg("ffmpeg", filter = pam_highpass_filter_string(250, 8))
}
#> [1] "ffmpeg version 9.0.2-full_build-www.gyan.dev Copyright (c) 2000-2026 the FFmpeg developers"
# }
```
