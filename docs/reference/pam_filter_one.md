# Filter one audio file with FFmpeg (WAV or FLAC)

Base R only, so it can be shipped to parallel workers without the
package installed. Writes to `<output>.part` and renames on success, so
an interrupted run never leaves a half-written file that looks finished.
Preserves the file format (WAV or FLAC) based on output extension.

## Usage

``` r
pam_filter_one(item, filter, ffmpeg = "ffmpeg")
```

## Arguments

- item:

  List with `input`, `output` (paths) and `bits` (input bit depth; 16,
  24 or 32 are preserved for WAV, FLAC outputs `-c:a flac`).

- filter:

  Filter string from
  [`pam_highpass_filter_string()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_highpass_filter_string.md).

- ffmpeg:

  Executable name or path.

## Value

A list: `ok` (logical) and `message` (last FFmpeg error lines, or "").

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("ffmpeg"))) {
  ex <- pam_example_project()
  item <- list(input = ex$files[1], output = tempfile(fileext = ".wav"), bits = 16)
  res <- pam_filter_one(item, pam_highpass_filter_string(250, 8))
  res$ok
  unlink(item$output)
}
# }
```
