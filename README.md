# Wrinkles app - V3 Prototype Project

contains:

* `OpenTime` math library
  * Topologies
  * Curve library
    * Bezier Curves
    * Linear curves
  * Sampling tools, projecting samplings, signal generators, etc.
* Visualizer apps
    * Wrinkles app for visualizing frequency domain "plaid" charts
    * curvet, otvis, pyguitest for looking at curves/curve projections
* OpenTimelineIO prototype library
  * parse .otio files and project through them
  * treecode library (path through a binary tree)

## Current Todo List (7/2/24)

 * [x]  fix the memory leak (stephan)
 * [x]  switch the polarity on the interpolating function + test (stephan)
 * [x]  all tests should pass
 * [x]  confirm that project topology should be b2c.project(a2b) -> a2c
 * [ ]  thread ^ function through opentimelineio demo
  * [x] implement projections through the TopologicalMap to specific end points
  * [ ]  and demo of just using OTIO directly to compute frame numbers
  * [ ]  demo of using OTIO + libsamplerate together
   * [ ] build mapping of topology + media references that can be handed to
         libsamplerate
   * [ ] build a map of an arbitrary slice of the output timeline to
         references

 * [ ] should `resampled` only work for interpolating Samplings?
 * [ ]  time_topology: is projecting the end point an error?  Or not?
        **For context**: for most of the run of the project, we had this return
        an error.OutOfBounds.  For the sampling tests, there are a bunch of
        places where we want to project the end point, so a second check in
        project was added that checked to see if the projected point was the
        end point.  
    * [ ] See also: the AffineTopology.inverted function
    * [ ] time_topology.zig
    * [ ] test_topology_projections.zig
 * [ ]  `DiscreteDatasourceIndexGenerator` <- what do we do this
 * [ ]  rename retimed_linear_curve_{non}_interpolating
 * [ ] should be `a2b.joined_with(b2c)` -> a2c -- thread this through the code
 * [ ]  let brains cool off <- beers
 * [ ]  port to sokol
 * [ ]  lumpy bits in the API
   * [ ] project_curve returns a []curve instead of a topology?
   * [ ] time/value vs input/output
   * [ ] consistent names
   * [ ] linear trimmed_in_input_space: promotes to bezier, trims there and
         then demotes back.  should do everything on the linear knots
   * [ ] should the sampling library be so built around time as the domain
         to sample over?
   * [ ] handle acyclical sampling as well (variable bitrate data, held
         frames, etc).
   * [x] there is a second set of sampling related bits in the topology
         library... see `sample_over` and the step mapping in there

### Build Questions

* [x] remove the check step (can the regular steps work if all_check_step
      depends on them?)

### Bigger, Later Questions/Todos

 * [ ]  what if not beziers internally but instead b-splines with bezier
   interfaces
 * [ ]  rebuild in c?
 * [ ]  PR to OTIO?

## PAST LIST IP

* Find the two or three point projection approximation
* Add the graph to the ui
* thread the duals through findU

* todo:
    * [ ] derivative with dual at u = 0
    * [ ] using the derivative in the projection
    * [ ] testing the 2 point approximation using computed derivatives
    * [ ] show derivatives on linearized curves
    * [ ] show derivatives on projected curves / projected curve imagine settings

* hododromes
    * [x] 0 finding over cubic bezier
    * [ ] non-linearizing bezier projection
    * [ ] non-linearizing bezier.affine projection
    * [ ] non-linearizing affine.bezier projection
    * [ ] non-linearizing bezier inversion
    * [ ] arbitrary (splitting) inversion

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
    * project_curve and so on should be !TimeCurve, not use catch unreachable
      everywhere
* move to zig v0.11 and bump deps
* topology->[]topology projection (for handling inversions)
* time-varying parameters
* time-varying metadata

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
