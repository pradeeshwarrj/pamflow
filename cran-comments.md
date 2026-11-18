## Resubmission

This is a resubmission of pamflow 0.6.0. Thank you for the review. 
Each point has been addressed:

* **"Tools for" at the start of the Description.** Removed. The Description
  now starts "An end-to-end workflow for passive acoustic monitoring
  projects".
* **Software names in single quotes.** 'BirdNET', 'Python', 'shiny', 'Excel',
  'HTML' and 'PDF' are now quoted in the Description. The Title names no
  software.
* **Writing to the user's home filespace.** No function has a default write
  location any more:
  - `pam_config_read()` / `pam_load_config()` now require the path of the
    config file. They no longer look for a config in the working directory or
    fall back to the template. Relative paths in the config are resolved
    against the folder holding the config file, never against `getwd()`.
  - `pam_standardize()` and `pam_standardization_app()` no longer default to
    `data/...` folders. Output folders must be given as arguments or in the
    config; otherwise the function stops with a message.
  - The soundscape functions (`pam_soundscape_run()`, `pam_soundscape_report()`,
    `pam_soundscape_run_vis()`) no longer fall back to `"."` or `getwd()`.
  - Examples, tests and the vignette write only to `tempdir()` (through
    `pam_example_project()`, `tempfile()` and `withr::local_tempdir()`). The
    optional 'Python' environment is created only when the user calls
    `pam_birdnet_setup()`, under `tools::R_user_dir("pamflow", "data")`.
* **Modifying the global environment.** Every `<<-` updated a variable defined
  in the enclosing function, but all `<<-` have now been replaced by a local
  environment. The parallel filter workers now run in `baseenv()` instead of
  `globalenv()`. Random draws use `withr::with_seed()` / `withr::local_seed()`,
  so `.Random.seed` is never changed. A new test checks the sources for `<<-`,
  `globalenv()` and `set.seed()`.


## Test environments

* Local: Windows 11, R 4.5.3 (`devtools::check(cran = TRUE, remote = TRUE,
  manual = TRUE)`, including examples with `--run-donttest`)
* Local: Ubuntu 24.04, R 4.3.3 with 'FFmpeg' installed
  (`R CMD check --as-cran --run-donttest`)
* win-builder: R-devel
* GitHub Actions: macOS (release), Windows (release), Ubuntu (devel, release,
  oldrel-1)
* First submission only: win-builder R release, and R-hub Linux (R-devel),
  macOS arm64 (R-devel), Windows (R-devel) and `nosuggests`

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.
* The incoming check on win-builder may list "Kahl", "et" and "al" as possibly
  misspelled words in the DESCRIPTION. They come from the author-year
  reference to the 'BirdNET' paper (Kahl et al. 2021,
  <doi:10.1016/j.ecoinf.2021.101236>); the DOI is correct.

`spelling::spell_check_package()` and `urlchecker::url_check()` report no
problems.

## Notes on specific points

* **Optional external software.** The package installs, loads, checks and
  passes its tests without 'Python', 'FFmpeg' or 'BirdNET'. Functions that
  need them check for them first and stop with an informative message
  (`pam_birdnet_doctor()` reports what is missing). Examples and tests that
  need 'FFmpeg' are guarded with `Sys.which()` (examples) and `skip_if()`
  (tests).
* **No downloads at install, load, example or test time.** The only function
  that creates a 'Python' environment and downloads software is
  `pam_birdnet_setup()`. It is never called by examples or tests, and in an
  interactive session it asks for confirmation before downloading anything.
  'BirdNET' models and code are not bundled with the package, and the
  'BirdNET' paper is cited in the DESCRIPTION and help pages.
* **`\dontrun{}` examples.** They are used only for functions that need the
  'Python' 'BirdNET' environment or a long training run (for example
  `pam_detect()`, `pam_birdnet_setup()`, `pam_birdnet_train()`,
  `pam_birdnet_benchmark()`, `pam_birdnet_cleanup()`, `pam_train_app()`).
  All other examples run, and use a small synthetic project written to
  `tempdir()` by `pam_example_project()`.
* **Internal help pages.** A few unexported helpers have help pages marked
  `@keywords internal`; none of them has examples.
* **R-hub `nosuggests`.** The only failure on this platform is "re-building of
  vignette outputs", because 'rmarkdown' is removed together with the other
  Suggests packages. Examples and tests pass without the Suggests packages.
* **Shiny apps.** Examples that launch an app run only in interactive
  sessions. The server logic is tested with `shiny::testServer()`, so no
  browser is opened.
