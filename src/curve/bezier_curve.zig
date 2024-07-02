const std = @import("std");
const debug_panic = @import("std").debug.panic;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const expect = std.testing.expect;

// const opentime = @import("opentime");
const opentime = @import("opentime");
const ContinuousTimeInterval = opentime.ContinuousTimeInterval;

const bezier_math = @import("bezier_math.zig");
const generic_curve = @import("generic_curve.zig");
const linear_curve = @import("linear_curve.zig");
const control_point = @import("control_point.zig");

const string_stuff = @import("string_stuff");
const latin_s8 = string_stuff.latin_s8;

const dual = opentime.dual;

// hodographs c-library
pub const hodographs = @import("spline_gym");

pub var u_val_of_midpoint:f32 = 0.5;
pub var fudge:f32 = 1;

/// options for projecting bezier through bezier
pub const ProjectionAlgorithms = enum (i32) {
    /// project endpoints, midpoint + midpoint derviatives, run decastlejau in
    /// reverse (so called three-point-approximation) to infer P1, P2
    three_point_approx=0,
    /// project each endpoint, chain rule derivatives, then use derivative length
    /// to estimate P1, P2
    two_point_approx,
    /// linearize both curves, then project linear segments
    linearized,
};

/// the projection algorithm to use when projecting Bezier through Bezier
pub var project_algo = ProjectionAlgorithms.linearized;

/// wrapper that bakes in the epsilon to expectApproxEql
fn expectApproxEql(
    expected: anytype,
    actual: @TypeOf(expected)
) !void 
{
    return std.testing.expectApproxEqAbs(
        expected,
        actual,
        generic_curve.EPSILON
    );
}

/// returns true if val is between fst and snd regardless of whether fst or snd
/// is greater
fn _is_between(
    val: f32,
    fst: f32,
    snd: f32
) bool 
{
    return (
           (fst < val - generic_curve.EPSILON and val < snd - generic_curve.EPSILON) 
        or (fst > val + generic_curve.EPSILON and val > snd + generic_curve.EPSILON)
    );
}

// Time curves are functions mapping a time to a value.
// Time curves are a sequence of right met 2d Bezier curve segments
// closed on the left and open on the right.
// If the first formal segment does not start at -inf, there is an
// implicit interval spanning -inf to the first formal segment.
// If there final formal segment does not end at +inf, there is an
// implicit interval spanning the last point in the final formal
// segment to +inf.
//
// It is a formal requirement that an application supply control
// points that satistfy the rules of a function, in other words,
// a Time Curve cannot contain a 2d Bezier curve segment that has
// a cusp or a loop.
//
// We name the parameterization of the time coordinate system t,
// and we name the parameterization of the Bezier curves u.
// The parameter t can be any legal timeline value, u must be
// within the closed interval of [0,1].
//
// The value of a Bezier at u is B(u). The value of a time curve at
// t is T(t). If M(x) maps t into u, then the evaluation of B(t) is
// B(M(C(t))).
// 

// A Time Curve with a single segment spanning t1 to t2
// therefore looks like this:
//
// -inf ------[---------)------- inf+
//            t1        t2               time parameterization
//            p0 p1 p2 p3                curve parameterization
//

// Each Bezier curve in a TimeCurve is a Bezier segment with
// four control points. Here we name the components of the
// control point ordinates time and value, and these axes
// correspond to the time metric the TimeCurve is embedded in.
// Note that when the Bezier curve is evaluated, the Bezier
// parameterization u will be used to evaluate the function
// nto the time metric space.

// Note that continuity between segments is not dictated by
// the TimeCurve class. Interested applications should make
// their own data structure that records continuity data, and
// are responsible for constraining the control points to 
// satisfy those continuity constraints. In the future, this
// library may provide helper functions that aid in the
// computation of common constraints, such as colinear
// tangents on end points, and so on.

/// compute the linear distance between two points
pub fn distance(
    from: control_point.ControlPoint,
    to: control_point.ControlPoint
) f32 
{
    const dist = to.sub(from);

    return std.math.sqrt((dist.time*dist.time) + (dist.value*dist.value));
}

test "distance: 345 triangle" 
{
    try expectEqual(
        @as(f32, 5),
        distance(
            .{ .time = 3, .value = -3 },
            .{ .time = 6, .value = 1 }
        )
    );
}

/// @TODO: time should be an ordinate

