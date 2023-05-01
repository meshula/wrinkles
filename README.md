# Wrinkles app

V3 Prototype Project

contains:
* `OpenTime` math library
  * Topologies
  * Curve library
    * Bezier Curves
    * Linear curves
* Visualizer apps
    * Wrinkles app for visualizing frequency domain "plaid" charts
    * otvis, pyguitest for looking at curves/curve projections
* OpenTimelineIO prototype library
  * parse .otio files and project through them
  * treecode library (path through a binary tree)

## IP
* holodromes
    * 0 finding over cubic bezier
    * non-linearizing bezier projection
    * non-linearizing bezier inversion
    * arbitrary (splitting) inversion

## Todo
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
    * Allocators should be exposed as parameters, not through `allocator.ALLOCATOR`
* move to zig v0.11 and bump deps
* topology->[]topology projection (for handling inversions)

## ZIG REFERENCES

* [Zig Lang](https://github.com/ziglang/zig): The language homepage
* [Zig Learn](https://ziglearn.org/chapter-0/): Good starting place for a language overview
* [Language Reference](https://ziglang.org/documentation/master/): Full Language Reference
* [Stdlib Reference](https://ziglang.org/documentation/master/std/#A;std)
* [Stdlib Source](https://github.com/ziglang/zig/tree/master/lib/std): I hate to admit it but often times its faster to just look at the source of the standard lib rather than going through the docs

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

