//! Documentation for the Wrinkles project.
//!
//! The wrinkles project is a ground-up reimplementation/proposal which
//! introduces a rigorous temporal modeling (from first principles) to
//! OpenTimelineIO ([http://opentimeline.io](http://opentimeline.io)).
//!
//! Libraries:
//!
//! * `opentimelineio`: User facing user library for wrinkles.  Includes schema
//!                     for modelling timeline document objects (Clips, Tracks,
//!                     Media, etc) as well as tools for [de]serializing and an
//!                     interface for doing transformations and math within its
//!                     temporal structure (see
//!                     `opentimelineio.TemporalProjectionBuilder`).
//! * `opentime`: Math library for basic temporal mathematical constructs -
//!               `opentime.Ordinate`, `opentime.ContinuousInterval`,
//!               `opentime.AffineTransform1D`, as well as the
//!               `opentime.Dual_Ord` for implicit differentiation.
//!
//! Internal components:
//!
//! * `treecode`: Library for encoding paths through graphs and a `BinaryTree` 
//!               for which uses the treecodes to encode node locations.
//! * `curve`: Structures and functions for making and manipulating linear and
//!            bezier splines.
//! * `sampling`: Tools for dealing with discrete spaces, particularly sets of 
//!               either samples or sample indices.  Includes tools for
//!               transforming and resampling such arrays.
//! * `topology`:
//!     * `topology.Mapping`: Linear, monontonic, composable transformation
//!                           functions for continuous transformation.
//!     * `topology.Topology`: Monotonic over their input spaces, use sets of
//!                            Mappings to continuously project from an input
//!                            space to an output space.

pub const opentimelineio = @import("opentimelineio");

pub const opentime = @import("opentime");

/// Continuous-to-discrete transformation and discrete math
pub const sampling = @import("sampling");

/// String wrapper for the library
pub const string = @import("string_stuff");

/// Topology - foundation for transformations
pub const topology = @import("topology");

/// Library for dealing with bezier and linear curves.
pub const curve = @import("curve");

pub const treecode = @import("treecode");
