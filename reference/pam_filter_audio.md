# Stage 2: high-pass filter all QC-passed recordings

Applies a Butterworth high-pass (default 250 Hz, 48 dB/octave) with
FFmpeg and writes filtered copies to `paths$filtered`, mirroring the
folder structure and file names of `paths$audio_standardized`. Originals
are never modified.

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
with `qc_pass == TRUE` are filtered. Run with
`pam_run_stage("02_filter", pam_filter_audio, cfg)`.