/// Bezier Curve Segment
pub const Segment = struct {
    // time coordinate of each control point is expressed in the coordinate
    // system of the embedding space, ie a clip's intrinsic space.
    p0: control_point.ControlPoint = .{
        .time = 0,
        .value = 0,
    },
    p1: control_point.ControlPoint = .{
        .time = 0,
        .value = 0,
    },
    p2: control_point.ControlPoint = .{
        .time = 1,
        .value = 1,
    },
    p3: control_point.ControlPoint = .{
        .time = 1,
        .value = 1,
    },

    pub fn init_identity(
        start_time: f32,
        end_time: f32
    ) Segment
    {
        return Segment.init_from_start_end(
            .{ .time = start_time, .value = start_time },
            .{ .time = end_time, .value = end_time }
        );
    }

    pub fn init_from_start_end(
        start: control_point.ControlPoint,
        end: control_point.ControlPoint
    ) Segment 
    {
        if (end.time >= start.time) 
        {
            return .{
                .p0 = start,
                .p1 = bezier_math.lerp(1.0/3.0, start, end),
                .p2 = bezier_math.lerp(2.0/3.0, start, end),
                .p3 = end,
            };
        }

        debug_panic(
            "Create linear segment failed, t0: {d} > t1: {d}\n",
            .{start.time, end.time}
        );
    }

    pub fn init_approximate_from_three_points(
        start_knot: control_point.ControlPoint,
        mid_point: control_point.ControlPoint,
        t_mid_point: f32,
        d_mid_point_dt: control_point.ControlPoint,
        end_knot: control_point.ControlPoint,
    ) ?Segment
    {
        const result = three_point_guts_plot(
            start_knot,
            mid_point,
            t_mid_point,
            d_mid_point_dt,
            end_knot
        );

        return result.result;
    }

    /// construct a static array of the points
    pub fn points(
        self: @This()
    ) [4]control_point.ControlPoint 
    {
        return .{ self.p0, self.p1, self.p2, self.p3 };
    }

    /// construct an array of pointers to the points in this segment
    pub fn point_ptrs(
        self: *@This()
    ) [4]*control_point.ControlPoint 
    {
        return .{ &self.p0, &self.p1, &self.p2, &self.p3 };
    }

    /// copy pts over values in self
    pub fn from_pt_array(
        pts: [4]control_point.ControlPoint
    ) Segment 
    {
        return .{ 
            .p0 = pts[0],
            .p1 = pts[1],
            .p2 = pts[2],
            .p3 = pts[3], 
        };
    }

    pub fn set_points(
        self: *@This(),
        pts: [4]control_point.ControlPoint
    ) void 
    {
        self.p0 = pts[0];
        self.p1 = pts[1];
        self.p2 = pts[2];
        self.p3 = pts[3];
    }

    pub fn eval_at_dual(
        self: @This(),
        unorm_dual:dual.Dual_f32,
    ) control_point.Dual_CP
    {
        var self_dual : [4]control_point.Dual_CP = undefined;
        const self_p = self.points();

        inline for (self_p, &self_dual) 
                   |p, *dual_p| 
        {
            dual_p.r = p;
            dual_p.i = .{};
        }

        const seg3 = bezier_math.segment_reduce4_dual(unorm_dual, self_dual);
        const seg2 = bezier_math.segment_reduce3_dual(unorm_dual, seg3);
        const result = bezier_math.segment_reduce2_dual(unorm_dual, seg2);

        return result[0];
    }

    /// evaluate the segment at parameter unorm, [0, 1)
    pub fn eval_at(
        self: @This(),
        unorm:f32
    ) control_point.ControlPoint
    {
        const use_reducer = true;
        if (use_reducer) {
            const seg3 = bezier_math.segment_reduce4(unorm, self);
            const seg2 = bezier_math.segment_reduce3(unorm, seg3);
            const result = bezier_math.segment_reduce2(unorm, seg2);
            return result.p0;
        }
        else {
            const z = unorm;
            const z2 = z*z;
            const z3 = z2*z;

            const zmo = z-1.0;
            const zmo2 = zmo*zmo;
            const zmo3 = zmo2*zmo;

            const p1: control_point.ControlPoint = self.p0;
            const p2: control_point.ControlPoint = self.p1;
            const p3: control_point.ControlPoint = self.p2;
            const p4: control_point.ControlPoint = self.p3;

            // "p4 * z3 - p3 * z2 * zmo + p2 * 3 * z * zmo2 - (p1 * zmo3)"
            const l_p4: control_point.ControlPoint = (
                (p4.mul(z3)).sub(p3.mul(3.0*z2*zmo)).add(p2.mul(3.0*z*zmo2)).sub(p1.mul(zmo3))
            );

            return l_p4;
        }

    }

    /// returns whether t overlaps the domain of this segment or not
    pub fn overlaps_time(
        self:@This(),
        t:f32
    ) bool 
    {
        return (self.p0.time <= t and self.p3.time > t);
    }

    /// return the segment split at u [0, 1.0)
    /// note: u of < 0 or >= 1 will result in a null result, no split
    pub fn split_at(
        self: @This(),
        unorm:f32
    ) ?[2]Segment 
    {
        if (unorm < generic_curve.EPSILON or unorm >= 1)
        {
            return null;
        }

        const p = self.points();

        const Q0 = self.p0;
        const Q1 = bezier_math.lerp(unorm, p[0], p[1]);
        const Q2 = bezier_math.lerp(
            unorm,
            Q1,
            bezier_math.lerp(unorm, p[1], p[2])
        );
        const Q3 = bezier_math.lerp(
            unorm,
            Q2,
            bezier_math.lerp(
                unorm,
                bezier_math.lerp(unorm, p[1], p[2]),
                bezier_math.lerp(unorm, p[2], p[3])
            )
        );

        const R0 = Q3;
        const R2 = bezier_math.lerp(unorm, p[2], p[3]);
        const R1 = bezier_math.lerp(
            unorm,
            bezier_math.lerp(unorm, p[1], p[2]), 
            R2,
        );
        const R3 = p[3];

        return .{
            Segment{ 
                .p0 = Q0,
                .p1 = Q1,
                .p2 = Q2,
                .p3 = Q3
            },
            Segment{
                .p0 = R0,
                .p1 = R1,
                .p2 = R2,
                .p3 = R3
            },
        };
    }

    pub fn extents_time(
        self: @This()
    ) opentime.ContinuousTimeInterval
    {
        return .{
            .start_seconds = self.p0.time,
            .end_seconds = self.p3.time,
        };
    }

    /// compute the extents of the segment
    pub fn extents(
        self: @This()
    ) [2]control_point.ControlPoint 
    {
        var min: control_point.ControlPoint = self.p0;
        var max: control_point.ControlPoint = self.p0;

        inline for ([3][]const u8{"p1", "p2", "p3"}) 
            |field| 
        {
            const pt = @field(self, field);
            min = .{
                .time = @min(min.time, pt.time),
                .value = @min(min.value, pt.value),
            };
            max = .{
                .time = @max(max.time, pt.time),
                .value = @max(max.value, pt.value),
            };
        }

        return .{ min, max };
    }

    /// checks if segment can project through this one
    pub fn can_project(
        self: @This(),
        segment_to_project: Segment,
    ) bool 
    {
        const my_extents = self.extents();
        const other_extents = segment_to_project.extents();

        return (
            other_extents[0].value >= my_extents[0].time - generic_curve.EPSILON
            and other_extents[1].value < my_extents[1].time + generic_curve.EPSILON
        );
    }

    /// assuming that segment_to_project is contained by self, project the 
    /// points of segment_to_project through self
    pub fn project_segment(
        self: @This(),
        segment_to_project: Segment,
    ) Segment
    {
        var result: Segment = undefined;

        inline for ([4][]const u8{"p0", "p1", "p2", "p3"}) 
                   |field| 
       {
           const pt = @field(segment_to_project, field);
           @field(result, field) = .{
               .time = pt.time,
               .value = self.eval_at_input(pt.value),
           };
       }

        return result;
    }

    /// @TODO: this function only works if the value is increasing over the 
    ///        segment.  The monotonicity and increasing -ness of a segment
    ///        is guaranteed for time, but not for the value coordinate.
    pub fn findU_value(
        self:@This(),
        tgt_value: f32
    ) f32 
    {
        return bezier_math.findU(
            tgt_value,
            self.p0.value,
            self.p1.value,
            self.p2.value,
            self.p3.value,
        );
    }

    pub fn findU_value_dual(
        self:@This(),
        tgt_value: f32
    ) dual.Dual_f32 
    {
        return bezier_math.findU_dual(
            tgt_value,
            self.p0.value,
            self.p1.value,
            self.p2.value,
            self.p3.value,
        );
    }

    pub fn findU_input(
        self:@This(),
        input_ordinate: f32
    ) f32 
    {
        return bezier_math.findU(
            input_ordinate,
            self.p0.time,
            self.p1.time,
            self.p2.time,
            self.p3.time,
        );
    }

    pub fn findU_input_dual(
        self:@This(),
        input_ordinate: f32
    ) dual.Dual_f32 
    {
        return bezier_math.findU_dual(
            input_ordinate,
            self.p0.time,
            self.p1.time,
            self.p2.time,
            self.p3.time,
        );
    }

    /// returns the y-value for the given x-value
    pub fn eval_at_input(
        self: @This(),
        x:f32
    ) f32 
    {
        const u:f32 = bezier_math.findU(
            x,
            self.p0.time,
            self.p1.time,
            self.p2.time,
            self.p3.time
        );
        return self.eval_at(u).value;
    }

    pub fn eval_at_input_dual(
        self: @This(),
        x:f32
    ) control_point.Dual_CP 
    {
        const u = bezier_math.findU_dual(
            x,
            self.p0.time,
            self.p1.time,
            self.p2.time,
            self.p3.time
        );
        return self.eval_at_dual(u);
    }

    pub fn debug_json_str(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const u8 
    {
        return try std.fmt.allocPrint(
            allocator,
            \\
            \\{{
            \\    "p0": {{ "time": {d:.6}, "value": {d:.6} }},
            \\    "p1": {{ "time": {d:.6}, "value": {d:.6} }},
            \\    "p2": {{ "time": {d:.6}, "value": {d:.6} }},
            \\    "p3": {{ "time": {d:.6}, "value": {d:.6} }}
            \\}}
            \\
            ,
            .{
                self.p0.time, self.p0.value,
                self.p1.time, self.p1.value,
                self.p2.time, self.p2.value,
                self.p3.time, self.p3.value,
            }
        );
    }

    pub fn debug_print_json(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !void 
    {
        std.debug.print("\ndebug_print_json] p0: {}\n", .{ self.p0});

        const blob = try self.debug_json_str(allocator);
        defer allocator.free(blob);

        std.debug.print("{s}", .{ blob });
    }

    /// convert into the c library hodographs struct
    pub fn to_cSeg(
        self: @This()
    ) hodographs.BezierSegment 
    {
        return .{ 
            .order = 3,
            .p = translate: {
                var tmp : [4] hodographs.Vector2 = undefined;

                inline for (&.{ self.p0, self.p1, self.p2, self.p3 }, 0..) 
                           |pt, pt_ind| 
                {
                    tmp[pt_ind] = .{ .x = pt.time, .y = pt.value };
                }

                break :translate tmp;
            },
        };
    }
};

test "Segment: can_project test" 
{
    const half = Segment.init_from_start_end(
        .{ .time = -0.5, .value = -0.25, },
        .{ .time = 0.5, .value = 0.25, },
    );
    const double = Segment.init_from_start_end(
        .{ .time = -0.5, .value = -1, },
        .{ .time = 0.5, .value = 1, },
    );

    try expectEqual(true, double.can_project(half));
    try expectEqual(false, half.can_project(double));
}

test "Segment: debug_str test" 
{
    const seg = Segment.init_from_start_end(
        .{.time = -0.5, .value = -0.5},
        .{.time =  0.5, .value = 0.5},
    );

    const result: []const u8=
        \\
        \\{
        \\    "p0": { "time": -0.500000, "value": -0.500000 },
        \\    "p1": { "time": -0.166667, "value": -0.166667 },
        \\    "p2": { "time": 0.166667, "value": 0.166667 },
        \\    "p3": { "time": 0.500000, "value": 0.500000 }
        \\}
        \\
            ;

        const blob = try seg.debug_json_str(std.testing.allocator);
        defer std.testing.allocator.free(blob);

        try expectEqualStrings( result,blob);
}

fn _is_approximately_linear(
    segment: Segment,
    tolerance: f32
) bool 
{
    const u = (
        (segment.p1.mul(3.0)).sub(segment.p0.mul(2.0)).sub(segment.p3)
    );
    var ux = u.time * u.time;
    var uy = u.value * u.value;

    const v = (
        (segment.p2.mul(3.0)).sub(segment.p3.mul(2.0)).sub(segment.p0)
    );
    const vx = v.time * v.time;
    const vy = v.value * v.value;

    if (ux < vx) {
        ux = vx;
    }
    if (uy < vy) {
        uy = vy;
    }

    return (ux+uy <= tolerance);

}

/// Based on this paper:
/// https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.86.162&rep=rep1&type=pdf
/// return a list of segments that approximate the segment with the given tolerance
///
/// ASSUMES THAT ALL POINTS ARE FINITE
pub fn linearize_segment(
    allocator: std.mem.Allocator,
    segment: Segment,
    tolerance:f32,
) ![]control_point.ControlPoint
{
    // @TODO: this function should compute and preserve the derivatives on the
    //        bezier segments
    var result: std.ArrayList(control_point.ControlPoint) = (
        std.ArrayList(control_point.ControlPoint).init(allocator)
    );

    if (_is_approximately_linear(segment, tolerance)) {
        // terminal condition
        try result.append(segment.p0);
        try result.append(segment.p3);
    } else {
        // recursion
        const subsegments = (
            segment.split_at(0.5) orelse return error.NoSplitForLinearization
        );

        {
            const l_result = try linearize_segment(
                allocator,
                subsegments[0],
                tolerance
            );
            defer allocator.free(l_result);
            try result.appendSlice(l_result);
        }

        {
            const r_result = try linearize_segment(
                allocator,
                subsegments[1],
                tolerance
            );
            defer allocator.free(r_result);
            try result.appendSlice(r_result[1..]);
        }
    }

    return result.toOwnedSlice();
}

test "segment: linearize basic test" 
{
    const segment = try read_segment_json(
        std.testing.allocator,
        "segments/upside_down_u.json"
    );

    {
        const linearized_knots = try linearize_segment(
            std.testing.allocator,
            segment,
            0.01
        );
        defer std.testing.allocator.free(linearized_knots);
        try expectEqual(@as(usize, 8+1), linearized_knots.len);
    }

    {
        const linearized_knots = try linearize_segment(
            std.testing.allocator,
            segment,
            0.000001
        );
        defer std.testing.allocator.free(linearized_knots);
        try expectEqual(@as(usize, 68+1), linearized_knots.len);
    }

    {
        const linearized_knots = try linearize_segment(
            std.testing.allocator,
            segment,
            0.00000001
        );
        defer std.testing.allocator.free(linearized_knots);
        try expectEqual(@as(usize, 256+1), linearized_knots.len);
    }
}

test "segment from point array" 
{
    const original_knots_ident: [4]control_point.ControlPoint = .{
        .{ .time = -0.5,     .value = -0.5},
        .{ .time = -0.16666, .value = -0.16666},
        .{ .time = 0.166666, .value = 0.16666},
        .{ .time = 0.5,      .value = 0.5}
    };
    const ident = Segment.from_pt_array(original_knots_ident);

    try expectApproxEql(@as(f32, 0), ident.eval_at(0.5).value);

    const linearized_ident_knots = try linearize_segment(
        std.testing.allocator,
        ident,
        0.01
    );
    defer std.testing.allocator.free(linearized_ident_knots);
    try expectEqual(@as(usize, 2), linearized_ident_knots.len);

    try expectApproxEql(
        original_knots_ident[0].time,
        linearized_ident_knots[0].time
    );
    try expectApproxEql(
        original_knots_ident[0].value,
        linearized_ident_knots[0].value
    );

    try expectApproxEql(
        original_knots_ident[3].time,
        linearized_ident_knots[1].time
    );
    try expectApproxEql(
        original_knots_ident[3].value,
        linearized_ident_knots[1].value
    );
}

test "segment: linearize already linearized curve" 
{
    const segment = try read_segment_json(
        std.testing.allocator,
        "segments/linear.json"
    );
    const linearized_knots = try linearize_segment(
        std.testing.allocator,
        segment,
        0.01
    );
    defer std.testing.allocator.free(linearized_knots);

    // already linear!
    try expectEqual(@as(usize, 2), linearized_knots.len);
}

/// read a Bezier segment from a json file on disk
pub fn read_segment_json(
    allocator:std.mem.Allocator,
    file_path: latin_s8,
) !Segment 
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32)
    );
    defer allocator.free(source);

    const result = try std.json.parseFromSlice(
        Segment,
        allocator,
        source,
        .{}
    );
    defer result.deinit();

    return result.value;
}

test "segment: eval_at_input and findU test over linear curve" 
{
    const seg = Segment.init_from_start_end(
        .{.time = 2, .value = 2},
        .{.time = 3, .value = 3},
    );

    inline for ([_]f32{2.1, 2.2, 2.3, 2.5, 2.7}) 
               |coord| 
    {
        try expectApproxEql(coord, seg.eval_at_input(coord));
    }
}

test "segment: dual_eval_at over linear curve" 
{
    // identity curve
    {
        const seg = Segment.init_identity(0, 1);

        inline for ([_]f32{0.2, 0.4, 0.5, 0.98}) 
            |coord| 
        {
            const result = seg.eval_at_dual(.{ .r = coord, .i = 1});
            errdefer std.log.err(
                "coord: {any}, result: {any}\n",
                .{ coord, result }
            );
            try expectApproxEql(coord, result.r.time);
            try expectApproxEql(coord, result.r.value);
            try expectApproxEql(@as(f32, 1), result.i.time);
            try expectApproxEql(@as(f32, 1), result.i.value);
        }
    }

    // curve with slope 2
    {
        const seg = Segment.init_from_start_end(
            .{ .time = 0, .value = 0 },
            .{ .time = 1, .value = 2 },
        );

        inline for ([_]f32{0.2, 0.4, 0.5, 0.98}) 
            |coord| 
        {
            const result = seg.eval_at_dual(.{ .r = coord, .i = 1 });
            errdefer std.log.err(
                "coord: {any}, result: {any}\n",
                .{ coord, result }
            );
            try expectApproxEql(coord, result.r.time);
            try expectApproxEql(coord * 2, result.r.value);
            try expectApproxEql(@as(f32, 1), result.i.time);
            try expectApproxEql(@as(f32, 2), result.i.value);
        }
    }
}

test "Segment.init_identity check cubic spline" 
{
    // ensure that points are along line even for linear case
    const seg = Segment.init_identity(0, 1);

    try expectEqual(@as(f32, 0), seg.p0.time);
    try expectEqual(@as(f32, 0), seg.p0.value);
    try expectEqual(@as(f32, 1.0/3.0), seg.p1.time);
    try expectEqual(@as(f32, 1.0/3.0), seg.p1.value);
    try expectEqual(@as(f32, 2.0/3.0), seg.p2.time);
    try expectEqual(@as(f32, 2.0/3.0), seg.p2.value);
    try expectEqual(@as(f32, 1), seg.p3.time);
    try expectEqual(@as(f32, 1), seg.p3.value);
}

