const std = @import("std");

const control_point = @import("./control_point.zig");
const ControlPoint = control_point.ControlPoint;
const curve = @import("./bezier_curve.zig");
const expectEqual = std.testing.expectEqual;

/// could build an anytype version of this function if we needed
pub fn lerp_cp(u: f32, a: ControlPoint, b: ControlPoint) ControlPoint {
    return .{
        .time =  a.time  * (1 - u) + b.time  * u,
        .value = a.value * (1 - u) + b.value * u,
    };
}

pub fn lerp(u: f32, a: f32, b: f32) f32 {
    return a  * (1 - u) + b * u;
}

pub fn invlerp(v: f32, a: f32, b: f32) f32 {
    if (b == a)
        return a;
    return (v - a)/(b - a);
}

pub fn value_at_time_between(
    t: f32,
    fst: ControlPoint,
    snd: ControlPoint
) f32 
{
    const u = invlerp(t, fst.time, snd.time);
    return lerp(u, fst.value, snd.value);
}

// @TODO: turn these back on
pub fn segment_reduce4(u: f32, segment: curve.Segment) curve.Segment {
    return .{
        .p0 = lerp_cp(u, segment.p0, segment.p1),
        .p1 = lerp_cp(u, segment.p1, segment.p2),
        .p2 = lerp_cp(u, segment.p2, segment.p3),
    };
}

pub fn segment_reduce3(u: f32, segment: curve.Segment) curve.Segment {
    return .{
        .p0 = lerp_cp(u, segment.p0, segment.p1),
        .p1 = lerp_cp(u, segment.p1, segment.p2),
    };
}

pub fn segment_reduce2(u: f32, segment: curve.Segment) curve.Segment {
    return .{
        .p0 = lerp_cp(u, segment.p0, segment.p1),
    };
}

// evaluate a 1d bezier whose first point is 0.
pub fn _bezier0(unorm: f32, p2: f32, p3: f32, p4: f32) f32
{
    const p1 = 0.0;
    const z = unorm;
    const z2 = z*z;
    const z3 = z2*z;

    const zmo = z-1.0;
    const zmo2 = zmo*zmo;
    const zmo3 = zmo2*zmo;

    return (p4 * z3) 
        - (p3 * (3.0*z2*zmo))
        + (p2 * (3.0*z*zmo2))
        - (p1 * zmo3);
}

//
// Given x in the interval [0, p3], and a monotonically nondecreasing
// 1-D Bezier curve, B(u), with control points (0, p1, p2, p3), find
// u so that B(u) == x.
//

pub fn _findU(x:f32, p1:f32, p2:f32, p3:f32) f32
{
    const MAX_ABS_ERROR = std.math.f32_epsilon * 2.0;
    const MAX_ITERATIONS: u8 = 45;

    if (x <= 0) {
        return 0;
    }

    if (x >= p3) {
        return 1;
    }

    var _u1:f32 = 0;
    var _u2:f32 = 0;
    var x1 = -x; // same as: bezier0 (0, p1, p2, p3) - x;
    var x2 = p3 - x; // same as: bezier0 (1, p1, p2, p3) - x;

    {
        const _u3 = 1.0 - x2 / (x2 - x1);
        const x3 = _bezier0(_u3, p1, p2, p3) - x;

        if (x3 == 0)
            return _u3;

        if (x3 < 0)
        {
            if (1.0 - _u3 <= MAX_ABS_ERROR) {
                if (x2 < -x3)
                    return 1.0;
                return _u3;
            }

            _u1 = 1.0;
            x1 = x2;
        }
        else
        {
            _u1 = 0.0;
            x1 = x1 * x2 / (x2 + x3);

            if (_u3 <= MAX_ABS_ERROR) {
                if (-x1 < x3)
                    return 0.0;
                return _u3;
            }
        }
        _u2 = _u3;
        x2 = x3;
    }

    var i: u8 = MAX_ITERATIONS - 1;

    while (i > 0)
    {
        i -= 1;
        const _u3:f32 = _u2 - x2 * ((_u2 - _u1) / (x2 - x1));
        const x3 = _bezier0 (_u3, p1, p2, p3) - x;

        if (x3 == 0)
            return _u3;

        if (x2 * x3 <= 0)
        {
            _u1 = _u2;
            x1 = x2;
        }
        else
        {
            x1 = x1 * x2 / (x2 + x3);
        }

        _u2 = _u3;
        x2 = x3;

        if (_u2 > _u1)
        {
            if (_u2 - _u1 <= MAX_ABS_ERROR)
                break;
        }
        else
        {
            if (_u1 - _u2 <= MAX_ABS_ERROR)
                break;
        }
    }

    if (x1 < 0)
        x1 = -x1;
    if (x2 < 0)
        x2 = -x2;

    if (x1 < x2)
        return _u1;
    return _u2;
}

