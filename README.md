# Wrinkles app

V3 Prototype Project

contains:
* `OpenTime` math library
  * Topologies
  * Curve library
    * Bezier Curves
    * Linear curves
* Wrinkles app for visualizing curves/projections
* OpenTimelineIO prototype library
  * parse .otio files and project through them
  * treecode library (path through a binary tree)

## Todo

## IP
* holodromes
    * 0 finding over cubic bezier
    * non-linearizing bezier projection
    * non-linearizing bezier inversion
    * arbitrary (splitting) inversion

## TODO
* add back in linear and bezier curve topologies
    * with linearizing
    * add hododrome decomposition to bezier/bezier projection
* `project_topology` in the projection operator (whoops)
* replacing `f32` with `opentime.Ordinate`
    * struct/union with add/mul/div/sub
    * rational object as an entry in the union (i32/i32)
* sampling
* domains (how do you handle that you want to evaluate the timeline at 30fps?)
* transitions

### later
* schema design
* `graphviz` viewer for otio files
    * plain format (dot -Tplain) produces a parsable output
    * visualize graph transformations over a topology with different targets
* redesign the `opentimelineio` layer
    * clean up mess of `Item` and `ItemPtr`
* move to zig v0.11 and bump deps
* clean up mess around allocators in math libraries
* topology->[]topology projection (for handling inversions)

### DONE

## Path System

* support arbitrary path lengths
    * use an array list of u128 to encode arbitrarily long paths
* arbitrary `TopologicalPathHash` lengths
* fix the simple_cut
* JSON OTIO parsing
    * can parse small OTIO files (but because of path length constraints, can't
      build maps for large files)
 
* Right now the topology has bounds, transform and curves.  This is
  inconsistent because the curves _inside_ the topology also represent a
  transformation, and implicitly define bounds (in that they're finite lists of
  segments, which are bounded).  The math reflects this - the way that
  transform and boundary are applied is pretty inconsistent.

* Part of the reason why this is the case is that there are several special
  cases of topology in play:
    * infinite identity (could have a transform but no bounds)
    * finite segments (do they have bounds?)
    * empty

Two options:
* do what we did for the graph and define a set of operators that bundle up a
  topology and work through the cases, providing clean constructors for those
  useful special types
* break these features up into things that the topology can contain and
  localize the math, push the matrix into handling combinations of those child
  types

* Stacks
* Timeline
* Gap (fully)

* how hard would parsing OTIO JSON be?  Would be cool to read in real
  timeilines and do transformations there

### Inversion

* need to add inversion functions to the topologies
* add error when a function isn't trivially invertible
* if we do something with the mappings, when things aren't trivially
  invertible, we still know how to invert them and how the mapping functions.
  Can we exploit this? Or is the juice not worth the squeeze for this project

### Optimization and Caching

* MxN track related time stuff - the map should cache those kinds of intermediates
* Can the map also cache optimizations like linearizing curves?

### Ordinate Notes

```zig
const Ordinate = union(enum) {
    f32: f32,
    rational: rational,

    // math
    pub fn add() Ordinate {}
    pub fn addWithOverflow() Ordinate {}
    pub fn sub() Ordinate {}
    pub fn subWithOverflow() Ordinate {}
    pub fn mul() Ordinate {}
    pub fn mulWithOverflow() Ordinate {}
    pub fn divExact() Ordinate {}
    pub fn divFloor() Ordinate {}
    pub fn divTrunc() Ordinate {}

    pub fn to_float() f32 {}
};
```

