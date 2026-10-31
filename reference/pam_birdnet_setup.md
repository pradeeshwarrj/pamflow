# Create a private Python environment for BirdNET

Builds a virtual environment (never touching the system Python) with a
pinned Python version. Uses `uv` when it is installed (it downloads the
requested Python itself); otherwise falls back to `reticulate`, which
needs a matching Python already installed.

## Usage

``` r
pam_birdnet_setup(
  component = c("inference", "training"),
  python_version = "3.11",
  packages = NULL,
  envdir = pam_birdnet_env_dir(component),
  recreate = FALSE,
  dry_run = FALSE,
  uv = pam_find_uv()
)
```

## Arguments

- component:

  "inference" (the `birdnet` package, used by Stage 3) or "training"
  (BirdNET-Analyzer, used only by the standalone training tools, which
  are not part of the workflow).

- python_version:

  Python version for the environment. Default "3.11", chosen as widely
  supported by TensorFlow; change it if a package install reports an
  unsupported version.

- packages:

  pip requirements. Defaults to
  `pam_birdnet_default_requirements()[[component]]`.

- envdir:

  Environment folder. Defaults to pamflow's private location.

- recreate:

  If TRUE, delete and rebuild an existing environment.

- dry_run:

  If TRUE, only return the plan without creating anything.

- uv:

  Path to the uv executable. Found automatically when uv is on PATH or
  in a standard install location; set it if you installed uv elsewhere.

## Value

Invisibly, a list: `envdir`, `python`, `python_version`, `packages`.

## Details

Installing TensorFlow downloads roughly a gigabyte, so this can take
several minutes. In an interactive session you are asked to confirm
before anything is downloaded; use `dry_run = TRUE` to see the plan
first. Afterwards run
[`pam_birdnet_doctor()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_doctor.md).

## Examples

``` r
if (FALSE) { # \dontrun{
pam_birdnet_setup("inference", dry_run = TRUE)
pam_birdnet_setup("inference")
pam_birdnet_setup("training")
} # }
```