pub fn create_bezier_segment(
    p0: control_point.ControlPoint,
    p1: control_point.ControlPoint,
    p2: control_point.ControlPoint,
    p3: control_point.ControlPoint
) Segment {
    if (p3.time >= p2.time and p2.time >= p1.time and p1.time >= p0.time) {
        return .{
            .p0 = p0,
            .p1 = p1,
            .p2 = p2,
            .p3 = p3,
        };
    }

    debug_panic(
        "Create bezier segment failed, {}, {}, {}, {}\n",
        .{p0.time, p1.time, p2.time, p3.time}
    );
}

/// TimeCurve maps an input time to an output time.
///
/// The TimeCurve is a sequence of 2d cubic bezier segments,
/// closed at the start, and open at the end, where each
/// segment is met by the previous one.
///
/// The evaluation of a TimeCurve (S0, S1, ... Sn) at t, is
/// therefore t if t < S0.p0.time or t >= S0.p3.time. Otherwise,
/// the segment S whose interval [S.p0.time, S.p3.time) contains t
/// is evaluated according to the cubic Bezier equations.
///
/// @TODO: we would like to break this down by curve parameterization
///             - CubicBezierCurve1d/CubicBezierSegment1d (current implementation)
///                 - can be linearized into a LinearBezierCurve1d
///                 - can be projected _through_ but not itself projected
///                   without linearization
///             - LinearBezierCurve1d/LinearBezierSegment1d
///                 - optimization, but also invertible and projectible!
///             - IdentityCurve1d
///                 - defined over the entire continuum, or within given bounds
///                 - convienent for interval->timecurve
///             - NullCurve1d
///                 - out of bounds everywhere
///                 - so that topologies can have "holes"
///            IdentityCurve1d and NullCurve1d
///            ... but it isn't urgent, I think this can wait
///
///            ... there are other procedural curves that we may want to encode:
///            - mono hermite
///            - step function
///
pub const TimeCurve = struct {
    // according to the evaluation specification, an empty
    // timecurve evaluates t as t, everywhere.
    segments: []Segment = &.{},

    /// dupe the segments argument into the returned object
    pub fn init(
        allocator:std.mem.Allocator,
        segments: []const Segment,
    ) !TimeCurve 
    {
        return TimeCurve{ 
            .segments = try allocator.dupe(
                Segment,
                segments
            ) 
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.segments);
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator
    ) !TimeCurve
    {
        return .{ 
            .segments = try allocator.dupe(
                Segment,
                self.segments
            ),
        };
    }

    pub fn init_from_start_end(
        allocator: std.mem.Allocator,
        p0: control_point.ControlPoint,
        p1: control_point.ControlPoint,
    ) !TimeCurve 
    {
        return try TimeCurve.init(
            allocator,
            &.{ Segment.init_from_start_end(p0, p1) }
        );
    }

    /// convert a linear curve into a bezier one
    pub fn init_from_linear_curve(
        allocator:std.mem.Allocator,
        crv: linear_curve.TimeCurveLinear,
    ) !TimeCurve 
    {
        var result = std.ArrayList(Segment).init(allocator);
        result.deinit();

        const knots = crv.knots.len;

        for (crv.knots[0..knots-1], crv.knots[1..]) 
            |knot, next_knot| 
        {
            try result.append(Segment.init_from_start_end(knot, next_knot));
        }

        return TimeCurve{ .segments = try result.toOwnedSlice() };
    }

    /// evaluate the curve at time t in the space of the curve
    pub fn evaluate(
        self: @This(),
        t_arg: f32
    ) error{OutOfBounds}!f32 
    {
        if (self.find_segment(t_arg)) 
           |seg|
        {
            return seg.eval_at_input(t_arg);
        }

        // no segment found
        return error.OutOfBounds;
    }

    pub fn find_segment_index(self: @This(), t_arg: f32) ?usize {
        if (
            self.segments.len == 0 
            or t_arg < self.segments[0].p0.time - generic_curve.EPSILON
            or t_arg >= self.segments[self.segments.len - 1].p3.time - generic_curve.EPSILON
        )
        {
            return null;
        }

        // quick check if it is exactly the start time of the first segment
        if (t_arg < self.segments[0].p0.time + generic_curve.EPSILON) {
            return 0;
        }

        for (self.segments, 0..) 
            |seg, index| 
        {
            if (
                seg.p0.time <= t_arg + generic_curve.EPSILON 
                and t_arg < seg.p3.time - generic_curve.EPSILON
            ) 
            {
                // exactly in a segment
                return index;
            }
        }

        // between segments, identity
        return null;
    }

    pub fn find_segment(self: @This(), t_arg: f32) ?*Segment {
        if (self.find_segment_index(t_arg)) 
           |ind|
        {
            return &self.segments[ind];
        }

        return null;
    }

    /// build a linearized version of this TimeCurve
    pub fn linearized(
        self: @This(),
        allocator:std.mem.Allocator,
    ) !linear_curve.TimeCurveLinear 
    {
        var linearized_knots = std.ArrayList(
            control_point.ControlPoint
        ).init(allocator);

        const self_split_on_critical_points = (
            try self.split_on_critical_points(
                allocator
            )
        );
        defer self_split_on_critical_points.deinit(allocator);

        var start_knot:usize = 0;

        for (self_split_on_critical_points.segments, 0..) 
            |seg, seg_ind| 
            {
                if (seg_ind > 0) {
                    start_knot = 1;
                }

                const subseg = try linearize_segment(
                    allocator,
                    seg,
                    0.000001
                );
                defer allocator.free(subseg);

                // @TODO: expose the tolerance as a parameter(?)
                try linearized_knots.appendSlice(
                    // first knot of all interior segments should match the 
                    // last knot of the previous segment, so can be skipped
                    subseg[start_knot..]
                );
            }

        return .{
            .knots = try linearized_knots.toOwnedSlice()
        };
    }

    /// project another curve through this one.  A curve maps 'time' to 'value'
    /// parameters.  if curve self is v_self(t_self), and curve other is 
    /// v_other(t_other) and other is being projected through self, the result
    /// function is v_self(v_other(t_other)).  This maps the the v_other value
    /// to the t_self parameter.
    ///
    /// curve self:
    /// 
    /// v_self
    /// |  /
    /// | /
    /// |/
    /// +--- t_self
    ///
    /// curve other:
    ///   
    ///  v_other
    /// |      ,-'
    /// |   ,-'
    /// |,-'
    /// +---------- t_other
    ///
    /// @TODO finish this doc
    ///
    pub fn project_curve(
        self: @This(),
        allocator: std.mem.Allocator,
        other: TimeCurve
        // should be []TimeCurve <-  come back to this later
    ) !TimeCurve 
    {
        const result = try project_curve_guts(
            self,
            other,
            allocator
        );
        defer result.deinit();

        if (result.result)
            |crv|
        {
            return try crv.clone(allocator);
        }

        return error.NoProjectionResult;
    }

    const ProjectCurveGuts = struct {
        result : ?TimeCurve = null,
        self_split: ?TimeCurve = null,
        other_split: ?TimeCurve = null,
        to_project : ?TimeCurve = null,
        tpa: ?[]tpa_result = null,
        segments_to_project_through: ?[]usize = null,
        allocator: std.mem.Allocator,
        midpoint_derivatives: ?[]control_point.ControlPoint = null,
        f_prime_of_g_of_t: ?[]control_point.ControlPoint = null,
        g_prime_of_t: ?[]control_point.ControlPoint = null,

        pub fn deinit(
            self: @This()
        ) void 
        {
            if (self.result) 
               |sp| 
            {
                sp.deinit(self.allocator);
            }

            if (self.self_split) 
               |sp| 
            {
                sp.deinit(self.allocator);
            }

            if (self.other_split) 
                |sp| 
            {
                sp.deinit(self.allocator);
            }

            if (self.to_project) 
                |tp| 
            {
                tp.deinit(self.allocator);
            }

            const things_to_free = &.{
                "tpa",
                "segments_to_project_through",
                "midpoint_derivatives",
                "f_prime_of_g_of_t",
                "g_prime_of_t"
            };

            inline for (things_to_free) 
                       |t| 
            {
                if (@field(self, t)) 
                    |thing| 
                {
                    self.allocator.free(thing);
                }
            }
        }
    };

    /// implementation of the bezier/bezier projection, including extra
    /// instrumentation ("guts") for debugging/visualization purposes
    pub fn project_curve_guts(
        self: @This(),
        other: TimeCurve,
        allocator: std.mem.Allocator,
        // should be []TimeCurve <-  come back to this later
    ) !ProjectCurveGuts 
    {
        var result = ProjectCurveGuts{.allocator = allocator};

        var self_split = try self.split_on_critical_points(
            allocator
        );
        defer self_split.deinit(allocator);

        var other_split = try other.split_on_critical_points(
            allocator
        );
        defer other_split.deinit(allocator);

        const self_bounds = self.extents();

        // @TODO: skip segments in self that are BEFORE other and skip segments
        //        in self that are AFTER other

        {
            var split_points = std.ArrayList(f32).init(allocator);
            defer split_points.deinit();

            // self split
            {
                // find all knots in self that are within the other bounds
                const endpoints = try other_split.segment_endpoints(
                    allocator
                );
                defer allocator.free(endpoints);

                for (endpoints)
                    |other_knot| 
                {
                    if (
                        _is_between(
                            other_knot.value,
                            self_bounds[0].time,
                            self_bounds[1].time
                        )
                        // @TODO: omit cases where either endpoint is within an
                        //        epsilon of an endpoint
                    ) {
                        try split_points.append(other_knot.value);
                    }
                }
                const old_ptr = self_split.segments;
                defer allocator.free(old_ptr);

                self_split = (
                    try self_split.split_at_each_input_ordinate(
                        split_points.items,
                        allocator
                    )
                );
            }

            result.self_split = try self_split.clone(allocator);

            // other split
            {
                const other_bounds = other.extents();

                split_points.clearAndFree();

                // find all knots in self that are within the other bounds
                const endpoints = try self_split.segment_endpoints(
                    allocator
                );
                defer allocator.free(endpoints);

                for (endpoints)
                    |self_knot| 
                {
                    if (
                        _is_between(
                            self_knot.time,
                            other_bounds[0].value,
                            other_bounds[1].value
                        )
                    ) {
                        try split_points.append(self_knot.time);
                    }
                }
                const old_ptr = other_split.segments;
                defer allocator.free(old_ptr);

                other_split = (
                    try other_split.split_at_each_output_ordinate(
                        split_points.items,
                        allocator
                    )
                );
            }
        }

        result.other_split = try other_split.clone(allocator);

        var curves_to_project = std.ArrayList(TimeCurve).init(allocator);
        defer curves_to_project.deinit();

        var last_index: i32 = -10;
        var current_curve = std.ArrayList(Segment).init(allocator);
        defer current_curve.deinit();

        // @breakpoint();

        // having split both curves by both endpoints, throw out the segments in
        // other that will not be projected
        for (other_split.segments, 0..) 
            |other_segment, index| 
        {
            const other_seg_ext = other_segment.extents();

            if (
                (other_seg_ext[0].value < self_bounds[1].time - generic_curve.EPSILON)
                and (other_seg_ext[1].value > self_bounds[0].time + generic_curve.EPSILON)
            )
            {
                if (index != last_index+1) 
                {
                    // curves of less than one point are trimmed, because they
                    // have no duration, and therefore are not modelled in our
                    // system.
                    if (current_curve.items.len > 1) 
                    {
                        try curves_to_project.append(
                            TimeCurve{
                                .segments = try current_curve.toOwnedSlice()
                            }
                        );
                    }
                    current_curve.clearAndFree();
                }

                try current_curve.append(other_segment);
                last_index = @intCast(index);
            }
        }
        if (current_curve.items.len > 0) 
        {
            try curves_to_project.append(
                TimeCurve{
                    .segments = try current_curve.toOwnedSlice()
                }
            );
        }
        current_curve.deinit();

        if (curves_to_project.items.len == 0) 
        {
            result.result = TimeCurve{};
            return result;
        }
        result.to_project = .{ 
            .segments = try allocator.alloc(
                Segment,
                curves_to_project.items[0].segments.len
            ),
        };
        std.mem.copyForwards(
            Segment,
            result.to_project.?.segments,
            curves_to_project.items[0].segments
        );

        var guts = std.ArrayList(tpa_result).init(allocator);
        var segments_to_project_through = std.ArrayList(usize).init(allocator);
        var midpoint_derivatives = std.ArrayList(
            control_point.ControlPoint
        ).init(allocator);
        var cache_f_prime_of_g_of_t = std.ArrayList(
            control_point.ControlPoint
        ).init(allocator);
        var cache_g_prime_of_t = std.ArrayList(
            control_point.ControlPoint
        ).init(allocator);

        // do the projection
        for (curves_to_project.items) 
            |*crv| 
        {
            for (crv.segments)
                |*segment|
            {
                const self_seg = self_split.find_segment(segment.p0.time) orelse {
                    continue;
                };
                try segments_to_project_through.append(
                    self_split.find_segment_index(segment.p0.time) orelse continue
                );

                switch (project_algo) {
                    .three_point_approx => {
                        // @TODO: question 1- should this be halfway across the input
                        //                    space (vs 0.5 across the parameter space)
                        // review - want the point on the curve furthest from the line
                        //          from A to C (in tpa terms)
                        //          see "aligning a curve" on pomax to compute the
                        //          extremity
                        const t_midpoint_other = u_val_of_midpoint;
                        const midpoint = segment.eval_at(t_midpoint_other);

                        var projected_pts = [_]control_point.ControlPoint{
                            segment.p0,
                            midpoint,
                            segment.p3, 
                        };

                        // explicitly project start, mid, and end
                        inline for (&projected_pts, 0..) 
                            |pt, pt_ind|
                        {
                            projected_pts[pt_ind] = .{
                                .time  = pt.time,
                                .value = self_seg.eval_at_input(pt.value)
                            };
                        }

                        // chain rule: h'(x) = f'(g(x)) * g'(x)
                        // chain rule: h'(t) = f'(g(t)) * g'(t)
                        // g(t) == midpoint (other @ t = 0.5)
                        // f'(g(t)) == f'(midpoint -- other @ t = 0.5)
                        // g'(t) == hodograph of other @ t = 0.5
                        // h'(t) = f'(midpoint) * hodograph of other @ t= 0.5
                        const u_in_self = self_seg.findU_input(
                            midpoint.value
                        );
                        const d_mid_point_dt = chain_rule: 
                        {
                            var self_cSeg = self_seg.to_cSeg();
                            var self_hodo = hodographs.compute_hodograph(&self_cSeg);
                            const f_prime_of_g_of_t = hodographs.evaluate_bezier(
                                &self_hodo,
                                u_in_self,
                            );
                            try cache_f_prime_of_g_of_t.append(
                                .{
                                    .time = f_prime_of_g_of_t.x, 
                                    .value= f_prime_of_g_of_t.y
                                }
                            );

                            // project derivative by the chain rule
                            var other_cSeg = segment.to_cSeg();
                            var other_hodo = hodographs.compute_hodograph(&other_cSeg);
                            const g_prime_of_t = hodographs.evaluate_bezier(
                                &other_hodo,
                                t_midpoint_other,
                            );
                            try cache_g_prime_of_t.append(
                                .{
                                    .time = g_prime_of_t.x, 
                                    .value= g_prime_of_t.y
                                }
                            );

                            if (true) {
                                break :chain_rule control_point.ControlPoint{
                                    .time  = f_prime_of_g_of_t.x * g_prime_of_t.x,
                                    .value = f_prime_of_g_of_t.y * g_prime_of_t.y,
                                };
                            } else {
                                break :chain_rule control_point.ControlPoint{
                                    .time  = g_prime_of_t.x,
                                    .value = f_prime_of_g_of_t.y * g_prime_of_t.y,
                                };
                            }
                        };

                        try midpoint_derivatives.append(d_mid_point_dt);

                        const m_ratio = (u_in_self * t_midpoint_other) / ((1-u_in_self)*(1-t_midpoint_other));
                        const projected_t = m_ratio / (m_ratio + 1);

                        const final = three_point_guts_plot(
                            projected_pts[0],
                            projected_pts[1],
                            projected_t, // <- should be u_in_projected_curve
                            d_mid_point_dt.mul(fudge),
                            projected_pts[2],
                        );

                        try guts.append(final);

                        segment.p0 = projected_pts[0];
                        segment.p1 = final.C1.?;
                        segment.p2 = final.C2.?;
                        segment.p3 = projected_pts[2];
                    },
                    .two_point_approx => {

                        // project p0, p3 and their derivaties
                        // p1 and p2 are derived by using the derivatives at p0
                        // and p3

                        var projected_pts = [_]control_point.ControlPoint{
                            segment.p0,
                            segment.p3, 
                        };
                        var projected_derivatives: [2]control_point.ControlPoint = undefined;

                        inline for (&projected_pts, 0..) 
                            |*pt, pt_ind|
                        {
                            const projection_dual = self_seg.eval_at_input_dual(
                                pt.value
                            );

                            // project the point
                            pt.* = .{
                                .time  = pt.time,
                                .value = projection_dual.r.value,
                            };
                            projected_derivatives[pt_ind] = projection_dual.i;
                        }

                        segment.p0 = projected_pts[0];
                        segment.p1 = projected_pts[0].add(
                            projected_derivatives[0].div(3)
                        );
                        segment.p2 = projected_pts[1].sub(
                            projected_derivatives[1].div(3)
                        );
                        segment.p3 = projected_pts[1];

                        try guts.append(
                            .{ 
                                .start = projected_pts[0],
                                .start_ddt = projected_derivatives[0].mul(fudge),
                                .end = projected_pts[1],
                                .end_ddt = projected_derivatives[1].mul(fudge),
                            }
                        );
                    },
                    else => {}
                }
            }
        }

        result.tpa = try guts.toOwnedSlice();
        result.segments_to_project_through = try segments_to_project_through.toOwnedSlice();
        result.midpoint_derivatives = try midpoint_derivatives.toOwnedSlice();
        result.f_prime_of_g_of_t = try cache_f_prime_of_g_of_t.toOwnedSlice();
        result.g_prime_of_t = try cache_g_prime_of_t.toOwnedSlice();

        result.result = curves_to_project.items[0];

        return result;
    }

    /// compute an array of all the segment endpoints
    pub fn segment_endpoints(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]control_point.ControlPoint 
    {
        var result = std.ArrayList(
            control_point.ControlPoint
        ).init(allocator);

        if (self.segments.len == 0) {
            return &[0]control_point.ControlPoint{};
        }

        try result.append(self.segments[0].p0);
        for (self.segments) 
            |seg| 
        {
            try result.append(seg.p3);
        }

        return try result.toOwnedSlice();
    }

    /// project a linear curve through this curve (by linearizing self)
    pub fn project_linear_curve(
        self: @This(),
        allocator: std.mem.Allocator,
        other: linear_curve.TimeCurveLinear,
        // should return []TimeCurve
    ) ![]linear_curve.TimeCurveLinear
    {
        const self_linearized = try self.linearized(
            allocator
        );
        defer self_linearized.deinit(allocator);

        return try self_linearized.project_curve(
            allocator,
            other,
        );
    }

    /// project an affine transformation through the curve
    pub fn project_affine(
        self: @This(),
        aff: opentime.transform.AffineTransform1D,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        const result_segments = try allocator.dupe(
            Segment,
            self.segments
        );

        for (result_segments) 
            |*seg| 
        {
            for (seg.point_ptrs()) 
                |pt |
            {
                pt.time = aff.applied_to_seconds(pt.time);
            }
        }

        return .{ .segments = result_segments };
    }

    /// build a string serialization of the curve
    pub fn debug_json_str(
        self:@This(),
        allocator: std.mem.Allocator
    ) ![]const u8
    {
        var str = std.ArrayList(u8).init(allocator);

        try std.json.stringify(self, .{}, str.writer()); 
        return str.toOwnedSlice();
    }

    /// return the extents of the curve's input spact /v
    pub fn extents_time(
        self:@This()
    ) ContinuousTimeInterval 
    {
        return .{
            .start_seconds = self.segments[0].p0.time,
            .end_seconds = self.segments[self.segments.len - 1].p3.time,
        };
    }

    /// return the extents of the curve's output space
    pub fn extents_value(
        self:@This()
    ) ContinuousTimeInterval 
    {
        const result = self.extents();
        return .{
            .start_seconds = result[0].value,
            .end_seconds = result[1].value,
        };
    }

    /// return the extents of the curve as control points
    pub fn extents(
        self:@This()
    ) [2]control_point.ControlPoint 
    {
        var min = self.segments[0].p0;
        var max = self.segments[0].p3;

        for (self.segments) 
            |seg| 
        {
            const seg_extents = seg.extents();
            min = .{
                .time = @min(min.time, seg_extents[0].time),
                .value = @min(min.value, seg_extents[0].value),
            };
            max = .{
                .time = @max(min.time, seg_extents[1].time),
                .value = @max(min.value, seg_extents[1].value),
            };
        }
        return .{ min, max };
    }

    /// returns a copy of self which is split in the segment which overlaps
    /// the ordinate at the ordinate in the input space.
    ///
    /// Example:
    /// Curve has three segments [0, 3)[0, 10)[0, 4)
    /// ordinate: 5
    ///
    /// result:
    /// [0, 3)[0, 5)[5, 10)[0, 4)
    ///
    /// note: if the ordinate causes no split (IE is on an endpoint), the
    ///       return will a strict copy of self.
    pub fn split_at_input_ordinate(
        self:@This(),
        ordinate:f32,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        const seg_to_split_index = self.find_segment_index(ordinate) orelse {
            return error.OutOfBounds;
        };

        const seg_to_split = self.segments[seg_to_split_index];

        const unorm = seg_to_split.findU_input(ordinate);

        if (
            unorm < generic_curve.EPSILON 
            or generic_curve.EPSILON > @abs(1 - unorm) 
        ) {
            return .{ 
                .segments = try allocator.dupe(
                    Segment,
                    self.segments
                ) 
            };
        }

        const maybe_split_segments = seg_to_split.split_at(unorm);

        if (maybe_split_segments == null) 
        {
            std.log.err(
                "ordinate: {} unorm: {} seg_to_split: {s}\n",
                .{ ordinate, unorm, try seg_to_split.debug_json_str(allocator) }
            );
            return error.OutOfBounds;
        }
        const split_segments = maybe_split_segments.?;


        var new_segments = try allocator.alloc(Segment, self.segments.len + 1);

        const before_split_src = self.segments[0..seg_to_split_index];
        const after_split_src = self.segments[seg_to_split_index+1..];

        const before_split_dest = new_segments[0..seg_to_split_index];
        const after_split_dest = new_segments[seg_to_split_index+2..];

        std.mem.copyForwards(Segment, before_split_dest, before_split_src);
        new_segments[seg_to_split_index] = split_segments[0];
        new_segments[seg_to_split_index+1] = split_segments[1];
        std.mem.copyForwards(Segment, after_split_dest, after_split_src);

        return .{ .segments = new_segments };
    }

    /// returns a copy of self which is split in the segment which overlaps
    /// the ordinate at the ordinate in the input space.
    ///
    /// Example:
    /// Curve has three segments [0, 3)[0, 10)[0, 4)
    /// ordinates: {5, 15}
    ///
    /// result:
    /// [0, 3)[0, 5)[5, 10)[0,2)[2, 4)
    pub fn split_at_each_output_ordinate(
        self:@This(),
        ordinates:[]const f32,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        var result_segments = std.ArrayList(
            Segment
        ).init(allocator);
        defer result_segments.deinit();
        try result_segments.appendSlice(self.segments);

        var current_segment_index:usize = 0;

        while (current_segment_index < result_segments.items.len) 
            : (current_segment_index += 1) 
        {
            for (ordinates)
                |ordinate|
            {
                const seg = result_segments.items[current_segment_index];
                const ext = seg.extents();

                if (
                    _is_between(
                        ordinate,
                        ext[0].value,
                        ext[1].value
                    )
                ) 
                {
                    const u = seg.findU_value(ordinate);

                    // if it isn't an end point
                    if (u > 0 + 0.000001 and u < 1 - 0.000001) {
                        const maybe_split_segments = seg.split_at(u);

                        if (maybe_split_segments) 
                            |split_segments| 
                        {
                            try result_segments.insertSlice(
                                current_segment_index,
                                &split_segments
                            );
                            _ = result_segments.orderedRemove(
                                current_segment_index + split_segments.len
                            );
                        }
                        continue;
                    }
                }
            }
        }

        return .{ 
            .segments = try result_segments.toOwnedSlice() 
        };
    }

    pub fn split_at_each_input_ordinate(
        self:@This(),
        ordinates:[]const f32,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        var result_segments = std.ArrayList(
            Segment
        ).init(allocator);
        defer result_segments.deinit();

        try result_segments.appendSlice(self.segments);

        var current_segment_index:usize = 0;

        while (current_segment_index < result_segments.items.len) 
            : (current_segment_index += 1) 
        {
            for (ordinates)
                |ordinate|
            {
                const seg = result_segments.items[current_segment_index];
                const ext = seg.extents();

                if (
                    _is_between(
                        ordinate,
                        ext[0].time,
                        ext[1].time
                    )
                ) 
                {
                    const u = seg.findU_input(ordinate);

                    // if it isn't an end point
                    if (u > 0 + 0.000001 and u < 1 - 0.000001) {
                        var split_segments = seg.split_at(u) orelse {
                            continue;
                        };

                        try result_segments.insertSlice(
                            current_segment_index,
                            &split_segments
                        );
                        _ = result_segments.orderedRemove(
                            current_segment_index + split_segments.len
                        );
                        continue;
                    }
                }
            }
        }

        return .{ .segments = try result_segments.toOwnedSlice() };
    }

    /// the direction to execute the trimming operation in
    const TrimDir = enum {
        trim_before,
        trim_after,
    };

    /// trim the curve based on the input ordinate
    ///
    /// note: if the input ordinate is a boundary point, then result will be a
    ///       strict copy of self.
    pub fn trimmed_from_input_ordinate(
        self: @This(),
        ordinate: f32,
        direction: TrimDir,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        if (
            (
             self.extents_time().start_seconds == ordinate
             and direction == .trim_before
            )
            or
            (
             self.extents_time().end_seconds == ordinate
             and direction == .trim_after
            )

        ) {
            return try self.clone(allocator);
        }

        const seg_to_split_index = (
            self.find_segment_index(ordinate)
        ) orelse {
            return error.OutOfBounds;
        };

        const seg_to_split = self.segments[seg_to_split_index]; 

        {
            const is_bounding_point = (
                std.math.approxEqAbs(
                    @TypeOf(ordinate),
                    seg_to_split.p0.time, 
                    ordinate,
                    0.00001,
                )
                or std.math.approxEqAbs(
                    @TypeOf(ordinate),
                    seg_to_split.p3.time, 
                    ordinate,
                    0.00001,
                )
            );

            if (is_bounding_point) {
                return .{
                    .segments =  try allocator.dupe(
                        Segment,
                        self.segments,
                    ) 
                };
            }
        }

        const unorm = seg_to_split.findU_input(ordinate);

        const maybe_split_segments = seg_to_split.split_at(unorm);
        if (maybe_split_segments == null) {
            return .{};
        }
        const split_segments = maybe_split_segments.?;

        var new_segments:[]Segment = undefined;

        switch (direction) {
            // keep later stuff
            .trim_before => {
                const new_split = split_segments[1];
                const segments_to_copy = self.segments[seg_to_split_index+1..];

                new_segments = try allocator.alloc(
                    Segment,
                    segments_to_copy.len + 1
                );

                new_segments[0] = new_split;
                std.mem.copyForwards(
                    Segment,
                    new_segments[1..],
                    segments_to_copy
                );
            },
            // keep earlier stuff
            .trim_after => {
                const new_split = split_segments[0];
                const segments_to_copy = self.segments[0..seg_to_split_index];

                new_segments = try allocator.alloc(
                    Segment,
                    segments_to_copy.len + 1
                );

                std.mem.copyForwards(
                    Segment,
                    new_segments[0..segments_to_copy.len],
                    segments_to_copy
                );
                new_segments[new_segments.len - 1] = new_split;
            },
        }

        return .{ .segments = new_segments };
    }

    /// returns a copy of self, trimmed by bounds.  If bounds are greater than 
    /// the bounds of the existing curve, an unaltered copy is returned.  
    /// Otherwise the curve is copied, and trimmed to fit the bounds.
    pub fn trimmed_in_input_space(
        self: @This(),
        bounds: ContinuousTimeInterval,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        // @TODO; implement this using slices of a larger segment buffer to
        //        reduce the number of allocations/copies
        var front_split = try self.trimmed_from_input_ordinate(
            bounds.start_seconds,
            .trim_before,
            allocator
        );
        defer front_split.deinit(allocator);

        // @TODO: - does the above trim reset the origin on the input space?
        const result = try front_split.trimmed_from_input_ordinate(
            bounds.end_seconds,
            .trim_after,
            allocator,
        );

        return result;
    }

    /// split the segments on their first derivative roots, return a new curve
    /// with all the split segments and copies of the segments that were not
    /// split, memory is owned by the caller
    pub fn split_on_critical_points(
        self: @This(),
        allocator: std.mem.Allocator
    ) !TimeCurve 
    {
        var cSeg = hodographs.BezierSegment{
            .order = 3
        };

        var split_segments = std.ArrayList(Segment).init(allocator);
        defer split_segments.deinit();

        for (self.segments) 
            |seg| 
        {
            // build the segment to pass into the C library
            for (seg.points(), &cSeg.p) 
                |pt, *p| 
            {
                p.x = pt.time;
                p.y = pt.value;
            }

            var hodo = hodographs.compute_hodograph(&cSeg);
            const roots = hodographs.bezier_roots(&hodo);
            const inflections = hodographs.inflection_points(&cSeg);

            //-----------------------------------------------------------------
            // compute splits
            //-----------------------------------------------------------------
            var splits:[3]f32 = .{ 1, 1, 1};

            var split_count:usize = 0;

            const possible_splits:[3]f32 = .{
                roots.x,
                roots.y,
                inflections.x,
            };

            for (possible_splits) 
                |possible_split| 
            {
                // if the possible split isn't already a segment boundary
                if (possible_split > 0 and possible_split < 1) 
                {
                    var duplicate:bool = false;

                    for (0..split_count) 
                        |s_i| 
                    {
                        if (
                            @abs(splits[s_i] - possible_split) 
                            < generic_curve.EPSILON
                        ) {
                            duplicate = true;
                            break;
                        }
                    }

                    if (duplicate == false) {
                        splits[split_count] = possible_split;
                        split_count += 1;
                    }
                }
            }

            std.mem.sort(f32, &splits, {}, std.sort.asc(f32));

            var current_seg = seg;

            for (0..split_count) 
                |i| 
            {
                const pt = seg.eval_at(splits[i]);
                const u = current_seg.findU_input(pt.time);
                const maybe_xsplits = current_seg.split_at(u);

                if (maybe_xsplits) 
                    |xsplits| 
                {
                    try split_segments.append(xsplits[0]);
                    current_seg = xsplits[1];
                }
            }
            try split_segments.append(current_seg);
        }

        return .{ .segments = try split_segments.toOwnedSlice() };
    }
};

