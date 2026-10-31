# Changelog

## pamflow (development version)

### Occupancy occasions

- **Stage 6 now uses `occupancy.occasion_length_days`.** Until now
  [`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md)
  always used one-day occasions and ignored the setting. Occasions are
  now blocks of that many days, starting on the first recorded day and
  the same for every site; `min_effort_hours` applies to the whole
  occasion. With the default of 1 day the results are unchanged.
  Existing occupancy outputs are kept unless you pass `force = TRUE`.

### Ecological products

- **[`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md)**
  chooses a confidence threshold for each species from the Stage 5
  validation. For each species it takes the lowest confidence whose
  estimated precision is within `tolerance` (0.05) of that species’ own
  best, so no precision target is needed. Species with too little
  validation get the global threshold (the `reason` column says why),
  and a `manual` table overrides any species. `write = TRUE` saves
  `species_thresholds.csv`, which can be used as
  `processing.species_thresholds_file`.
- **[`pam_detection_table()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detection_table.md)**
  gives one row per site, time bin and species with detections,
  recordings with a detection, recording effort and detections per hour
  (zeros included). The bin length defaults to
  `occupancy.occasion_length_days` (1 day) and can be set with
  `bin_days`. It is the base for the planned activity, richness and
  abundance functions.
- **[`pam_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_activity.md)**
  gives detections per recorded hour for each species by hour of the
  day, day, week or month (pooled over sites or per site), for daily and
  seasonal activity patterns. Recording effort is split over the clock
  hours each recording covers, so recordings that start part way through
  an hour or cross midnight are counted correctly. It accepts the same
  species selection and thresholds as the table, and returns a relative
  activity index (1 = the species’ peak).
  **[`pam_plot_activity()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_plot_activity.md)**
  draws it.
- **[`pam_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_richness.md)**
  gives species richness and Hill numbers (orders you choose, default 1
  and 2) for every site and time bin and for every site over the whole
  survey, the expected species accumulation over sites, and the Chao2
  estimate of how many species were missed. A species counts as present
  in a bin only with at least `min_events` events (default 1), and Hill
  numbers can weight species by their event counts or by presence only.
  The site table can be joined to habitat covariates by `site_id`.
  **[`pam_plot_richness()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_plot_richness.md)**
  draws the accumulation curve or richness per site.

### Stage 7: input for occupancy and abundance models

pamflow prepares the data; it does not fit the models and does not
depend on any modelling package.

- **[`pam_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_history.md)**
  builds the count history of one species (detections or recordings with
  a detection per site and occasion, `NA` where a site was not surveyed)
  with matching matrices of recording effort and days.
  **[`pam_count_histories()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_count_histories.md)**
  does it for many species in one pass over the detections, on a shared
  grid of sites and occasions.
  **[`pam_as_count_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_as_count_history.md)**
  wraps counts from another source, and
  **[`pam_add_site_covariates()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_add_site_covariates.md)**
  attaches covariates by `site_id` later.
- **[`pam_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_model_input.md)**
  turns histories into `y`, `siteCovs` and `obsCovs` (counts or
  detection / non-detection, optionally standardised and written to
  CSV). For several species `y` is a species x site x occasion array.
  With `seasons` it groups occasions into primary periods for
  multi-season models and returns both the wide matrix (for `unmarked`
  and `ubms`) and arrays (for `spOccupancy`), padded to equal length,
  with optional season covariates as yearly site covariates.
  **[`pam_define_seasons()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_define_seasons.md)**
  builds seasons by year or month.
- **[`pam_check_model_input()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_check_model_input.md)**
  checks dimensions, site and occasion matching, response values and
  missing values before the input goes to a modelling package.

### Reports and guide

- **[`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md)
  has new sections**: species richness and diversity (per-site table,
  Hill numbers, species accumulation and the Chao2 estimate), activity
  patterns (detections per recorded hour by hour of day and by week) and
  the per-species thresholds saved by
  [`pam_species_thresholds()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_species_thresholds.md).
  The Excel workbook gets matching sheets. A section is left out, and
  noted in the log, when its inputs are missing.
