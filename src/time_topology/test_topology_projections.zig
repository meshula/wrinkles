//! test harness for functionality based on presentation notes

const std = @import("std");

const opentime = @import("opentime");
const EPSILON = opentime.util.EPSILON;

const time_topology = @import("time_topology.zig");

/// check if a float is nan or not
pub inline fn expectNotNan(
    val: opentime.Ordinate
) !void 
{
    return try std.testing.expect(std.math.isNan(val) == false);
}

test "identity projections" 
{
    const identity_inf = time_topology.TimeTopology.init_identity_infinite();

    const bounds = opentime.ContinuousTimeInterval{
        .start_seconds = 12,
        .end_seconds = 20,
    };
    const identity_bounded = time_topology.TimeTopology.init_affine(
        .{ .bounds = bounds }
    );
    try std.testing.expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds, 
        identity_bounded.project_instantaneous_cc(10),
    );
    try std.testing.expectApproxEqAbs(
        @as(opentime.Ordinate, 13),
        try identity_bounded.project_instantaneous_cc(13),
        EPSILON
    );

    const inf_through_bounded = (
        try identity_bounded.project_topology(
            std.testing.allocator,
            identity_inf,
        )
    );

    // no segments because identity_inf has no segments
    try std.testing.expectEqual(
        inf_through_bounded.affine.bounds,
        bounds
    );
}

test "projection test: linear_through_linear" 
{
    const first = time_topology.TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 4 }, 
            .bounds = .{
                .start_seconds = 0,
                .end_seconds=30
            },
        }
    );

    try std.testing.expectEqual(
        @as(opentime.Ordinate, 0),
        try first.project_instantaneous_cc(0)
    );
    try std.testing.expectApproxEqAbs(
        8,
        try first.project_instantaneous_cc(2),
        EPSILON
    );

    const second = time_topology.TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 2},
            .bounds = .{
                .start_seconds = 0,
                .end_seconds=15
            },
        }
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        try second.project_instantaneous_cc(0)
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 4),
        try second.project_instantaneous_cc(2),
        EPSILON
    );

    // project one through the other
    const second_through_first_topo = (
        try first.project_topology(
            std.testing.allocator,
            second,
        )
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        try second_through_first_topo.project_instantaneous_cc(0)
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 16),
        try second_through_first_topo.project_instantaneous_cc(2),
        EPSILON
    );
}

test "projection test: linear_through_linear with boundary" 
{
    const first = time_topology.TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 4 },
            .bounds = .{
                .start_seconds = 0,
                .end_seconds=5
            },
        }
    );

    try std.testing.expectEqual(0, try first.project_instantaneous_cc(0));
    try std.testing.expectEqual(8, try first.project_instantaneous_cc(2));

    // @TODO: this test reveals the question in the end point projection -
    //        should it be an error or not?
    //
    //        this test did a bound-test as an error.
    //
    // // because intervals are right-open, projecting the boundary value is 
    // // outside of the boundary condition
    // try std.testing.expectError(
    //     error.OutOfBounds,
    //     first.project_instantaneous_cc(5)
    // );
    try std.testing.expectEqual(20, try first.project_instantaneous_cc(5));

    const second= time_topology.TimeTopology.init_affine(
        .{ 
            .transform = .{ .scale = 2},
            .bounds = .{
                .start_seconds = 0,
                .end_seconds=15
            },
        }
    );
    try std.testing.expectEqual(0,  try second.project_instantaneous_cc(0));
    try std.testing.expectEqual(4,  try second.project_instantaneous_cc(2));

    // not out of bounds for the second topology
    try std.testing.expectEqual(10, try second.project_instantaneous_cc(5));

    // project one through the other
    const second_through_first_topo = try first.project_topology(
        std.testing.allocator,
        second
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        try second_through_first_topo.project_instantaneous_cc(0)
    );
    try std.testing.expectEqual(
        @as(f32, 16),
        try second_through_first_topo.project_instantaneous_cc(2)
    );

    // ... but after projection, the bounds are smaller
    try std.testing.expectError(
        error.OutOfBounds,
        second_through_first_topo.project_instantaneous_cc(5)
    );
}
