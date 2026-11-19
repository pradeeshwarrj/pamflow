# Run a workflow stage with logging and error isolation

Logs start time, end time, duration and every warning, and converts
errors into a logged failure instead of terminating the whole workflow.

## Usage

``` r
pam_run_stage(stage, fn, cfg, ...)
```

## Arguments

- stage:

  Stage name (e.g. "03_detect").

- fn:

  Function taking `cfg` as its first argument.

- cfg:

  A `pam_config` object.

- ...:

  Passed on to `fn`.

## Value

A list: `status` ("ok" or "failed"), `result`, `duration` (difftime),
`warnings` (character).

## Examples

``` r
ex <- pam_example_project()
res <- suppressMessages(pam_run_stage("demo", function(cfg, x) x * 2, ex$cfg, x = 21))
res$status
#> [1] "ok"
res$result
#> [1] 42

# an error is logged and returned as a failed status; it does not stop your script
bad <- suppressMessages(pam_run_stage("demo_fail", function(cfg) stop("boom"), ex$cfg))
bad$status
#> [1] "failed"
```
