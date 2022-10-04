const std = @import("std");
const opentime = @import("opentime");
const util = @import("util.zig");
const EPSILON = @import("util.zig").EPSILON;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs= std.testing.expectApproxEqAbs;

///////////////////////////////////////////////////////////////////////////////
//
// test harness for functionality based on presentation notes
//
///////////////////////////////////////////////////////////////////////////////

test "projection test: linear_through_linear" {
    const first = opentime.TimeTopology.init_linear(
        // slope
        4,
        // bounds
        .{.start_seconds = 0, .end_seconds=30},
    );

    try expectEqual(@as(f32, 0), try first.project_seconds(0));
    try expectApproxEqAbs(@as(f32, 8), try first.project_seconds(2), EPSILON);

    const second = opentime.TimeTopology.init_linear(
        // slope
        2,
        // bounds
        .{.start_seconds = 0, .end_seconds=15},
    );
    try expectEqual(@as(f32, 0), try second.project_seconds(0));
    try expectApproxEqAbs(@as(f32, 4), try second.project_seconds(2), EPSILON);

    // project one through the other
    const second_through_first_topo = first.project_topology(second);
    try expectEqual(@as(f32, 0), try second_through_first_topo.project_seconds(0));
    try expectApproxEqAbs(@as(f32, 16), try second_through_first_topo.project_seconds(2), EPSILON);
}

test "projection test: linear_through_linear with boundary" {
    try util.skip_test();

    const first = opentime.TimeTopology.init_linear(
        // slope
        4,
        // bounds
        .{.start_seconds = 0, .end_seconds=5},
    );

    try expectEqual(@as(f32, 0), try first.project_seconds(0));
    try expectEqual(@as(f32, 8), try first.project_seconds(2));

    // because intervals are right-open, projecting the boundary value is 
    // outside of the boundary condition
    try std.testing.expectError(
        error.ProjectionError,
        first.project_seconds(5)
    );

    const second= opentime.TimeTopology.init_linear(
        // slope
        2,
        // bounds
        .{.start_seconds = 0, .end_seconds=15},
    );
    try expectEqual(@as(f32, 0),  try second.project_seconds(0));
    try expectEqual(@as(f32, 4),  try second.project_seconds(2));

    // not out of bounds for the second topology
    try expectEqual(@as(f32, 10), try second.project_seconds(5));

    // project one through the other
    const second_through_first_topo = first.project_topology(second);
    try expectEqual(@as(f32, 0), try second_through_first_topo.project_seconds(0));
    try expectEqual(@as(f32, 16), try second_through_first_topo.project_seconds(2));

    // ... but after projection, the bounds are smaller
    try std.testing.expectError(
        error.ProjectionError,
        first.project_seconds(5)
    );
}
