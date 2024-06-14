const std = @import("std");
const TimeTopology = @import("time_topology.zig").TimeTopology;
const opentime = @import("opentime");
const util = opentime.util;
const EPSILON = util.EPSILON;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs= std.testing.expectApproxEqAbs;
const expectError = @import("std").testing.expectError;

pub fn expectNotNan(val: f32) !void {
    return try expect(std.math.isNan(val) == false);
}

///////////////////////////////////////////////////////////////////////////////
//
// test harness for functionality based on presentation notes
//
///////////////////////////////////////////////////////////////////////////////

test "identity projections" {
    const identity_inf = TimeTopology.init_identity_infinite();

    const bounds = opentime.ContinuousTimeInterval{
        .start_seconds = 12,
        .end_seconds = 20,
    };
    const identity_bounded = TimeTopology.init_affine(.{ .bounds = bounds });
    try expectError(
        TimeTopology.ProjectionError.OutOfBounds, 
        identity_bounded.project_ordinate(10),
    );
    try expectApproxEqAbs(
        @as(f32, 13),
        try identity_bounded.project_ordinate(13),
        EPSILON
    );

    const inf_through_bounded = try identity_bounded.project_topology(identity_inf);

    // no segments because identity_inf has no segments

    try expectEqual(inf_through_bounded.affine.bounds, bounds);
}

test "projection test: linear_through_linear" {
    const first = TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 4 }, 
            .bounds = .{.start_seconds = 0, .end_seconds=30},
        }
    );

    try expectEqual(@as(f32, 0), try first.project_ordinate(0));
    try expectApproxEqAbs(@as(f32, 8), try first.project_ordinate(2), EPSILON);

    const second = TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 2},
            .bounds = .{.start_seconds = 0, .end_seconds=15},
        }
    );
    try expectEqual(@as(f32, 0), try second.project_ordinate(0));
    try expectApproxEqAbs(@as(f32, 4), try second.project_ordinate(2), EPSILON);

    // project one through the other
    const second_through_first_topo = try first.project_topology(second);
    try expectEqual(
        @as(f32, 0),
        try second_through_first_topo.project_ordinate(0)
    );
    try expectApproxEqAbs(
        @as(f32, 16),
        try second_through_first_topo.project_ordinate(2),
        EPSILON
    );
}

test "projection test: linear_through_linear with boundary" {
    try util.skip_test();

    const first = TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 4 },
            .bounds = .{.start_seconds = 0, .end_seconds=5},
        }
    );

    try expectEqual(@as(f32, 0), try first.project_ordinate(0));
    try expectEqual(@as(f32, 8), try first.project_ordinate(2));

    // because intervals are right-open, projecting the boundary value is 
    // outside of the boundary condition
    try std.testing.expectError(
        error.ProjectionError,
        first.project_ordinate(5)
    );

    const second= TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 2},
            .bounds = .{.start_seconds = 0, .end_seconds=15},
        }
    );
    try expectEqual(@as(f32, 0),  try second.project_ordinate(0));
    try expectEqual(@as(f32, 4),  try second.project_ordinate(2));

    // not out of bounds for the second topology
    try expectEqual(@as(f32, 10), try second.project_ordinate(5));

    // project one through the other
    const second_through_first_topo = try first.project_topology(second);
    try expectEqual(@as(f32, 0), try second_through_first_topo.project_ordinate(0));
    try expectEqual(@as(f32, 16), try second_through_first_topo.project_ordinate(2));

    // ... but after projection, the bounds are smaller
    try std.testing.expectError(
        error.ProjectionError,
        first.project_ordinate(5)
    );
}
