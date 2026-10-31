# Stage 2: high-pass filter all QC-passed recordings

Applies a Butterworth high-pass (default 250 Hz, 48 dB/octave) with
FFmpeg and writes filtered copies (WAV or FLAC) to `paths$filtered`,
mirroring the folder structure and file names of
`paths$audio_standardized`. Originals are never modified.

## Usage

``` r
pam_filter_audio(cfg, master = NULL, force = FALSE)
```

## Arguments

- cfg:

  A `pam_config` object. Uses the `filter` section and paths.

- master:

  Optional master table from `pam_scan_audio()$master`; if NULL it is
  read from `metadata/audio_master.csv`.

- force:

  If TRUE, ignore the checkpoint and re-filter everything.

## Value

Invisibly, a list: `n_pending`, `n_ok`, `n_failed`, `results_file`.

## Details

Resumable: completed files are recorded in `metadata/02_filter.done`
only after the output has been written and verified (readable, same
duration, sample rate and channels). Per-file outcomes, including FFmpeg
error text, are appended to `metadata/02_filter_results.csv`. Only files
with `qc_pass == TRUE` are filtered. Format (WAV vs FLAC) is preserved
from source files. Run with
`pam_run_stage("02_filter", pam_filter_audio, cfg)`.

## Examples

``` r
# \donttest{
if (nzchar(Sys.which("ffmpeg"))) {
  ex <- pam_example_project()
  # the later stages read the master table that the scan builds
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  out <- suppressMessages(pam_filter_audio(ex$cfg))
  out$n_ok
  basename(list.files(ex$cfg$paths$filtered, recursive = TRUE))
}
#> Error in pam_example_project(): could not find function "pam_example_project"
# }
```