/// parse a .curve.json file from disk and return a TimeCurve
pub fn read_curve_json(
    file_path: latin_s8,
    allocator:std.mem.Allocator
) !TimeCurve 
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32)
    );
    defer allocator.free(source);

    // if its a linear curve
    if (std.mem.indexOf(u8, file_path, ".linear.json"))
        |_|
    {
        const lin_curve = try std.json.parseFromSliceLeaky(
            linear_curve.TimeCurveLinear,
            allocator,
            source, .{}
        );
        return TimeCurve.init_from_linear_curve(
            allocator,
            lin_curve
        );
    }

    return try std.json.parseFromSliceLeaky(
        TimeCurve,
        allocator,
        source,
        .{}
    );
}

test "Curve: read_curve_json" 
{
    const curve = try read_curve_json(
        "curves/linear.curve.json",
        std.testing.allocator
    );
    defer std.testing.allocator.free(curve.segments);

    try expectEqual(1, curve.segments.len);

    // first segment should already be linear
    const segment = curve.segments[0];

    const linearized_knots = try linearize_segment(
        std.testing.allocator,
        segment,
        0.01
    );
    defer std.testing.allocator.free(linearized_knots);

    // already linear!
    try expectEqual(2, linearized_knots.len);
}

test "Segment: projected_segment to 1/2" 
{
    {
        const half = Segment.init_from_start_end(
            .{ .time = -0.5, .value = -0.25, },
            .{ .time = 0.5, .value = 0.25, },
        );
        const double = Segment.init_from_start_end(
            .{ .time = -0.5, .value = -1, },
            .{ .time = 0.5, .value = 1, },
        );

        const half_through_double = double.project_segment(half);

        var u:f32 = 0;
        while (u<1) 
            : (u += 0.01)
        {
            try expectApproxEql(
                // t at u = 0 is -0.5
                u-0.5,
                half_through_double.eval_at(u).value
            );
        }
    }

    {
        const half = Segment.init_from_start_end(
            .{ .time = -0.5, .value = -0.5, },
            .{ .time = 0.5, .value = 0.0, },
        );
        const double = Segment.init_from_start_end(
            .{ .time = -0.5, .value = -0.5, },
            .{ .time = 0.5, .value = 1.5, },
        );

        const half_through_double = double.project_segment(half);

        var u:f32 = 0;
        while (u<1) 
            : (u += 0.01)
        {
            try expectApproxEql(
                // t at u = 0 is -0.5
                u-0.5,
                half_through_double.eval_at(u).value
            );
        }
    }
}

