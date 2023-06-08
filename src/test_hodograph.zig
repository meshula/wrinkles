const std = @import("std");
const hodographs = @cImport(
    {
        @cInclude("hodographs.h");
    }
);

const opentime = @import("opentime");
const curve = opentime.curve;

test "hodograph: simple" {
    const crv = try curve.read_curve_json("curves/upside_down_u.curve.json");

    var cSeg : hodographs.BezierSegment = .{
        .order = 3,
        .p = .{},
    };
    
    for (crv.segments[0].points()) |pt, index| {
        cSeg.p[index].x = pt.time;
        cSeg.p[index].y = pt.value;
    }

    if (cSeg.p[0].y == cSeg.p[3].y) {
        cSeg.p[0].y += 0.0001;
    }

    var hodo = hodographs.compute_hodograph(&cSeg);
    const roots = hodographs.bezier_roots(&hodo);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), roots.x, 0.00001);
    try std.testing.expectApproxEqAbs(roots.y, -1, 0.00001);

    const split_crv = try crv.split_hodograph(std.testing.allocator);
    defer std.testing.allocator.free(split_crv.segments);

    try std.testing.expectEqual(@as(usize, 2), split_crv.segments.len);
}

test "hodograph: uuuuu" {
    const crv = try curve.read_curve_json("curves/upside_down_u.curve.json");

    var seg_list = std.ArrayList(curve.Segment).init(std.testing.allocator);
    defer seg_list.deinit();

    const u_count:usize = 5;

    try seg_list.appendNTimes(crv.segments[0], u_count);

    const crv_to_split = curve.TimeCurve{ .segments = seg_list.items };

    const split_crv = try crv_to_split.split_hodograph(std.testing.allocator);
    defer std.testing.allocator.free(split_crv.segments);

    try std.testing.expectEqual(u_count*2, split_crv.segments.len);
}

test "hodograph: multisegment curve" {
    const crv = try curve.read_curve_json("curves/linear_scurve_u.curve.json");
    try std.testing.expectEqual(@as(usize, 3), crv.segments.len);
    const split_crv = try crv.split_hodograph(std.testing.allocator);
    defer std.testing.allocator.free(split_crv.segments);

    try std.testing.expectEqual(@as(usize, 4), split_crv.segments.len);
}
