const hodo = @cImport(
    {
        @cInclude("hodographs.h");
    }
);

pub const Vector2 = hodo.Vector2;
pub const compute_hodograph = hodo.compute_hodograph;
pub const bezier_roots = hodo.bezier_roots;
pub const inflection_points = hodo.inflection_points;
pub const split_bezier = hodo.split_bezier;
pub const evaluate_bezier = hodo.evaluate_bezier;
pub const BezierSegment = hodo.BezierSegment;
