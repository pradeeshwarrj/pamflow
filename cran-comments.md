## Submission

This is the first submission of pamflow to CRAN (version 0.6.0).

pamflow is an end-to-end workflow for passive acoustic monitoring: it
standardizes and checks field recordings, runs 'BirdNET' through a Python
package, cleans and validates detections, computes soundscape indices, and
prepares detection histories, count histories and model input for occupancy
and abundance models. It does not fit any models itself.

## Test environments

* Local: Windows 11, R 4.5.3 (`devtools::check(cran = TRUE, remote = TRUE,
  manual = TRUE)`, and again with `NOT_CRAN = "false"` and `--run-donttest`)
* win-builder: R release (4.6.2) and R-devel
* R-hub: Linux (R-devel), macOS arm64 (R-devel), Windows (R-devel), and the
  `nosuggests` platform
* GitHub Actions: macOS (release), Windows (release), Ubuntu (devel, release,
  oldrel-1)

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.
* The incoming check on win-builder (release and R-devel) also lists "Kahl",
  "et", "al" and "detections" as possibly misspelled words in the
  DESCRIPTION. The first three come from the author-year reference to the
  'BirdNET' paper (Kahl et al. 2021, <doi:10.1016/j.ecoinf.2021.101236>); the
  DOI is correct. "detections" is an ordinary English word.
* A local `devtools::check(cran = TRUE)` on Windows gives 0 errors, 0 warnings
  and 0 notes.

## Notes on specific points

* **Optional external software.** The package installs, loads, checks and
  passes its tests without Python, 'FFmpeg' or 'BirdNET'. Functions that need
  them check for them first and stop with an informative message
  (`pam_birdnet_doctor()` reports what is missing). Examples and tests that
  need 'FFmpeg' are guarded with `Sys.which()` (examples) and `skip_if()`
  (tests).
* **No downloads at install, load, example or test time.** The only function
  that creates a Python environment and downloads software is
  `pam_birdnet_setup()`. It is never called by examples or tests, and in an
  interactive session it asks for confirmation before downloading anything.
  'BirdNET' models and code are not bundled with the package, and the 'BirdNET'
  paper is cited in the DESCRIPTION and help pages.
* **`\dontrun{}` examples.** They are used only for functions that need the
  Python 'BirdNET' environment or a long training run
  (for example `pam_detect()`, `pam_birdnet_setup()`, `pam_birdnet_train()`,
  `pam_birdnet_benchmark()`, `pam_birdnet_cleanup()`, `pam_train_app()`).
  All other examples run, and use a small synthetic project written to
  `tempdir()` by `pam_example_project()`.
* **Writing to disk.** Nothing is written outside `tempdir()` during
  examples, tests or vignettes. The Python environment is created only on
  request, under `tools::R_user_dir("pamflow", "data")`.
* **R-hub `nosuggests`.** The only failure on this platform is "re-building of
  vignette outputs", because 'rmarkdown' is removed together with the other
  Suggests packages. Examples and tests pass without the Suggests packages.
* **Shiny apps.** Examples that launch an app run only in interactive
  sessions. The server logic is tested with `shiny::testServer()`, so no
  browser is opened.
