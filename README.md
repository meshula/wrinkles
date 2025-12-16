# Wrinkles app - Robust Temporal Math V3 Prototype Project

## Contents

* `treecode`: library for encoding paths through graphs and a `BinaryTree` for
  which uses the treecodes to encode node locations
* `opentime`: low level points, intervals and affine transforms, and
  `Dual` for doing dual arithmetic/implicit differentiation.
* `curve`: structures and functions for making and manipulating linear and
  bezier splines
* `sampling`: tools for dealing with discrete spaces, particularly sets of either
  samples or sample indices.  Includes tools for transforming and resampling
  such arrays.
* `Mapping`: linear, monontonic, composable transformation functions for
  continuous transformation
* `Topology`: monotonic over their input spaces, use sets of Mappings to
  continuously project from an input space to an output space.
* `ProjectionOperator`: pairs a topology with source and destination references
  which can define discrete spaces so that you can project from a discrete
  space to another discrete space with a continuous transformation in the
  middle.
* `OpenTimelineIO`: structures to represent an editorial timeline document and
  construct a `TemporalProjectionBuilder`, An acceleration structure that
  allows quickly building projections from a complex graph.

### Structure:

```
                  `opentime`-.
                     |        \
`treecode`        `sampling`   `curve`
      |              |        /
      |           `Topology`-'
      |              |
      |           `ProjectionOperator`
       \             |
        `---------`TemporalProjectionBuilder`
                     |
                  `OpenTimelineIO`
```

Additionally there are tools for visualizing curves, transformations, and the
temporal hierarchies of editorial documents.

![Screenshot of visualizer app](app.png)

## Sample API

Example code snippet:

```zig
pub fn main(
) !void
{
    const otio_root = try otio.read_from_file(
        allocator,
        path_to_otio_file,
    );
    defer otio_root.deinit(allocator);

    const builder = try otio.TemporalProjectionBuilder.init_from(
        allocator,
        otio_root,
    );
    defer builder.deinit(allocator);

    const root_to_child = try builder.projection_operator_to(
        allocator,
        otio_root.tracks.children[0].space(.media)
    );

    const clip_indices = try root_to_child.project_range_cd(
        allocator,
        .{ .start = 0, .end = 10 },
        .picture,
    );
    defer allocator.free(clip_indices);

    // ...
}
```

## Lessons/Differences to OTIO V1

* clarify that OTIO is modelling a temporally-oriented hierarchy, not a data
  model that necessarily resembles an NLE
    * in other words: Time is the domain that is handled, so model the
                      structure around time
* Transform the data, don't provide a ton of flexibility in the algorithms
  * makes the algorithms simpler and easier to use as templates for
    business-logic specific use cases
  * Magical filter functions were really difficult to implement in a way that
    covered everyone's needs.  Lets try and provide an API that makes it easy
    to write loops closer to the applications rather than in the core.
* use hierarchy rather than "has-a" to clarify temporal relationships
    * in other words, previously effects were on clips, which made it ambiguous
      how to apply their math to the math of the clip
    * Transitions were also weird, in how they reached into neighbor objects.
      Now they're explicitly wrappers around Stacks.
* Use composition rather than inheritance to build objects and interfaces.
* having hierarchy object schemas be runtime definable: juice seems not to have
  been worth the squeeze
* explicitly modelling discrete/continuous means no need for rational time
* implementing in a low level language from the ground up (zig->C) to allow
  flatter higher level language bindings
* The hierarchy is built over a handle object explicitly rather than over the
  instances directly.
* The in-memory model does not intend to 1:1 match the serialized format.
    * The ascii serialized format is a user interface.
    * The binary serialized format is there for performance and size.

### Unsupported/Unimplemented Features From OTIO v1

There are some features that we didn't include in this prototype, because they
didn't impact the deisgn or problems we were specifically solving.

* Multiple media references (left eye/right eye)
* Metadata
* Spatial Coordinate Systems
* Markers
* Schema Versioning

### Omitted from OTIO

* User-defined runtime schemas
* Metadata with arbitrary user defined schemas
* Algorithms for filtering or iterating over all the children of a timeline.

## Ideal Demonstrator Gui App 8/23

* timeline view
* topological graph node view
* curve projection demonstration app
  * pick curves to project from presets
  * edit / drag points
  * see derivatives
  * see projection result

* app that can open an existing .otio file
* visualize the presentation time-space of the top level track
* tlrender++ scrub around the track and see a render of what the composition
  looks like at that frame decorated with coordinates in the media timespaces
  and media sources for each section/clip
* raven/raven++
* topological view -- for a selection of the document, show the topological
  graph of the temporal structural, decorated with the Transformation curves
  * select two nodes to see the projection operator from one to the other

## Serializer

### OTIO v1 

* .otio - json
*   `- can have any kind of object as its top object
* ^
* .otioz 
* .otiod 

