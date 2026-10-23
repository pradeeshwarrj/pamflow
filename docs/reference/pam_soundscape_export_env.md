# Build a cleanroom function environment for PSOCK workers

Prevents workers from loadNamespace()-ing an outdated installed pamflow
copy when closures are serialized. All helper functions are re-parented
to an isolated env whose parent is baseenv().

## Usage

``` r
pam_soundscape_export_env(funs)
```

## Arguments

- funs:

  Named list of functions to export.

## Value

An environment suitable for clusterExport / worker closures.
