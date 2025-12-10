//! Documentation for the Wrinkles project.
//!
//! The wrinkles project is a ground-up reimplementation/proposal for how to
//! introduce a rigorous temporal modelling (from first principles) to
//! OpenTimelineIO ([http://opentimeline.io](http://opentimeline.io)).
//!
//! Libraries:
//!
//! * `opentimelineio`: Main facing user library for wrinkles.
//! * `opentime`: Math library for basic temporal mathematical constructs -
//!               ordinates, intervals, etc.
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
