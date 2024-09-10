pub const bezier_math = @import("bezier_math.zig");
pub const linear_curve = @import("linear_curve.zig");
pub const control_point = @import("control_point.zig");
pub const bezier_curve = @import("bezier_curve.zig");
pub const test_segment_projection = @import("test_segment_projection.zig");

pub const Bezier = bezier_curve.Bezier;
pub const Linear = linear_curve.Linear;
pub const ControlPoint = control_point.ControlPoint;

pub const linearize_segment = bezier_curve.linearize_segment;
pub const read_segment_json = bezier_curve.read_segment_json;
pub const read_curve_json = bezier_curve.read_curve_json;
pub const read_bezier_curve_data = bezier_curve.read_bezier_curve_data;
pub const read_linear_curve_data = bezier_curve.read_linear_curve_data;
pub const write_json_file_curve = bezier_curve.write_json_file_curve;
pub const normalized_to = bezier_math.normalized_to;
pub const inverted = bezier_math.inverted_bezier;
pub const inverted_linear = bezier_math.inverted_linear;
pub const rescaled_curve = bezier_math.rescaled_curve;
pub const affine_project_curve = bezier_curve.affine_project_curve;

test {
    _ = bezier_math;
    _ = linear_curve;
    _ = bezier_curve;
    _ = control_point;
    _ = test_segment_projection;
}