### Proposal for v2

```
[]const schema.Timeline
[]const CompositionItemHandle
```

* .ottl + [a, b, z] -- top level of these files is only ever a list of timelines
* .otco + [a, b, z] -- top level is a collection
* suffixes:
    * a: ascii
    * b: binary
    * z: zip bundle

## ZIG REFERENCES

* [Zig Lang](https://github.com/ziglang/zig): The language homepage
* [Zig Learn](https://ziglearn.org/chapter-0/): Good starting place for a language overview
* [Language Reference](https://ziglang.org/documentation/master/): Full Language Reference
* [Stdlib Reference](https://ziglang.org/documentation/master/std/#A;std)
* [Stdlib Source](https://github.com/ziglang/zig/tree/master/lib/std): I hate to admit it but often times its faster to just look at the source of the standard lib rather than going through the docs

## Places for demoing animated parameters on warped scopes

* properties: one time configuration of information (IE, name, temporal
  bounds, media_reference, discrete_info)
* parameters: varying data over some domain (a mapping and an embedding
  domain)

* lens parameters on a clip (ie an animated rack focus or aperture or something)
  * animated focus distance or aperture
* parameter that drives a wipe in a transition
* animating a 2d image space transform 
* a color correct parameter
* state of a gyroscope during capture
* mocap data
    * floats over time

## Why Is This So Complicated

* Editorial Time is Complicated
    * Sometimes Continuous, sometimes discrete
    * Even when its discrete its Complicated
        * different rates/metrics (at the very least, audio vs video)
        * audio rates can be huge, meaning even with not that much wall clock
          time numbers get enormous (ie 192khz - 1 minute of audio is already
          at index 11,520,000, 3.1 hours = max in32)
        * NTSC rates (with a 1001 denominator) mean that mixing rates can be
          difficult to represent with integer rationals
    * Even when its continuous its Complicated
        * Because typically pictures are not resampled, precision is important
        * Audio rates mean that increments can be tiny but still go for large
          ranges
        * when dealing with the media a frame index integer is generally what
          is desired
    * Deformations can be non-linear
        * Bezier curve-based transformations for speed ramps
        * F,M,L type presentations in dailies
        * pulldowns/pullups for going between NTSC and non-NTSC rates
    * Animated parameters are often driven off of time, meaning that time warps
      need to also warp 
* What does OTIO do
    * Uses "RationalTime" - a double value over a double rate.
        * some smarts but used in a handwavvy "both continuous and discrete"
          sort of way
    * Doesn't deal with non-linear transformations
    * Cannot project ranges or points under warp
* What do we propose
    * Join discrete and continuous math via sampling theory

## References

[^1]: [Ordinate Precision Research](https://github.com/ssteinbach/ordinate_precision_research)

## Todo List 11/14/25

* [ ] Transition Schema
    * [x] Add type
    * [ ] Animated parameter for amount [0, 1)
    * [ ] add a boundary to the transition
* [ ] discrete space description
    * [x] Clip specification
    * [ ] description of bounds in either Continuous or Discrete space
* [ ] OTIO 2.0 file format
    * [ ] translator python script
    * [ ] don't need a rational time based format anymore
    * [ ] expressing points/ranges discrete/continuously
    * [ ] describing discrete spaces
    * [ ] Warp Schema: multi segment bezier / pt-tangent form
* [ ] Serializer 
* [ ] visualizer
    * [ ] Normalized view that sorts by track and normalizes output range 0-1
          for each leaf
    * [ ] performance pass
        * [ ] option to only show discrete space under mouse
        * [ ] detect large timelines and default ^ to on for large timelines
    * [ ] UI to represent tracks?
        * [ ] raven-lite. would be nice to confirm the view for the feature
              timeline (feels like there is an offset in there?)
    * [ ] add ALL nodes to the table instead of just terminal spaces
      * [ ] allow controlling visibility from intermediate (non-plotted) scopes
      * [ ] optionally plot intermediate scopes
    * [ ] add visibility controls over the hierarchy
* [ ] code cleanup pass on projection_builder
* [ ] C++ test API
* [ ] Python test API (ziggy-pydust)
* [ ] project_*_cd should return an optional instead of an error?
* [ ] building a projection operator should not require allocation from a
      builder
* [ ] look for tests that are manually comparing interval endpoints and just
      compare the entire (optional) interval
* [x] remove defaults for prescribed initializers 
    * [x] ControlPoint
* [ ] NTSC example
* [ ]  what if not beziers internally but instead b-splines with bezier
        interfaces

## Todo List (10/9/25)

* [x] optimize generating the ProjectionOperatorMap for large otio files
* [x] Can Projection Operator go away?
* [x] Can the Projection Operator map get melded in with Topology, omitting 
      both the Projection Operator and Operator Map?
* [ ] Raven recode against this tooling?
* [ ] serialize OTIO Files for round tripping?
* [ ] schema updater app?

## Todo List (11/6/24)

* [x] add build variable for debug messages
* [x] prune existing debug messages out
* [x] clean up how graphviz is found
* [x] decompose opentimelineio.zig into a library w/ multiple modules
* [x] boil time out of opentime (hm might need to rename this library) —
    * [x] particularly ContinuousTimeInterval->ContinuousInterval
    * [x] opentime
* [x] and the rest of the library (notably sampling.zig)
    * [x] sampling
    * [x] ripple out into the c library too
* [x] fold DiscreteDatasourceIndexGenerator into Sampling
    * [x] -> SignalIndexGenerator
    * [x] add more functionality to the DiscreteDatasourceIndexGenerator so that
    * [x] build out into the otio layer too
* [x] rename “time_topology” build unit to “topology”
* [x] `PhaseOrdinate` (or some other means of accurately handling integers over
  rates changing)
    * [x] confirm that this is really better than an `f64` or `f128`
    * ... it isn't, see: [https://github.com/ssteinbach/ordinate_precision_research](https://github.com/ssteinbach/ordinate_precision_research)
* [ ] 0.5 offset todo in sampling
* [ ] thread the "domain" idea out to the discrete spaces, so you can
      define on the timeline a discrete info per domain (ie 24 for picture
      48000 for sound)
* [ ] handle non-integer rates (ie 1000/1001 rates) in the sample rate
* [ ] review the high level tests and make sure they’re covering all the stuff
  in the slides
    * [ ] factor out the code that builds the timelines into a couple
          prototypical timelines, then the tests can operate on those structures
          and make the tests a bit more readable/direct
* [ ] write the slide examples in C
* [ ] handle/test cases where projection results in multiple solutions (maybe
  because inversion creates multiple concurrent topologies?)
* [ ] add a catmull-rom basis function
* [ ] zbez library specific for bezier?
     * [ ] remove the two point/three point approximations and simplify the
           curve library
     * [ ] export bezier code into a zbez library that can be freestanding
* [ ] finish parameterizing the sampling library on type, like the curve
  library
     * ie index_at_time -> output_index_at_input_ordinate
     * [ ] handle acyclical sampling as well (variable bitrate data, held
           frames, etc).?
* [ ] do a scan to make sure that `opentime.Ordinate` is used in place of f32
  directly
* [ ] integrate inside of raven

