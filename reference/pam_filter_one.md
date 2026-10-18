# Filter one audio file with FFmpeg

Base R only, so it can be shipped to parallel workers without the
package installed. Writes to `<output>.part` and renames on success, so
an interrupted run never leaves a half-written file that looks finished.

## Usage

``` r
pam_filter_one(item, filter, ffmpeg = "ffmpeg")
```

## Arguments

- item:

  List with `input`, `output` (paths) and `bits` (input bit depth; 16,
  24 or 32 are preserved, anything else becomes 16).

- filter:

  Filter string from
  [`pam_highpass_filter_string()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_highpass_filter_string.md).

- ffmpeg:

  Executable name or path.

## Value

A list: `ok` (logical) and `message` (last FFmpeg error lines, or "").