- The guide and README describe the new functions: Stage 7 model input,
  thresholds, activity and richness, plus
  [`pam_audio_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_history.md)
  in the function reference and FAQ, and the occasion length of Stage 6.

## pamflow 0.5.0

### Audio history

- **[`pam_audio_history()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_history.md)**
  shows what happened to each audio file across the workflow:
  standardization, scan and QC flags, filtering, detection, cleaning,
  validation, recall annotation and whether it went into the occupancy
  histories. It is built from the files the stages already write, so it
  works on existing projects and writes nothing unless you pass
  `write = TRUE` (which saves `metadata/audio_history.csv`). Use
  `file =` to look at one file and `wide = TRUE` for one row per file
  with a status column per stage.

### Examples

- **[`pam_example_project()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_example_project.md)**
  builds a tiny synthetic project (six short WAV files from two grids, a
  deployment sheet and a config) in a temporary folder. It needs no
  FFmpeg, Python or internet, so help-page examples and tests can run
  anywhere.
- Runnable examples were added to the config, audio, filename-parsing,
  deployment, QC, scan, checkpoint and logging functions, and to the
  detection cleaning, validation, recall and occupancy functions (the
  example project includes a small BirdNET-style detections file for
  them).
- Examples that need FFmpeg, `rmarkdown` or `soundecology` run only when
  those are available (`\donttest` plus a check), the Shiny apps have
  `if (interactive())` examples, and functions that need the BirdNET
  Python environment keep `\dontrun`. Functions that need FFmpeg, Python
  or an interactive session get guarded examples in later batches.
- README: the deployment-sheet example gave the grid as `G0059`; the
  sheet expects a number (`59`).

### Standalone BirdNET model training (not a workflow stage)

Training your own classifier is a separate tool. No workflow stage calls
it and the workflow runs without it; the trained model is used by
pointing the `birdnet:` config section at it.
`pam_birdnet_setup("training")` creates the training environment.

- **Training app.**
  [`pam_train_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_train_app.md)
  is a Shiny app laid out like the Analyzer GUI’s training tab: choose
  the data, set the options, watch live progress and learning curves,
  repeat a training to see how much the scores vary, compare earlier
  runs, and copy the config lines for the new model. The interface text
  lives in `inst/i18n/` (English included; other languages can be added
  by translating one file).
- [`pam_birdnet_train_prepare()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_prepare.md),
  [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md),
  [`pam_birdnet_train_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_metrics.md)
  and
  [`pam_birdnet_train_repeat()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train_repeat.md)
  run BirdNET-Analyzer’s own `birdnet-train` command, with the same
  defaults and results as the Analyzer GUI (version 2.4.0). Every run
  keeps a log and a record of what was run.
- **Per-class test results.** With a separate test folder,
  [`pam_birdnet_train()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_train.md)
  returns `evaluation`: precision, recall, F1, AUPRC and AUROC for every
  class plus the macro average, read from the Analyzer’s
  `<output>_evaluation.csv`. The training app shows them on the Results
  tab (best threshold per class or 0.5) with the confusion counts.

### BirdNET without birdnetR

- **birdnetR is no longer used.** Stage 3 runs the Python `birdnet`
  package (0.2.x) directly through a small batch script shipped with
  pamflow (`inst/python/pam_birdnet_predict.py`). Detections are
  identical to birdnetR’s on the pilot data and the run is faster.
- **Own Python environment.**
  [`pam_birdnet_setup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_setup.md)
  creates private virtual environments (inference and training) with
  `uv`;
  [`pam_birdnet_doctor()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_doctor.md)
  checks the machine and the environments.
- **Worker control.** `birdnet$workers` sets the number of worker
  processes; if unset, half of the physical cores are used. New options:
  `top_k`, `py_batch_size`, `n_producers`, `sigmoid_sensitivity`,
  `device`, `python_env`. `batch_size` and `tflite_threads` were
  birdnetR settings and are ignored.
- **Benchmark.**
  [`pam_birdnet_benchmark()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_benchmark.md)
  measures throughput for several worker counts and estimates the time
  for the whole archive.
- **Clearer errors.**
  [`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)
  now names missing configuration entries.
- **No leftover processes.** Interrupting a run (Esc) stops BirdNET and
  all its worker processes;
  [`pam_birdnet_cleanup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_cleanup.md)
  stops workers left behind by an earlier crash.

## pamflow 0.4.0

### Stage 00 Data Triage & Standardization

- **Audio Standardization Engine**: Added
  [`pam_standardize()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_standardize.md)
  to process multi-format field audio (WAV, FLAC, MP3) into uniform 48
  kHz Mono WAV format while keeping raw audio files strictly read-only.
