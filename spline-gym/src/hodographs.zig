//! Zig wrapper of the hodographs c-library.

const libhodographs = @cImport(
    {
        @cInclude("hodographs.h");
    }
);

pub const Vector2 = libhodographs.Vector2;
pub const compute_hodograph = libhodographs.compute_hodograph;
pub const bezier_roots = libhodographs.bezier_roots;
pub const inflection_points = libhodographs.inflection_points;
pub const split_bezier = libhodographs.split_bezier;
pub const evaluate_bezier = libhodographs.evaluate_bezier;
pub const BezierSegment = libhodographs.BezierSegment;

const std = @import("std");

const hodographs = libhodographs;

const opentime = @import("opentime");
const curve = @import("curve");

test "hodograph: simple" 
{
    const allocator = std.testing.allocator;

    const crv = try curve.read_curve_json(
        allocator,
        "curves/upside_down_u.curve.json",
    );
    defer crv.deinit(allocator);

    var cSeg : hodographs.BezierSegment = .{
        .order = 3,
        .p = undefined,
    };
    
    for (crv.segments[0].points(), 0..) 
        |pt, index| 
    {
        cSeg.p[index].x = pt.time;
        cSeg.p[index].y = pt.value;
    }

    if (cSeg.p[0].y == cSeg.p[3].y) 
    {
        cSeg.p[0].y += 0.0001;
    }

    var hodo = hodographs.compute_hodograph(&cSeg);
    const roots = hodographs.bezier_roots(&hodo);

    try std.testing.expectApproxEqAbs(
        0.5,
        roots.x,
        0.00001,
    );
    try std.testing.expectApproxEqAbs(
        roots.y,
        -1,
        0.00001,
    );

    const split_crv = try crv.split_on_critical_points(allocator);
    defer allocator.free(split_crv.segments);

    try std.testing.expectEqual(
        2,
        split_crv.segments.len,
    );
}

test "hodograph: uuuuu" 
{
    const allocator = std.testing.allocator;

    const crv = try curve.read_curve_json(
        "curves/upside_down_u.curve.json",
        allocator,
    );
    defer crv.deinit(allocator);

    var seg_list = std.ArrayList(curve.Segment).init(allocator);
    defer seg_list.deinit();

    const u_count:usize = 5;

    try seg_list.appendNTimes(crv.segments[0], u_count);

    const crv_to_split = curve.TimeCurve{ .segments = seg_list.items };

    const split_crv = try crv_to_split.split_on_critical_points(allocator);
    defer allocator.free(split_crv.segments);

    try std.testing.expectEqual(
        u_count*2,
        split_crv.segments.len,
    );
}

test "hodograph: multisegment curve" 
{
    const allocator = std.testing.allocator;

    {
        const crv = try curve.read_curve_json(
            "curves/linear.curve.json",
            allocator
        );
        defer crv.deinit(allocator);

        try std.testing.expectEqual(
            1,
            crv.segments.len,
        );
        const split_crv = try crv.split_on_critical_points(allocator);
        defer allocator.free(split_crv.segments);

        try std.testing.expectEqual(
            1,
            split_crv.segments.len,
        );
    }

    {
        const crv = try curve.read_curve_json(
            "curves/linear_scurve_u.curve.json",
            allocator,
        );
        defer crv.deinit(allocator);

        try std.testing.expectEqual(
            3,
            crv.segments.len,
        );
        const split_crv = try crv.split_on_critical_points(allocator);
        defer allocator.free(split_crv.segments);

        // 1 segment for the linear, two for the s and 2 for the u
        try std.testing.expectEqual(
            5,
            split_crv.segments.len,
        );
    }
}
