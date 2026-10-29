# Stage 3: run the custom BirdNET classifier on all QC-passed recordings

Reads from the filtered folder (default) or the standardized folder
(`birdnet$input`), runs BirdNET in parallel worker processes, and writes
raw detections in batches to `<detections>/<run_id>/batches/`.

## Usage

``` r
pam_detect(cfg, master = NULL, sample_n = NULL, seed = 1L, force = FALSE)
```

## Arguments

- cfg:

  A `pam_config` object (uses the `birdnet` section).

- master:

  Optional Stage 1 master table; if NULL it is read from
  `metadata/audio_master.csv`.

- sample_n:

  If set, process a random sample of this many files (for pilots). The
  same `seed` gives the same sample.

- seed:

  Seed for the pilot sample.

- force:

  If TRUE, delete this run's earlier results and start over.

## Value

Invisibly, a list: `n_pending`, `n_done`, `n_failed`, `n_detections`,
`run_dir`.

## Details

BirdNET runs in pamflow's Python inference environment (see
[`pam_birdnet_setup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_setup.md))
using the `birdnet` Python package, which does its own multiprocessing:
`birdnet$workers` worker processes each load the model (an unset value
means half of the physical cores). `top_k` limits the species kept per 3
s segment (NULL = all above `min_confidence`). Resumable. A file is
marked done (`<run_dir>/done.txt`) only after its batch file is on disk,
and files with no detections count as done. If a crash happens between
writing a batch and updating the checkpoint, those files are re-run, and
[`pam_assemble_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_assemble_detections.md)
removes the duplicates. Per-file outcomes (seconds, errors) go to
`file_results.csv`; settings and the `birdnet` package version go to
`run_settings_*.yml`. Run with
`pam_run_stage("03_detect", pam_detect, cfg)`.
