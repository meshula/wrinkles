const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

const curve = @import("./curve.zig");

///////////////////////////////////////////////////////////////////////////////
// this file is for testing specifically the curve projection, building up to
// topology projection
//
// should probably be in the curve.zig file
///////////////////////////////////////////////////////////////////////////////

// setting up approximate testing -- this is the smallest epsilon such that 
// tests pass
const EPSILON : f32 = 0.000001;
fn expectApproxEql(
    expected: anytype,
    actual: @TypeOf(expected)
) !void 
{
    return expectApproxEqAbs(
        expected,
        actual,
        EPSILON,
    );
}

fn expectNotEqual(
    expected: anytype,
    actual: @TypeOf(expected),
) !void 
{
    std.testing.expect(expected != actual) catch {
        std.debug.print(
            "expected not equal values, both are: {}\n",
            .{expected},
        );
        return error.TestExpectedNotEqual; 
    };
}

test "curve projection tests: identity projection" {
    // note that intervals are identical
    var identity_tc = try curve.TimeCurve.init_from_start_end(
        std.testing.allocator,
        .{ .time = 0, .value = 0 },
        .{ .time = 10, .value = 10 },
    );
    defer identity_tc.deinit(std.testing.allocator);

    const double_tc = try curve.TimeCurve.init_from_start_end(
        std.testing.allocator,
        .{ .time = 0, .value = 0 },
        .{ .time = 1, .value = 2 },
    );
    defer double_tc.deinit(std.testing.allocator);

    const results = try identity_tc.project_curve_guts(
        double_tc,
        std.testing.allocator,
    );
    defer results.deinit();

    // both are already linear, should result in a single segment
    try expectEqual(1, results.result.?.segments.len);

    const result = results.result.?.segments[0];

    try expectEqual(
        double_tc.extents()[0].time,
        result.extents()[0].time,
    );
    try expectEqual(
        double_tc.extents()[1].time,
        result.extents()[1].time,
    );

    for (result.points())
        |pt|
    {
        try expectApproxEqAbs(
            pt.value,
            result.eval_at_input(pt.time),
            EPSILON,
        );
    }
}

test "Segment:  identity projection" {
    // note that intervals are identical
    var identity_s = curve.Segment.init_from_start_end(
        .{ .time = 0, .value = 0 },
        .{ .time = 10, .value = 10 },
    );
    const double_s = curve.Segment.init_from_start_end(
        .{ .time = 0, .value = 0 },
        .{ .time = 1, .value = 2 },
    );

    // both are already linear, should result in a single segment
    const result = identity_s.project_segment(double_s);

    try expectEqual(double_s.p0, result.p0);
    try expectApproxEql(double_s.p1.value, result.p1.value);
    try expectApproxEql(double_s.p2.value, result.p2.value);
    try expectApproxEql(double_s.p3.value, result.p3.value);
}

test "projection tests: linear projection" {
    const m: f32 = 4;

    // note that intervals are identical
    var quad_s = curve.Segment.init_from_start_end(
        .{ .time = 0, .value = 0 },
        .{ .time = 1, .value = m },
    );
    var double_s = curve.Segment.init_from_start_end(
        .{ .time = 0, .value = 0 },
        .{ .time = 0.5, .value = 1 },
    );

    var result = quad_s.project_segment(double_s);

    try expectEqual(m*double_s.p0.value, result.p0.value);
    try expectApproxEql(m*double_s.p1.value, result.p1.value);
    try expectApproxEql(m*double_s.p2.value, result.p2.value);
    try expectApproxEql(m*double_s.p3.value, result.p3.value);

    try expectEqual(    m*(double_s.eval_at(0).value),   (result.eval_at(0).value));
    try expectApproxEql(m*(double_s.eval_at(0.25).value),(result.eval_at(0.25).value));
    try expectApproxEql(m*(double_s.eval_at(0.5).value), (result.eval_at(0.5).value));
    try expectApproxEql(m*(double_s.eval_at(0.75).value),(result.eval_at(0.75).value));
}

test "projection tests: bezier projected through linear" {
    const m: f32 = 2;

    var double_s = curve.Segment.init_from_start_end(
        .{ .time = 0, .value = 0 },
        .{ .time = 1, .value = m },
    );

    // upside down u shaped curve
    var bezier_s = curve.Segment{
        .p0 = .{ .time = 0, .value = 0 },
        .p1 = .{ .time = 0, .value = 1 },
        .p2 = .{ .time = 1, .value = 1 },
        .p3 = .{ .time = 1, .value = 0 },
    };

    var result = double_s.project_segment(bezier_s);

    try expectEqual(m*bezier_s.eval_at(0   ).value, result.eval_at(0   ).value);

    try expectEqual(m*bezier_s.eval_at(0.25).value, result.eval_at(0.25).value);
    try expectEqual(m*bezier_s.eval_at(0.5 ).value, result.eval_at(0.5 ).value);
    try expectEqual(m*bezier_s.eval_at(0.75).value, result.eval_at(0.75).value);
}

test "projection tests: bezier projected through linear 2" {
    // This test demonstrates that _just_ projecting the bezier control points
    // isn't enough to projet the curve itself through another curve.
    //
    // Because the control points of the U are on the beginning and end of the
    // interval, and the displacement from the linear curve are in the middle,
    // the alterations to the shape are't visible if _just_ the control points
    // are projected.

    const off: f32 = 0.2;

    // pushing the middle control points up and down to make a slight S curve
    var scurve_s = curve.Segment{
        .p0 = .{ .time = 0, .value = 0},
        .p1 = .{ .time = 1.0/3.0, .value = 1.0/3.0 - off },
        .p2 = .{ .time = 2.0/3.0, .value = 2.0/3.0 + off },
        .p3 = .{ .time = 1, .value = 1},
    };

    // upside down u shaped curve
    var ushape_s = curve.Segment{
        .p0 = .{ .time = 0, .value = 0 },
        .p1 = .{ .time = 0, .value = 1 },
        .p2 = .{ .time = 1, .value = 1 },
        .p3 = .{ .time = 1, .value = 0 },
    };

    var result = scurve_s.project_segment(ushape_s);

    // the boundaries should still be the same
    try expectEqual(ushape_s.eval_at(0).value, result.eval_at(0).value);

    // ...but midpoints shoulld be different
    // try expectNotEqual(curve._eval_bezier(0.25, ushape_s), curve._eval_bezier(0.25, result));
    // try expectNotEqual(curve._eval_bezier(0.5,  ushape_s), curve._eval_bezier(0.5,  result));
    // try expectNotEqual(curve._eval_bezier(0.75, ushape_s), curve._eval_bezier(0.75, result));
}
