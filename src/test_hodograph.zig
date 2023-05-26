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

    std.debug.print("\n\ncSeg: {}\n\n", .{ cSeg });

    // var hodo = hodographs.compute_hodograph(&cSeg);
    @breakpoint();
    const roots = hodographs.bezier_roots(&cSeg);

    std.debug.print("\n\nroots: {}\n\n", .{ roots });

    try std.testing.expectApproxEqAbs(roots.x, 0.5, 0.00001);
    try std.testing.expectApproxEqAbs(roots.y, -1, 0.00001);
}