test "TimeCurve: positive length 1 linear segment test" 
{
    var crv_seg = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 1, .value = 0, },
            .{ .time = 2, .value = 1, },
        )
    };
    const xform_curve: TimeCurve = .{ .segments = &crv_seg, };

    // out of range returns error.OutOfBounds
    try expectError(error.OutOfBounds, xform_curve.evaluate(2));
    try expectError(error.OutOfBounds, xform_curve.evaluate(3));
    try expectError(error.OutOfBounds, xform_curve.evaluate(0));

    // find segment
    try expect(xform_curve.find_segment(1) != null);
    try expect(xform_curve.find_segment(1.5) != null);
    try expectEqual(@as(?*Segment, null), xform_curve.find_segment(2));

    // within the range of the curve
    try expectEqual(@as(f32, 0),    try xform_curve.evaluate(1));
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), try xform_curve.evaluate(1.25), generic_curve.EPSILON);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5),  try xform_curve.evaluate(1.5), generic_curve.EPSILON);
    try expectApproxEql(@as(f32, 0.75), try xform_curve.evaluate(1.75));
}

test "TimeCurve: project_linear_curve to identity" 
{

    var seg_0_4 = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 0, .value = 0, },
            .{ .time = 4, .value = 8, },
        ) 
    };
    const fst: TimeCurve = .{ .segments = &seg_0_4 };

    var seg_0_8 = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 0, .value = 0, },
            .{ .time = 8, .value = 4, },
        )
    };
    const snd: TimeCurve = .{ .segments = &seg_0_8 };

    const fst_lin = try fst.linearized(std.testing.allocator);
    defer fst_lin.deinit(std.testing.allocator);
    try expectEqual(@as(usize, 2), fst_lin.knots.len);

    const snd_lin = try snd.linearized(std.testing.allocator);
    defer snd_lin.deinit(std.testing.allocator);
    try expectEqual(@as(usize, 2), snd_lin.knots.len);

    const results = try fst.project_linear_curve(
        std.testing.allocator,
        snd_lin,
    );
    defer {
        for (results)
            |crv|
            {
                crv.deinit(std.testing.allocator);
            }
        std.testing.allocator.free(results);
    }
    try expectEqual(@as(usize, 1), results.len);

    if (results.len > 0) 
    {
        const result = results[0];
        try expectEqual(@as(usize, 2), result.knots.len);

        var x:f32 = 0;
        while (x < 1) 
        {
            // @TODO: fails because evaluating a linear curve
            try expectApproxEql(x, try result.evaluate(x));
            x += 0.1;
        }
    }
}

