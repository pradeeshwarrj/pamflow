# Generate PAM workflow reports

Gathers outputs from all completed stages and renders summary reports in
HTML, PDF and/or Excel format.

## Usage

``` r
pam_report(
  cfg,
  run_id = cfg$birdnet$run_id,
  formats = cfg$report$formats,
  output_dir = cfg$paths$reports,
  force = FALSE
)
```

## Arguments

- cfg:

  A list from `pam_config_read`.

- run_id:

  Character. The detection run to report on. Defaults to
  `cfg$birdnet$run_id`.

- formats:

  Character vector. One or more of `"html"`, `"pdf"`, `"excel"`.
  Defaults to `cfg$report$formats`.

- output_dir:

  Character. Directory for the output files. Defaults to
  `cfg$paths$reports`.

- force:

  Logical. Overwrite existing reports? Default FALSE.

## Value

Invisibly, a character vector of generated file paths.

## Details

HTML and PDF are rendered from an R Markdown template using
[`rmarkdown::render`](https://pkgs.rstudio.com/rmarkdown/reference/render.html).
PDF requires a LaTeX installation (e.g.
[`tinytex::install_tinytex()`](https://rdrr.io/pkg/tinytex/man/install_tinytex.html)).
If PDF rendering fails, a warning is issued and the other formats are
still produced.

Excel output is a multi-sheet workbook with one sheet per report
section, created with `openxlsx`.

## Examples

``` r
# \donttest{
if (requireNamespace("rmarkdown", quietly = TRUE) && rmarkdown::pandoc_available()) {
  ex <- pam_example_project()
  res <- suppressMessages(pam_scan_audio(ex$cfg))
  proc <- suppressMessages(pam_process_detections(ex$cfg))
  occ <- suppressMessages(pam_build_occupancy(ex$cfg))
  files <- suppressMessages(pam_report(ex$cfg, formats = "html"))
  basename(files)
}
#> [1] "report_run01.html"
# }
```
