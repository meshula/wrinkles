# Wrinkles app

## Todo

### Path System

* support arbitrary path lengths
    * use an array list of u128 to encode arbitrarily long paths

### Clean up the Topology Math

- Add in holodrome types and checking.  Holodromes can help with linearization,
  since critical points could be expensive for the algorithm to find otherwise.
  They definitely help with inversion.  I think we should just model them
  directly under the hood as an optimization

- Right now the topology has bounds, transform and curves.  This is
  inconsistent because the curves _inside_ the topology also represent a
  transformation, and implicitly define bounds (in that they're finite lists of
  segments, which are bounded).  The math reflects this - the way that
  transform and boundary are applied is pretty inconsistent.

- Part of the reason why this is the case is that there are several special
  cases of topology in play:
    - infinite identity (could have a transform but no bounds)
    - finite segments (do they have bounds?)
    - empty

Two options:
* do what we did for the graph and define a set of operators that bundle up a
  topology and work through the cases, providing clean constructors for those
  useful special types
* break these features up into things that the topology can contain and
  localize the math, push the matrix into handling combinations of those child
  types

### Inversion

* need to add inversion functions to the topologies
* add error when a function isn't trivially invertible
* if we do something with the mappings, when things aren't trivially
  invertible, we still know how to invert them and how the mapping functions.
  Can we exploit this? Or is the juice not worth the squeeze for this project

### Sampling Tools

* need tools for defining and transforming sets of samples

### Additional OTIO nodes

* Stacks
* Timeline
* Gap (fully)
* TimeEffect
* Transitions

* how hard would parsing OTIO JSON be?  Would be cool to read in real
  timeilines and do transformations there

### Optimization and Caching

* MxN track related time stuff - the map should cache those kinds of intermediates
* Can the map also cache optimizations like linearizing curves?


