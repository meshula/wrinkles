//! Curve library for working with two dimensional curves.  Supports
//! `bezier_curve.Bezier` and `linear_curve.Linear` curves, including code
//! paths for building `linear_curve.Linear.Monotonic` curves from other curve
//! types.
//!
//! Includes a number of utility functions for working with curve data.  Built
//! on top of `opentime` data structures.
//!
//! Also includes simple serializers for working with test data on disk.

pub const bezier = @import("bezier_curve.zig");
pub const Bezier = bezier.Bezier;
pub const read_curve_json = bezier.read_curve_json;
pub const read_bezier_curve_data = bezier.read_bezier_curve_data;

pub const linear = @import("linear_curve.zig");
pub const Linear = linear.Linear;
pub const join = linear.join;

const control_point = @import("control_point.zig");
pub const ControlPoint = control_point.ControlPoint;

// Imported so that the hyperlink in the document functions (autodoc).
const opentime = @import("opentime");

test {
    _ = linear;
    _ = bezier;
    _ = control_point;
    _ = @import("test_segment_projection.zig");
    _ = @import("bezier_math.zig");
}