test "TimeCurve: projection_test non-overlapping" 
{
    var seg_0_1 = [_]Segment{ Segment.init_identity(0, 1) };
    const fst: TimeCurve = .{ .segments = &seg_0_1 };

    var seg_1_9 = [_]Segment{ 
        Segment.init_from_start_end(
            .{ .time = 1, .value = 1, },
            .{ .time = 9, .value = 5, },
        )
    };
    const snd: TimeCurve = .{ .segments = &seg_1_9 };

    const result = try fst.project_curve(
        std.testing.allocator,
        snd,
    );
    defer result.deinit(std.testing.allocator);

    try expectEqual(@as(usize, 0), result.segments.len);
}

test "positive slope 2 linear segment test" 
{
    var test_segment_arr = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 1, .value = 0, },
            .{ .time = 2, .value = 2, },
        )
    };
    const xform_curve = TimeCurve{ .segments = &test_segment_arr };

    const tests = &.{
        // expect result
        .{ 0,   1   },
        .{ 0.5, 1.25},
        .{ 1,   1.5 },
        .{ 1.5, 1.75},
    };

    inline for (tests) 
        |t| 
    {
        try std.testing.expectApproxEqAbs(
            @as(f32, t[0]),
            try xform_curve.evaluate(t[1]),
            generic_curve.EPSILON
        );
    }
}

test "negative length 1 linear segment test" 
{
    // declaring the segment here means that the memory management is handled
    // by stack unwinding
    var segments_xform = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = -2, .value = 0, },
            .{ .time = -1, .value = 1, },
        )
    };
    const xform_curve = TimeCurve{ .segments = &segments_xform };

    // outside of the range should return the original result
    // (identity transform)
    try expectError(error.OutOfBounds, xform_curve.evaluate(0));
    try expectError(error.OutOfBounds, xform_curve.evaluate(-3));
    try expectError(error.OutOfBounds, xform_curve.evaluate(-1));

    // within the range
    try expectEqual(try xform_curve.evaluate(-2), 0);
    try expectApproxEql(try xform_curve.evaluate(-1.5), 0.5);
}

fn line_orientation(
    test_point: control_point.ControlPoint,
    segment: Segment
) f32 
{
    const v1 = control_point.ControlPoint {
        .time  = test_point.time  - segment.p0.time,
        .value = test_point.value - segment.p0.value,
    };

    const v2 = control_point.ControlPoint {
        .time  = segment.p3.time  - segment.p0.time,
        .value = segment.p3.value - segment.p0.value,
    };

    return (v1.time * v2.value - v1.value * v2.time);
}

test "convex hull test" 
{
    const segment = create_bezier_segment(
        .{ .time = 1, .value = 0, },
        .{ .time = 1.25, .value = 1, },
        .{ .time = 1.75, .value = 0.65, },
        .{ .time = 2, .value = 0.24, },
    );

    const p0 = segment.p0;
    const p1 = segment.p1;
    var p2 = segment.p2;
    var p3 = segment.p3;

    const left_bound_segment = Segment.init_from_start_end(p0, p1);
    var right_bound_segment = Segment.init_from_start_end(p2, p3);

    // swizzle the right if necessary
    if (line_orientation(p0, right_bound_segment) < 0) 
    {
        const tmp = p3;
        p3 = p2;
        p2 = tmp;
        right_bound_segment = Segment.init_from_start_end(p2, p3);
    }

    const top_bound_segment = Segment.init_from_start_end(p1, p2);

    // NOTE: reverse the winding order because linear segment requires the 
    //       second point be _after_ the first in time
    const bottom_bound_segment = Segment.init_from_start_end(p0, p3);

    var i: f32 = 0;
    while (i <= 1) 
    {
        const test_point = segment.eval_at(i);

        try expect(line_orientation(test_point, left_bound_segment) >= 0);
        try expect(line_orientation(test_point, top_bound_segment) >= 0);
        try expect(line_orientation(test_point, right_bound_segment) >= 0);

        // because the winding order is reversed, this sign is reversed
        // the winding order is reversed on bottom_bound_segment because
        // we require that the points in the bezier be ordered, which
        // violates the winding order of the algorithm
        try expect(line_orientation(test_point, bottom_bound_segment) <= 0);

        i += 0.1;
    }
}

test "Segment: eval_at for out of range u" 
{
    var seg = [1]Segment{Segment.init_identity(3, 4)};
    const tc = TimeCurve{ .segments = &seg};

    try expectError(error.OutOfBounds, tc.evaluate(0));
    // right open intervals means the end point is out
    try expectError(error.OutOfBounds, tc.evaluate(4));
    try expectError(error.OutOfBounds, tc.evaluate(5));
}

pub fn write_json_file(
    json_blob: []const u8,
    to_fpath: []const u8
) !void 
{
    const file = try std.fs.cwd().createFile(
        to_fpath,
        .{ .read = true },
    );
    defer file.close();

    try file.writeAll(json_blob);
}

/// serialize a thing with a .debug_json_str to the filepath
pub fn write_json_file_curve(
    allocator: std.mem.Allocator,
    curve: anytype,
    to_fpath: []const u8
) !void 
{
    const json_blob = try curve.debug_json_str(allocator);
    defer allocator.free(json_blob);

    try write_json_file(
        json_blob,
        to_fpath
    );
}

test "json writer: curve" 
{
    const ident = try TimeCurve.init(
        std.testing.allocator,
        &.{ Segment.init_identity(-20, 30) },
    );
    defer ident.deinit(std.testing.allocator);

    const fpath = "/var/tmp/test.curve.json";

    try write_json_file_curve(
        std.testing.allocator,
        ident,
        fpath
    );

    const file = try std.fs.cwd().openFile(
        fpath,
        .{ .mode = .read_only },
    );
    defer file.close();

    var buffer: [2048]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);

    const blob = try ident.debug_json_str(std.testing.allocator);
    defer std.testing.allocator.free(blob);

    try expectEqualStrings(buffer[0..bytes_read], blob);
}

test "segment: findU_value" 
{
    const test_segment = Segment.init_identity(1,2);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        test_segment.findU_value(1.5),
        generic_curve.EPSILON
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        test_segment.findU_value(0.5),
        generic_curve.EPSILON
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        test_segment.findU_value(2.5),
        generic_curve.EPSILON
    );
}

test "TimeCurve: project u loop bug" 
{
    // specific to the linearized implementation
    const old_project_algo = project_algo;
    project_algo = ProjectionAlgorithms.linearized;
    defer project_algo = old_project_algo;

    const simple_s_segments = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 0, .value = 0},
            .{ .time = 30, .value = 10},
        ),
        Segment.init_from_start_end(
            .{ .time = 30, .value = 10},
            .{ .time = 60, .value = 90},
        ),
        Segment.init_from_start_end(
            .{ .time = 60, .value = 90},
            .{ .time = 100, .value = 100},
        ),
    };
    const simple_s = try TimeCurve.init(
        std.testing.allocator,
        &simple_s_segments
    );
    defer simple_s.deinit(std.testing.allocator);

    const u_seg = [_]Segment{
        Segment{
            .p0 = .{ .time = 0, .value = 0 },
            .p1 = .{ .time = 0, .value = 100 },
            .p2 = .{ .time = 100, .value = 100 },
            .p3 = .{ .time = 100, .value = 0 },
        },
    }; 
    const upside_down_u = try TimeCurve.init(
        std.testing.allocator,
        &u_seg,
    );
    defer upside_down_u.deinit(std.testing.allocator);

    const result  = try simple_s.project_curve(
        std.testing.allocator,
        upside_down_u,
    );
    defer result.deinit(std.testing.allocator);

    for (result.segments)
        |seg|
    {
        for (seg.points())
            |p|
        {
            try std.testing.expect(!std.math.isNan(p.time));
            try std.testing.expect(!std.math.isNan(p.value));
        }
    }

    errdefer std.log.err("simple_s: {!s}\n", .{ simple_s.debug_json_str(std.testing.allocator) } );
    errdefer std.log.err("u: {!s}\n", .{ upside_down_u.debug_json_str(std.testing.allocator) } );
    errdefer std.log.err("result: {!s}\n", .{ result.debug_json_str(std.testing.allocator) } );

    try expectEqual(@as(usize, 5), result.segments.len);
}

test "TimeCurve: project linear identity with linear 1/2 slope" 
{
    const linear_segment = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 60, .value = 60},
            .{ .time = 230, .value = 230},
        ),
    };
    const linear_crv = try TimeCurve.init(
        std.testing.allocator,
        &linear_segment,
    );
    defer linear_crv.deinit(std.testing.allocator);

    const linear_half_segment = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 0, .value = 100},
            .{ .time = 200, .value = 200},
        ),
    };
    const linear_half_crv = try TimeCurve.init(
        std.testing.allocator,
        &linear_half_segment
    );
    defer linear_half_crv.deinit(std.testing.allocator);

    const result = try linear_half_crv.project_curve(
        std.testing.allocator,
        linear_crv,
    );
    defer result.deinit(std.testing.allocator);

    try expectEqual(@as(usize, 1), result.segments.len);
}

test "TimeCurve: project linear u with out-of-bounds segments" 
{
    const linear_segment = [_]Segment{
        Segment.init_from_start_end(
            .{ .time = 60, .value = 60},
            .{ .time = 130, .value = 130},
        ),
    };
    const linear_crv = try TimeCurve.init(
        std.testing.allocator,
        &linear_segment,
    );
    defer linear_crv.deinit(std.testing.allocator);

    const u_seg = [_]Segment{
        Segment{
            .p0 = .{ .time = 0, .value = 0 },
            .p1 = .{ .time = 0, .value = 100 },
            .p2 = .{ .time = 100, .value = 100 },
            .p3 = .{ .time = 100, .value = 0 },
        },
    }; 
    const upside_down_u = try TimeCurve.init(
        std.testing.allocator,
        &u_seg,
    );
    defer upside_down_u.deinit(std.testing.allocator);

    const result : TimeCurve = try upside_down_u.project_curve(
        std.testing.allocator,
        linear_crv,
    );
    defer result.deinit(std.testing.allocator);

    try expectEqual(@as(usize, 4), result.segments.len);
}

