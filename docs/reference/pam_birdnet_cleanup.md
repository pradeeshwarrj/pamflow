# Stop BirdNET worker processes that were left behind

Interrupting a run (Esc) or a crash can leave the worker processes of
the Python `birdnet` package running in the background, holding memory
(about 260 MB each). This finds those orphans and stops them. A worker
counts as an orphan only if the process that started it no longer
exists, so workers of a run that is still going are never touched.

## Usage

``` r
pam_birdnet_cleanup(kill = TRUE, quiet = FALSE)
```

## Arguments

- kill:

  If FALSE, only report the orphans without stopping them.

- quiet:

  If TRUE, print nothing.

## Value

Invisibly, a data.frame with `pid`, `name`, `parent_pid` and `killed`
(zero rows if there were no orphans).

## Details

[`pam_detect()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_detect.md)
and the training functions call this automatically (after an interrupt,
and before a run starts), so you rarely need it.

## Examples

``` r
if (FALSE) { # \dontrun{
pam_birdnet_cleanup(kill = FALSE)   # just look
pam_birdnet_cleanup()               # stop them
} # }
```
