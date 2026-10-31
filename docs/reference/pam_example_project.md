# Create a small example project to try pamflow on

Builds a tiny, synthetic pamflow project in a temporary folder: six
two-second WAV files (pure tones, 8 kHz, mono) from two recording grids
with pamflow-style file names, a deployment sheet, a configuration file,
and a BirdNET-style detections file for three species. It is meant for
the examples in the help pages, for tests, and for getting to know the
workflow without any field data. It needs only R packages that pamflow
already depends on: no FFmpeg, Python or internet connection.

## Usage

``` r
pam_example_project(dir = tempfile("pamflow_example_"))
```

## Arguments

- dir:

  Folder to create the project in. The default is a new folder inside
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html), which R removes
  when the session ends. If the folder exists it must be empty.

## Value

A list with:

- `root`:

  The project folder.

- `config`:

  Path to `config/config.yml`.

- `cfg`:

  The configuration, read with
  [`pam_config_read()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_config_read.md).

- `audio_dir`:

  Folder with the standardized audio.

- `files`:

  Paths of the six WAV files.

- `deployments`:

  Path to the deployment sheet.

- `detections`:

  Path to the detections batch file.

## Details

The project has this layout (the other folders are created when stages
run):

      <root>/
        config/config.yml
        metadata/deployments.csv
        data/standardized/G0059/ (3 files)
        data/standardized/G0110/ (3 files)
        data/detections/run01/batches/batch_001.csv
      

Grid `G0059` was recorded on 2026-04-05 at 18:30 and grid `G0110` on
2026-04-06 at 06:00; every file lies inside its deployment window, so a
scan finds no problems.

The detections file looks like the batch files that
[`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)
writes (three species, 3-second windows). It has a few things for the
cleaning stage to deal with: overlapping windows to merge,
low-confidence rows, a window past the end of its recording, and one
duplicated row. The stages after the scan need the master table, so run
[`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)
on `ex$cfg` first; the help-page examples show how.

The configuration only sets what differs from the defaults: occupancy
needs no minimum recording effort and one detection per species, recall
segments are 1 second long because the recordings are only 2 seconds
long, and the filter stage uses a single worker.

## Examples

``` r
ex <- pam_example_project()
#> Error in pam_example_project(): could not find function "pam_example_project"
basename(ex$files)
#> Error: object 'ex' not found
res <- suppressMessages(pam_scan_audio(ex$cfg))
#> Error: object 'ex' not found
res$summary$overall
#> Error: object 'res' not found
```