test "TimeCurve: split_at_each_value u curve" 
{
    const u_seg = [_]Segment{
        Segment{
            .p0 = .{ .time = 0, .value = 0 },
            .p1 = .{ .time = 0, .value = 100 },
            .p2 = .{ .time = 100, .value = 100 },
            .p3 = .{ .time = 100, .value = 0 },
        },
    }; 
    const upside_down_u = try TimeCurve.init(
        std.testing.allocator,
        &u_seg
    );
    defer upside_down_u.deinit(std.testing.allocator);

    const upside_down_u_hodo = try upside_down_u.split_on_critical_points(
        std.testing.allocator
    );
    defer upside_down_u_hodo.deinit(std.testing.allocator);

    const split_points = [_]f32{
        u_seg[0].eval_at(0).value, 
        u_seg[0].eval_at(0.5).value, 
        u_seg[0].eval_at(0.75).value, 
        u_seg[0].eval_at(0.88).value, 
        u_seg[0].eval_at(1).value, 
    };

    const result = try upside_down_u_hodo.split_at_each_output_ordinate(
        &split_points,
        std.testing.allocator
    );
    defer result.deinit(std.testing.allocator);

    const endpoints = try result.segment_endpoints(
        std.testing.allocator
    );
    defer std.testing.allocator.free(endpoints);

    for (split_points, 0..)
        |sp_p, index|
    {
        errdefer std.debug.print(
            "Couldn't find : {d}: {d} in [{any:0.02}]\n",
            .{
                index,
                sp_p,
                endpoints,
            }
        );

        var found = false;
        for (endpoints)
            |pt|
        {
            if (
                std.math.approxEqAbs(
                    f32,
                    sp_p,
                    pt.value,
                    0.00001
                )
            ) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try expectEqual(@as(usize, 4), result.segments.len);
}

test "TimeCurve: split_at_each_value linear" 
{
    const identSeg = Segment.init_identity(-0.2, 1) ;
    const lin = try TimeCurve.init(
        std.testing.allocator,
        &.{identSeg},
    );
    defer lin.deinit(std.testing.allocator);

    const split_points = [_]f32{ -0.2, 0, 0.5, 1 };

    const result = try lin.split_at_each_output_ordinate(
        &split_points,
        std.testing.allocator
    );
    defer result.deinit(std.testing.allocator);

    var fbuf: [1024]f32 = undefined;
    const endpoints_cp = try result.segment_endpoints(
        std.testing.allocator
    );
    defer std.testing.allocator.free(endpoints_cp);
    for (endpoints_cp, 0..) 
        |cp, index| 
    {
        fbuf[index] = cp.value;
    }
    const endpoints = fbuf[0..endpoints_cp.len];

    for (split_points, 0..)
        |sp_p, index|
    {
        errdefer std.debug.print(
            "Couldn't find : {d}: {d} in [{any:0.02}]\n",
            .{
                index,
                sp_p,
                endpoints,
            }
        );

        var found = false;
        for (endpoints)
            |pt|
        {
            if (std.math.approxEqAbs(f32, sp_p, pt, 0.00001)) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try expectEqual(@as(usize, 3), result.segments.len);
}

test "TimeCurve: split_at_each_input_ordinate linear" 
{
    const identSeg = Segment.init_identity(-0.2, 1) ;
    const lin = try TimeCurve.init(
        std.testing.allocator,
        &.{identSeg},
    );
    defer lin.deinit(std.testing.allocator);

    const split_points = [_]f32{ -0.2, 0, 0.5, 1 };

    const result = try lin.split_at_each_input_ordinate(
        &split_points,
        std.testing.allocator
    );
    defer result.deinit(std.testing.allocator);

    var fbuf: [1024]f32 = undefined;
    const endpoints_cp = try result.segment_endpoints(
        std.testing.allocator
    );
    defer std.testing.allocator.free(endpoints_cp);

    for (endpoints_cp, 0..) 
        |cp, index| 
    {
        fbuf[index] = cp.value;
    }
    const endpoints = fbuf[0..endpoints_cp.len];

    for (split_points, 0..)
        |sp_p, index|
    {
        errdefer std.debug.print(
            "Couldn't find : {d}: {d} in [{any:0.02}]\n",
            .{
                index,
                sp_p,
                endpoints,
            }
        );

        var found = false;
        for (endpoints)
            |pt|
        {
            if (std.math.approxEqAbs(f32, sp_p, pt, 0.00001)) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try expectEqual(@as(usize, 3), result.segments.len);
}

test "TimeCurve: split_at_input_ordinate" 
{

    const test_curves = [_]TimeCurve{
        try TimeCurve.init(
            std.testing.allocator,
            &.{ Segment.init_identity(-20, 30) },
        ),
        try read_curve_json("curves/upside_down_u.curve.json", std.testing.allocator), 
        try read_curve_json("curves/scurve.curve.json", std.testing.allocator), 
    };
    defer test_curves[0].deinit(std.testing.allocator);
    defer test_curves[1].deinit(std.testing.allocator);
    defer test_curves[2].deinit(std.testing.allocator);

    for (test_curves, 0..) 
        |ident, loop| 
    {
        const extents = ident.extents();
        var split_loc:f32 = extents[0].time + 1;

        while (split_loc < extents[1].time) 
            : (split_loc += 1) 
        {
            errdefer std.log.err(
                "loop_index: {} extents: {any}, split_loc: {} curve: {!s}\n",
                .{
                    loop, extents, split_loc, ident.debug_json_str(std.testing.allocator)
                }
            );
            const split_ident = try ident.split_at_input_ordinate(
                split_loc,
                std.testing.allocator
            );
            defer split_ident.deinit(std.testing.allocator);

            try expectEqual(
                ident.segments.len + 1,
                split_ident.segments.len
            );

            // check that the end points are the same
            try expectEqual(
                ident.segments[0].p0.time,
                split_ident.segments[0].p0.time
            );
            try expectEqual(
                ident.segments[0].p3.time,
                split_ident.segments[1].p3.time
            );

            var i:f32 = extents[0].time;
            while (i < extents[1].time) 
                : (i += 1) 
            {
                const fst = try ident.evaluate(i);
                const snd = try split_ident.evaluate(i);
                errdefer std.log.err(
                    "Loop: {} orig: {} new: {}",
                    .{i, fst, snd}
                );
                try std.testing.expectApproxEqAbs(fst, snd, 0.001);
            }
        }
    }
}

test "TimeCurve: trimmed_from_input_ordinate" 
{
    const TestData = struct {
        // inputs
        ordinate:f32,
        direction: TimeCurve.TrimDir,

        // expected results
        result_extents:ContinuousTimeInterval,
        result_segment_count: usize,
    };

    const test_curves = [_]TimeCurve{
        try read_curve_json(
            "curves/linear_scurve_u.curve.json",
            std.testing.allocator
        ), 
        try TimeCurve.init(
            std.testing.allocator,
            &.{
                Segment.init_identity(-25, -5), 
                Segment.init_identity(-5, 5), 
                Segment.init_identity(5, 25), 
            }
        ),
    };

    defer test_curves[0].deinit(std.testing.allocator);
    defer test_curves[1].deinit(std.testing.allocator);

    for (test_curves, 0..) 
        |ident, curve_index| 
    {
        const extents = ident.extents();

        // assumes that curve is 0-centered
        const test_data = [_]TestData{
            // trim the first segment
            .{
                .ordinate = extents[0].time * 0.25,
                .direction = .trim_before,
                .result_extents = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time,
                },
                .result_segment_count = ident.segments.len,
            },
            .{
                .ordinate = extents[0].time * 0.25,
                .direction = .trim_after,
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[0].time * 0.25,
                },
                .result_segment_count = 1,
            },
            // trim the last segment
            .{
                .ordinate = extents[1].time * 0.75,
                .direction = .trim_before,
                .result_extents = .{
                    .start_seconds = extents[1].time * 0.75,
                    .end_seconds = extents[1].time,
                },
                .result_segment_count = 1,
            },
            .{
                .ordinate = extents[1].time * 0.75,
                .direction = .trim_after,
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time * 0.75,
                },
                .result_segment_count = ident.segments.len,
            },
            // trim on an existing split
            .{
                .ordinate = ident.segments[0].p3.time,
                .direction = .trim_after,
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time,
                },
                .result_segment_count = ident.segments.len,
            },
        };

        for (test_data, 0..) 
            |td, index| 
        {
            errdefer std.debug.print(
                "\ncurve: {} / loop: {}\n",
                .{ curve_index, index }
            );

            const trimmed_curve = try ident.trimmed_from_input_ordinate(
                td.ordinate,
                td.direction,
                std.testing.allocator,
            );
            const trimmed_extents = trimmed_curve.extents();
            defer trimmed_curve.deinit(std.testing.allocator);

            errdefer std.debug.print(
                "\n test: {any}\n trimmed_extents: {any} \n\n",
                .{ td , trimmed_extents}
            );

            try std.testing.expectApproxEqAbs(
                td.result_extents.start_seconds,
                trimmed_extents[0].time,
                0.001
            );
            try std.testing.expectApproxEqAbs(
                td.result_extents.end_seconds,
                trimmed_extents[1].time,
                0.001
            );
        }
    }
}

test "TimeCurve: trimmed_in_input_space" 
{
    if (true) {
        return error.SkipZigTest;
    }

    const TestData = struct {
        trim_range:ContinuousTimeInterval,
        result_extents:ContinuousTimeInterval,
    };

    const test_curves = [_]TimeCurve{
        try TimeCurve.init(
            std.testing.allocator,
            &.{ Segment.init_identity(-20, 30) }
        ),
        try read_curve_json("curves/upside_down_u.curve.json", std.testing.allocator), 
        try read_curve_json("curves/scurve.curve.json", std.testing.allocator), 
    };

    defer test_curves[0].deinit(std.testing.allocator);
    defer test_curves[1].deinit(std.testing.allocator);
    defer test_curves[2].deinit(std.testing.allocator);

    for (test_curves) 
        |ident|
    {
        const extents = ident.extents();

        const test_data = [_]TestData{
            // trim both
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time * 0.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time * 0.75,
                },
                },
            // trim start
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time * 1.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time,
                },
                },
            // trim end
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 1.25,
                    .end_seconds = extents[1].time * 0.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time * 0.75,
                },
                },
            // trim neither
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 1.25,
                    .end_seconds = extents[1].time * 1.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time * 1.25,
                    .end_seconds = extents[1].time * 1.75,
                },
                },
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time,
                },
                },
            };

        for (test_data) 
            |td|
        {
            const trimmed_curve = try ident.trimmed_in_input_space(
                td.trim_range,
                std.testing.allocator
            );
            defer trimmed_curve.deinit(std.testing.allocator);

            const trimmed_extents = trimmed_curve.extents();

            try std.testing.expectApproxEqAbs(
                td.result_extents.start_seconds,
                trimmed_extents[0].time,
                0.001
            );
            try std.testing.expectApproxEqAbs(
                td.result_extents.end_seconds,
                trimmed_extents[1].time,
                0.001
            );
        }
    }
}

test "TimeCurve: project_affine" 
{
    // @TODO: test bounds

    const test_crv = try read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer test_crv.deinit(std.testing.allocator);

    const test_affine = [_]opentime.transform.AffineTransform1D{
        .{
            .offset_seconds = -10,
            .scale = 0.5,
        },
        .{
            .offset_seconds = 0,
            .scale = 1,
        },
        .{
            .offset_seconds = 0,
            .scale = 2,
        },
        .{
            .offset_seconds = 10,
            .scale = 1,
        },
    };

    // @TODO: this seems like it could be cleaned up
    for (test_affine) 
        |testdata| 
    {
        const result = try test_crv.project_affine(
            testdata,
            std.testing.allocator
        );
        defer result.deinit(std.testing.allocator);

        // number of segments shouldn't have changed
        try expectEqual(test_crv.segments.len, result.segments.len);

        for (test_crv.segments, 0..) 
            |t_seg, t_seg_index| 
        {
            for (t_seg.points(), 0..) 
                |pt, pt_index| 
            {
                const result_pt = result.segments[t_seg_index].points()[pt_index];
                errdefer  std.debug.print(
                    "\nseg: {} pt: {} ({d:.2}, {d:.2})\n"
                    ++ "computed: ({d:.2}, {d:.2})\n\n", 
                    .{
                        t_seg_index,
                        pt_index,
                        pt.time,
                        pt.value,
                        result_pt.time,
                        result_pt.value, 
                    }
                );
                try expectApproxEql(
                    @as(
                        f32,
                        testdata.scale * pt.time + testdata.offset_seconds
                    ), 
                    result_pt.time
                );
            }
        }
    }
}

pub fn affine_project_curve(
    lhs: opentime.transform.AffineTransform1D,
    rhs: TimeCurve,
    allocator: std.mem.Allocator,
) !TimeCurve 
{
    const result_segments = try allocator.dupe(
        Segment,
        rhs.segments
    );

    for (result_segments) 
        |*seg| 
    {
        for (seg.point_ptrs()) 
            |pt| 
        {
            pt.value = lhs.applied_to_seconds(pt.value);
        }
    }

    return .{ .segments = result_segments };
}

