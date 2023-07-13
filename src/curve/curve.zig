pub const bezier_math = @import("bezier_math.zig");
pub const linear_curve = @import("linear_curve.zig");
pub const control_point = @import("control_point.zig");

// bezier
pub const TimeCurve = bezier_curve.TimeCurve;
pub const Segment = bezier_curve.Segment;

pub const TimeCurveLinear = linear_curve.TimeCurveLinear;

pub const ControlPoint = control_point.ControlPoint;
pub const create_linear_segment = bezier_curve.create_linear_segment;
pub const create_identity_segment = bezier_curve.create_identity_segment;
pub const linearize_segment = bezier_curve.linearize_segment;
pub const read_segment_json = bezier_curve.read_segment_json;
pub const read_curve_json = bezier_curve.read_curve_json;
pub const write_json_file_curve = bezier_curve.write_json_file_curve;
pub const normalized_to = bezier_math.normalized_to;
pub const inverted = bezier_math.inverted_bezier;
pub const inverted_linear = bezier_math.inverted_linear;
pub const rescaled_curve = bezier_math.rescaled_curve;
pub const affine_project_curve = bezier_curve.affine_project_curve;

pub const bezier_curve = @import("bezier_curve.zig");

test "all curve" {
    _ = bezier_math;
    _ = linear_curve;
    _ = bezier_curve;
}
