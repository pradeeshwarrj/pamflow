# Launch PAM Standardization & Data Triage Shiny App

Interactive GUI for inspecting raw acoustic data, parsing timestamps,
previewing conversions, isolating non-audio/memo files, and performing
standardized audio transcoding.

## Usage

``` r
pam_standardization_app(cfg = NULL, raw_dir = NULL, lang = NULL)
```

## Arguments

- cfg:

  Optional configuration object from
  [`pam_load_config()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_load_config.md).

- raw_dir:

  Optional path override for raw audio directory.

- lang:

  Interface language code (for example `"en"`); `NULL` chooses it as
  [`pam_train_app()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_train_app.md)
  does. Translations live in `inst/i18n/<code>.yml`.

## Value

Runs Shiny application.

## Examples

``` r
if (interactive()) {
  ex <- pam_example_project()
  pam_standardization_app(ex$cfg, raw_dir = ex$audio_dir)
}
```
