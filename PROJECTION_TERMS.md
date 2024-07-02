# Projection Terms

## Overview

This document explains the terminology of projections and related spaces that
this library uses (or should use).

## Definitions

Given a function, y = f(x), we can define two spaces: the input space (x) and
the output space (y).

If we have two functions:

1. y = f(x)
2. w = g(y)

Then w(x) = g(f(x)).  

## Projection

Another way of saying this is "projecting a value in the space of x to the
space of w".  In functional terms, this is projecting f through g, or feeding
the output of f to the input of g.

Given a transform function, be it curve or an affine, to say "is applied to",
as in
`b2c_xform.applied_to(a2b_xform)`
is to say the output of a2b_xform will be used as an input to b2c_xform, and
the resulting transform will project from the input of a2b_xform to the output
space of b2c_xform.

If b2c_xform maps B->C and a2b_xform maps A->B then
`b2c_xform.applied_to(a2b_xform)` maps A->C.

Synonomously, `b2c_xform.project_type(a2b_xform)` would produce a new transform that
maps A->C.

## TODO HACK CBB XXX notes for API revision

### always using explicit spaces with transforms and transformations

The code has lots of abstract "xform" type names vs "a2b_xform".

### use a more functional (vs OO) syntax for composing transforms

*TODOHACKCBBXXX* in the final form of the API, using the terminology:

```zig
const a2c = transform(
    .{
        .in_to_middle_space = a2b,
        .middle_to_output_space    = b2c,
    },
);
```

This disambiguates which space is and what the final transformation will be.

### handle discontinuities and gaps in either curve model or the topology model