test "affine_project_curve" 
{
    // @TODO: test bounds

    const test_crv = try read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer test_crv.deinit(std.testing.allocator);

    const test_affine = [_]opentime.transform.AffineTransform1D{
        .{
            .offset_seconds = -10,
            .scale = 0.5,
        },
        .{
            .offset_seconds = 0,
            .scale = 1,
        },
        .{
            .offset_seconds = 0,
            .scale = 2,
        },
        .{
            .offset_seconds = 10,
            .scale = 1,
        },
    };

    for (test_affine, 0..) 
        |testdata, test_loop_index| 
    {
        errdefer std.debug.print(
            "\ntest: {}, offset: {d:.2}, scale: {d:.2}\n",
            .{ test_loop_index, testdata.offset_seconds, testdata.scale }
        );
        const result = try affine_project_curve(
            testdata,
            test_crv, 
            std.testing.allocator
        );
        defer result.deinit(std.testing.allocator);

        // number of segments shouldn't have changed
        try expectEqual(test_crv.segments.len, result.segments.len);

        for (test_crv.segments, 0..) 
            |t_seg, t_seg_index| 
        {
            for (t_seg.points(), 0..) 
                |pt, pt_index| 
            {
                const result_pt = result.segments[t_seg_index].points()[pt_index];
                errdefer  std.debug.print(
                    "\nseg: {} pt: {} ({d:.2}, {d:.2})\n"
                    ++ "computed: ({d:.2}, {d:.2})\n\n", 
                    .{
                        t_seg_index,
                        pt_index,
                        pt.time,
                        pt.value,
                        result_pt.time,
                        result_pt.value, 
                    }
                );
                try expectApproxEql(
                    @as(
                        f32,
                        testdata.scale * pt.value + testdata.offset_seconds
                    ), 
                    result_pt.value
                );
            }
        }
    }
}

test "TimeCurve: split_on_critical_points s curve" 
{
    const s_seg = [_]Segment{
        Segment{
            .p0 = .{ .time = 0, .value = 0 },
            .p1 = .{ .time = 0, .value = 200 },
            .p2 = .{ .time = 100, .value = -100 },
            .p3 = .{ .time = 100, .value = 100 },
        },
    }; 
    const s_curve_seg = try TimeCurve.init(
        std.testing.allocator,
        &s_seg
    );
    defer s_curve_seg.deinit(std.testing.allocator);

    const s_curve_split = try s_curve_seg.split_on_critical_points(
        std.testing.allocator
    );
    defer s_curve_split.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), s_curve_split.segments.len);
}

test "TimeCurve: split_on_critical_points symmetric about the origin" 
{

    const TestData = struct {
        segment: Segment,
        inflection_point: f32,
        roots: [2]f32,
        split_segments: usize,
    };

    const tests = [_]TestData{
        .{
            .segment = Segment{
                .p0 = .{ .time = -0.5, .value = -0.5 },
                .p1 = .{ .time =    0, .value = -0.5 },
                .p2 = .{ .time =    0, .value =  0.5 },
                .p3 = .{ .time =  0.5, .value =  0.5 },
            },
            .inflection_point = 0.5,
            .roots = .{ -1, -1 },
            .split_segments = 2,
        },
        .{
            .segment = Segment{
                .p0 = .{ .time = -0.5, .value =    0 },
                .p1 = .{ .time =    0, .value =   -1 },
                .p2 = .{ .time =    0, .value =    1 },
                .p3 = .{ .time =  0.5, .value =    0 },
            },
            .inflection_point = 0.5,
            // assuming this is correct
            .roots = .{ 0.21132487, 0.788675129 },
            .split_segments = 4,
        },
    };

    for (tests, 0..) 
        |td, td_ind| 
    {
        errdefer std.debug.print("test that failed: {d}\n", .{ td_ind });
        const s_seg:[1]Segment = .{ td.segment };
        const s_curve_seg = try TimeCurve.init(
            std.testing.allocator,
            &s_seg
        );
        defer s_curve_seg.deinit(std.testing.allocator);

        const cSeg : hodographs.BezierSegment = .{
            .order = 3,
            .p = .{
                .{ .x = s_seg[0].p0.time, .y = s_seg[0].p0.value },
                .{ .x = s_seg[0].p1.time, .y = s_seg[0].p1.value },
                .{ .x = s_seg[0].p2.time, .y = s_seg[0].p2.value },
                .{ .x = s_seg[0].p3.time, .y = s_seg[0].p3.value },
            },
        };
        const inflections = hodographs.inflection_points(&cSeg);
        try std.testing.expectApproxEqAbs(
            @as(f32, td.inflection_point),
            inflections.x,
            generic_curve.EPSILON
        );

        var t:f32 = 0.0;
        while (t < 1) 
            : (t += 0.01) 
        {
            var c_split_l:hodographs.BezierSegment = undefined;
            var c_split_r:hodographs.BezierSegment = undefined;
            const c_result = hodographs.split_bezier(
                &cSeg,
                t,
                &c_split_l,
                &c_split_r
            );

            const maybe_zig_splits = s_seg[0].split_at(t);

            errdefer std.debug.print("\nt: {}\n", .{t});

            if (maybe_zig_splits == null) {
                try std.testing.expect(c_result == false);
                continue;
            } else {
                errdefer std.debug.print("zig added a split where c didnt", .{});
                try std.testing.expect(c_result == true);
            }

            const zig_splits = maybe_zig_splits.?;

            errdefer {
                std.debug.print("\n---\nc left:\n", .{});
                for (c_split_l.p) 
                    |p| 
                {
                    std.debug.print("  {d}, {d}\n", .{p.x, p.y});
                }
                std.debug.print("\nc right:\n", .{});
                for (c_split_r.p) 
                    |p| 
                {
                    std.debug.print("  {d}, {d}\n", .{p.x, p.y});
                }
                std.debug.print("\nzig left:\n", .{});
                for (zig_splits[0].points()) 
                    |p| 
                {
                    std.debug.print("  {d}, {d}\n", .{p.time, p.value});
                }
                std.debug.print("\nzig right:\n", .{});
                for (zig_splits[1].points()) 
                    |p| 
                {
                    std.debug.print("  {d}, {d}\n", .{p.time, p.value});
                }
            }

            for (0..4) 
                |i|
            {
                errdefer std.debug.print("\n\npt: {d} t: {d}\n", .{ i, t });
                try std.testing.expectApproxEqAbs(
                    c_split_l.p[i].x,
                    zig_splits[0].points()[i].time,
                    generic_curve.EPSILON
                );
                try std.testing.expectApproxEqAbs(
                    c_split_l.p[i].y,
                    zig_splits[0].points()[i].value,
                    generic_curve.EPSILON
                );
                try std.testing.expectApproxEqAbs(
                    c_split_r.p[i].x,
                    zig_splits[1].points()[i].time,
                    generic_curve.EPSILON
                );
                try std.testing.expectApproxEqAbs(
                    c_split_r.p[i].y,
                    zig_splits[1].points()[i].value,
                    generic_curve.EPSILON
                );
            }
        }

        const s_curve_split = try s_curve_seg.split_on_critical_points(
            std.testing.allocator
        );
        defer s_curve_split.deinit(std.testing.allocator);

        try std.testing.expectEqual(
            @as(usize, td.split_segments),
            s_curve_split.segments.len
        );

        // test the hodographs for this curve
        {
            const hodo = hodographs.compute_hodograph(&cSeg);
            const roots = hodographs.bezier_roots(&hodo);

            errdefer std.debug.print("roots: {any:0.2}\n", .{roots});

            try std.testing.expectApproxEqAbs(
                // @as(f32, -0.25),
                @as(f32, td.roots[0]),
                roots.x,
                generic_curve.EPSILON
            );
            try std.testing.expectApproxEqAbs(
                @as(f32, td.roots[1]),
                // @as(f32, 0.25),
                roots.y,
                generic_curve.EPSILON
            );
        }
    }
}

pub const tpa_result = struct {
    result: ?Segment = null,
    start_ddt: ?control_point.ControlPoint = null,
    start: ?control_point.ControlPoint = null,
    A:  ?control_point.ControlPoint = null,
    midpoint: ?control_point.ControlPoint = null,
    C:  ?control_point.ControlPoint = null,
    end: ?control_point.ControlPoint = null,
    end_ddt: ?control_point.ControlPoint = null,
    e1: ?control_point.ControlPoint = null,
    e2: ?control_point.ControlPoint = null,
    v1: ?control_point.ControlPoint = null,
    v2: ?control_point.ControlPoint = null,
    C1: ?control_point.ControlPoint = null,
    C2: ?control_point.ControlPoint = null,
    t: ?f32 = null,
};

pub fn three_point_guts_plot(
    start_knot: control_point.ControlPoint,
    mid_point: control_point.ControlPoint,
    t_mid_point: f32,
    d_mid_point_dt: control_point.ControlPoint,
    end_knot: control_point.ControlPoint,
) tpa_result
{
    var final_result = tpa_result{};

    final_result.start = start_knot;
    final_result.midpoint = mid_point;
    final_result.end = end_knot;
    final_result.t = t_mid_point;

    // from pomax
    // if B is the midpoint, there are points A and C such that C is the
    // midpoint of the first and last control points and A is the midpoint
    // of the inner control points.
    // 
    // Based on this we can infer the position of the inner control points

    const t_cubed = t_mid_point * t_mid_point * t_mid_point;
    const one_minus_t = 1 - t_mid_point;
    const one_minus_t_cubed = one_minus_t * one_minus_t * one_minus_t;

    const u = one_minus_t_cubed / (t_cubed + one_minus_t_cubed);

    // C is a lerp between the end points
    const C = bezier_math.lerp(1-u, start_knot, end_knot);
    final_result.C = C;

    // abs( (t^3 + (1-t)^3 - 1) / ( t^3 + (1-t)^3 ) )
    const ratio_t = cmp_t: {
        const result = @abs(
            (t_cubed + one_minus_t_cubed - 1)
            /
            (t_cubed + one_minus_t_cubed)
        );
        break :cmp_t result;
    };

    // A = B - (C-B)/ratio_t
    const A = a: {
        const c_minus_b = C.sub(mid_point);
        const c_minus_b_over_ratio_t = c_minus_b.div(ratio_t);
        break :a mid_point.sub(c_minus_b_over_ratio_t);
    };
    final_result.A = A;

    // then set up an e1 and e2 parallel to the baseline
    const e1 = control_point.ControlPoint{
        .time= mid_point.time - d_mid_point_dt.time * (t_mid_point),
        .value= mid_point.value - d_mid_point_dt.value * (t_mid_point),
    };
    const e2 = control_point.ControlPoint{
        .time= mid_point.time + d_mid_point_dt.time * (1-t_mid_point),
        .value = mid_point.value + d_mid_point_dt.value * (1-t_mid_point),
    };
    final_result.e1 = e1;
    final_result.e2 = e2;

    // then use those e1/e2 to derive the new hull coordinates
    // v1 = (e1 - t*A)/(1-t)
    const v1 = (e1.sub(A.mul(t_mid_point))).div(1-t_mid_point);
    // v2 = (e2 - (1-t)*A)/(t)
    const v2 = (e2.sub(A.mul(1-t_mid_point))).div(t_mid_point);
    final_result.v1 = v1;
    final_result.v2 = v2;

    // C1 = (v1 - (1 - t) * start) / t
    const C1 = (v1.sub(start_knot.mul(1-t_mid_point))).div(t_mid_point);
    // C2 = (v2 - t * end) / (1 - t)
    const C2 = (v2.sub(end_knot.mul(t_mid_point))).div(1 - t_mid_point);
    final_result.C1 = C1;
    final_result.C2 = C2;

    const result_seg : Segment = .{
        .p0 = start_knot,
        .p1 = C1,
        .p2 = C2,
        .p3 = end_knot,
    };
    final_result.result = result_seg;

    return final_result;
}