- **Raven Compass Triage App**: Added
  [`pam_standardization_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_standardization_app.md),
  an interactive Shiny app with `[Inspect]`, `[Convert]`, and `[Log]`
  tabs.
- **Automatic Isolation**: Short files (\< 60 seconds) or corrupt audio
  are automatically segregated into `data/isolated/`.
- **Metadata Parsing**: Added
  [`pam_parse_datetime()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_parse_datetime.md)
  and
  [`pam_extract_grid()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_extract_grid.md)
  to extract timestamps and deployment/sensor IDs directly from
  filenames.

### Infrastructure, Branding & Documentation

- **Package Logo**: Integrated hexagonal logo (`man/figures/logo.png`)
  and site favicons.

### Compliance & Maintenance

- Standardized log outputs with strict uppercase log levels (`"INFO"`,
  `"WARN"`, `"ERROR"`).
- Ensured pure ASCII compliance across all `.R` files and Shiny
  interfaces.

## pamflow 0.3.0

### Major Features

- **FLAC compatibility**: All 8 pipeline stages now natively support
  `.flac` files alongside `.wav`.
- **Audio Utilities Module (`R/utils_audio.R`)**: Added
  [`pam_read_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_read_audio.md),
  [`pam_audio_info()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_audio_info.md),
  [`pam_cut_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_cut_audio.md),
  [`pam_list_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_list_audio.md),
  and
  [`pam_is_flac()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_is_flac.md)
  for unified audio I/O.
- **Stage 1 (Scan)**: Vectorized header reading via `av` and `tuneR`.
- **Stage 2 (Filter)**: Dynamic FFmpeg codec branching (`-c:a flac` vs
  `-c:a pcm_s16le`).
- **Stage 2b (Soundscape)**: PSOCK worker export env with FLAC decoding.
- **Stage 5 (Validation)**: Format-preserving clip export and on-the-fly
  FLAC -\> WAV transcoding for Shiny browser playback.

## pamflow 0.2.0

### Major Features

- **Workflow B: Soundscape Analysis** introduced.
- **Stage 2b (Soundscape Indices)**: Added
  [`pam_soundscape_run()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run.md)
  to compute ACI, ADI, AEve, Bio, H, M, and NDSI following
  Bradfer-Lawrence et al. (2019).
- **Stage 2c (Soundscape Visualizations)**: Added
  [`pam_soundscape_run_vis()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_run_vis.md)
  and
  [`pam_soundscape_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_soundscape_report.md)
  to generate automated 24-hour diel profiles, Day/Night comparisons,
  and HTML diagnostic reports.

### Performance & Optimizations

- Implemented 1-minute sub-windowing for high-performance memory safety.
- Optimized audio high-pass filtering (500 Hz) at the sub-window level.
- Added dynamic downsampling (to 24 kHz) for ecoacoustic frequency
  bounds, increasing processing speed by 10x-15x.
- Checkpointing mechanism (`done.txt`) implemented for crash-resilient
  resuming.

## pamflow 0.1.0

- First release.
- **Stage 1 (Scan)**: Audio scanning and QC
  ([`pam_scan_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_scan_audio.md)).
- **Stage 2 (Filter)**: High-pass filtering (Optional)
  ([`pam_filter_audio()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_filter_audio.md)).
- **Stage 3 (Detection)**: BirdNET batch detection with parallel workers
  and resume support
  ([`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)).
- **Stage 4 (Process Detection)**: Detection cleaning, filtering, and
  merging
  ([`pam_process_detections()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_process_detections.md)).
- **Stage 5 (Validation)**: Interactive validation app with precision
  metrics
  ([`pam_validation_draw()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_draw.md),
  [`pam_validation_export()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_export.md),
  `pam_validation_app()`,
  [`pam_validation_metrics()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_validation_metrics.md)).
- **Stage 6 (Occupancy detection History)**: Occupancy detection
  histories and covariates
  ([`pam_build_occupancy()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_build_occupancy.md)).
- **Stage 8 (Report)**: HTML and Excel reports
  ([`pam_report()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_report.md)).
- Config-driven pipeline — all settings in a single YAML file.
- R CMD check clean (0 errors, 0 warnings, 0 notes).
- Tested on pilot data.
