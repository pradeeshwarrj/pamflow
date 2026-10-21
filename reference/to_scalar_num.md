# Safely Extract a Single Numeric Value from Soundecology/Seewave Returns

Returns NA_real\_ for NULL, non-scalar, or non-numeric inputs. Useful
because soundecology returns can be lists, data.frames, or numeric(0) on
short clips.

## Usage

``` r
to_scalar_num(x)
```

## Arguments

- x:

  An object returned by a soundecology/seewave function.

## Value

A length-1 numeric, or NA_real\_.
