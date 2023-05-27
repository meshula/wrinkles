const std = @import("std");
const hodographs = @cImport(
    {
        @cInclude("hodographs.h");
    }
);

const opentime = @import("opentime");
const curve = opentime.curve;

test "simple_hodo" {
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
}
