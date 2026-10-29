# Check the machine and Python environments needed for BirdNET

Inspects the R session, the machine (CPU cores, RAM, GPU) and the two
pamflow BirdNET Python environments, and reports what is missing and
what to do about it. Nothing is installed or changed. TensorFlow is
probed in a separate process, so this never loads Python into your R
session.

## Usage

``` r
pam_birdnet_doctor(
  envs = list(inference = pam_birdnet_env_dir("inference"), training =
    pam_birdnet_env_dir("training")),
  quiet = FALSE
)
```

## Arguments

- envs:

  Named list with the folders of the "inference" and "training"
  environments. Defaults to pamflow's private environments.

- quiet:

  If TRUE, return the table without printing it.

## Value

Invisibly, a data.frame with columns `check`, `status`
(`ok`/`warn`/`fail`/`info`) and `detail`. Class `pam_birdnet_doctor`.

## Details

Assumptions: on native Windows, TensorFlow has no GPU support, so
pamflow runs BirdNET on CPU there; a detected NVIDIA GPU is reported as
information only. Run
[`pam_birdnet_setup()`](https://pradeeshwarrj.github.io/pamflow/reference/pam_birdnet_setup.md)
to create missing environments.

## Examples

``` r
if (FALSE) { # \dontrun{
pam_birdnet_doctor()
} # }
```
