# Follow audio files through the workflow

Collects, for every audio file, what each stage recorded about it: the
standardization result (Stage 0), the scan and QC flags (Stage 1),
filtering (Stage 2), detection (Stage 3), cleaning (Stage 4), validation
(Stage 5), ground-truth annotation (Stage 5b) and whether it went into
the occupancy histories (Stage 6). It reads the files the stages already
write, so it works on existing projects and changes nothing unless you
ask it to write.

## Usage

``` r
pam_audio_history(cfg, file = NULL, run_id = NULL, wide = FALSE, write = FALSE)
```

## Arguments

- cfg:

  A `pam_config` object.

- file:

  Optional audio file to look up: a path relative to the standardized
  audio folder (such as `"G0059/G0059_20260405_183000.wav"`), a file
  name, or, for files standardized by Stage 0, the name of the raw file.
  `NULL` (the default) returns every file.

- run_id:

  Optional detection run (or runs). `NULL` (the default) includes every
  run found in the project.

- wide:

  If `TRUE`, return one row per file with one column per stage (and per
  run, for the stages that belong to a run) holding the status.

- write:

  If `TRUE`, also save the long table to `metadata/audio_history.csv`.
  Nothing is written by default.

## Value

A data.table. The long table has one row per file and stage (and run)
with columns `rel` (path relative to the standardized audio folder, `NA`
for files Stage 0 set aside), `file` (file name), `stage`, `run_id`,
`status`, `detail` (what happened, in words), `n` (a count, such as the
number of detections) and `time` (when the stage recorded it, where the
stage keeps a time, otherwise the time its output file was written). The
attribute `stages_found` lists the stages whose outputs were found. With
`wide = TRUE` the table has `rel` plus one status column per stage.

## Details

Statuses: Stage 0 `ok`, `warning` or `failed`; Stage 1 `pass` or `fail`;
Stage 2 and 3 `ok` or `failed`; Stage 4 `kept` (some events survived
cleaning) or `removed` (none did); Stage 5 `reviewed` or `sampled`;
Stage 5b `annotated`, `partly annotated` or `drawn`; Stage 6 `included`
or `excluded`. Stages whose outputs are missing are skipped. Times are
saved in UTC when `write = TRUE`. The history is built from the current
outputs, so a stage you delete or rerun is shown as it now is.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
proc <- suppressMessages(pam_process_detections(ex$cfg))
#> Error: object 'ex' not found

# one row per file and stage
hist <- pam_audio_history(ex$cfg)
#> Error in pam_audio_history(ex$cfg): could not find function "pam_audio_history"
as.data.frame(hist)[1:3, c("file", "stage", "status", "detail")]
#> Error in as.data.frame.default(hist): cannot coerce class '"function"' to a data.frame

# one file, by name
one <- pam_audio_history(ex$cfg, file = "G0059_20260405_183004.wav")
#> Error in pam_audio_history(ex$cfg, file = "G0059_20260405_183004.wav"): could not find function "pam_audio_history"
as.data.frame(one)[, c("stage", "status", "detail")]
#> Error: object 'one' not found

# one row per file, one column per stage
as.data.frame(pam_audio_history(ex$cfg, wide = TRUE))
#> Error in pam_audio_history(ex$cfg, wide = TRUE): could not find function "pam_audio_history"
```