//
// Given x in the interval [p0, p3], and a monotonically nondecreasing
// 1-D Bezier curve, B(u), with control points (p0, p1, p2, p3), find
// u so that B(u) == x.
//
pub fn findU(x:f32, p0:f32, p1:f32, p2:f32, p3:f32) f32
{
    return _findU(x - p0, p1 - p0, p2 - p0, p3 - p0);
}


test "lerp_cp" {
    const fst: ControlPoint = .{ .time = 0, .value = 0 };
    const snd: ControlPoint = .{ .time = 1, .value = 1 };

    try expectEqual(@as(f32, 0), lerp_cp(0, fst, snd).value);
    try expectEqual(@as(f32, 0.25), lerp_cp(0.25, fst, snd).value);
    try expectEqual(@as(f32, 0.5), lerp_cp(0.5, fst, snd).value);
    try expectEqual(@as(f32, 0.75), lerp_cp(0.75, fst, snd).value);

    try expectEqual(@as(f32, 0), lerp_cp(0, fst, snd).time);
    try expectEqual(@as(f32, 0.25), lerp_cp(0.25, fst, snd).time);
    try expectEqual(@as(f32, 0.5), lerp_cp(0.5, fst, snd).time);
    try expectEqual(@as(f32, 0.75), lerp_cp(0.75, fst, snd).time);
}

test "findU" {
    try expectEqual(@as(f32, 0), findU(0, 0,1,2,3));
    // out of range values are clamped in u
    try expectEqual(@as(f32, 0), findU(-1, 0,1,2,3));
    try expectEqual(@as(f32, 1), findU(4, 0,1,2,3));
}

fn remap_float(
    val:f32,
    in_min:f32, in_max:f32,
    out_min:f32, out_max:f32,
) f32 {
    return ((val-in_min)/(in_max-in_min) * (out_max-out_min) + out_min);
}

/// return crv normalized into the space provided
pub fn normalized_to(
    crv:curve.TimeCurve,
    min_point:ControlPoint,
    max_point:ControlPoint,
) !curve.TimeCurve 
{

    // return input, curve is empty
    if (crv.segments.len == 0) {
        return crv;
    }

    const extents = crv.extents();
    const crv_min = extents[0];
    const crv_max = extents[1];

    // copy the curve
    var result = crv;

    for (result.segments) |seg, seg_index| {
        var new_points:[4]ControlPoint = .{};
        for (seg.points()) |pt, pt_index| {
            new_points[pt_index] = .{
                .time = remap_float(
                    pt.time,
                    crv_min.time, crv_max.time,
                    min_point.time, max_point.time
                ),
                .value = remap_float(
                    pt.value,
                    crv_min.value, crv_max.value,
                    min_point.value, max_point.value
                ),
            };
        }
        result.segments[seg_index] = curve.Segment.from_pt_array(new_points);
    }

    return crv;
}

test "remap_float" {
    try expectEqual(
        remap_float(0.5, 0.25, 1.25, -4, -5),
        @as(f32, -4.25)
    );
}

test "normalized_to" {
    const input_crv:curve.TimeCurve = .{
        .segments = &.{
            curve.create_bezier_segment(
                .{.time = -500, .value=600},
                .{.time = -300, .value=-100},
                .{.time = 200, .value=300},
                .{.time = 500, .value=700},
            ),
        }
    };

    const min_point = ControlPoint{.time=-100, .value=-300};
    const max_point = ControlPoint{.time=100, .value=-200};

    const result_crv = try normalized_to(input_crv, min_point, max_point);
    const result_extents = result_crv.extents();

    try expectEqual(min_point.time, result_extents[0].time);
    try expectEqual(min_point.value, result_extents[0].value);

    try expectEqual(max_point.time, result_extents[1].time);
    try expectEqual(max_point.value, result_extents[1].value);
}
