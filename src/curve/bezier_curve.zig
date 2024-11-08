//! Bezier Curve implementation
//!
//! A sequence of right met 2d Bezier curve segments closed on the left and
//! open on the right. If the first formal segment does not start at -inf,
//! there is an implicit interval spanning -inf to the first formal segment. If
//! there final formal segment does not end at +inf, there is an implicit
//! interval spanning the last point in the final formal segment to +inf.
//! 
//! It is a formal requirement that an application supply control points that
//! satistfy the rules of a function over the input space, in other words, a
//! Bezier curve cannot contain a 2d Bezier curve segment that has a cusp or a
//! loop.
//!
//! The parameterization of the Bezier curve is named `u`.  `u` must be within
//! the closed interval of  [0, 1].
//!
//! The input and output value of a Bezier at `u` is B_in(u) and B_out(u).  To
//! compose a function B(in), in other words, then another function is needed,
//! M(in) which maps in to u.  Then to compute the out value for a given in
//! value, the functions can be composed: `B_out(M(in))`.
//!
//! A Bezier is composed of segments with four control points, which are pairs
//! of in and out ordinates from the input and output spaces respectively.
//!
//! Note that continuity between segments is not dictated by the Bezier
//! class. Interested applications should make their own data structure that
//! records continuity data, and are responsible for constraining the control
//! points to satisfy those continuity constraints. In the future, this library
//! may provide helper functions that aid in the computation of common
//! constraints, such as colinear tangents on end points, and so on.
//!
//! A Bezier with a single segment spanning t1 to t2 therefore looks like this:
//! 
//! -inf ------[---------)------- inf+
//!            in_1      in_2               input parameterization
//!            p0 p1 p2 p3                  segment parameterization
//! 

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const expect = std.testing.expect;

const opentime = @import("opentime");
const bezier_math = @import("bezier_math.zig");
const generic_curve = @import("generic_curve.zig");
const linear_curve = @import("linear_curve.zig");
const control_point = @import("control_point.zig");
const string_stuff = @import("string_stuff");

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

/// the projection algorithm to use when projecting a Bezier through a Bezier
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
    val: anytype,
    fst: anytype,
    snd: anytype
) bool 
{
    return (
           (fst < val - generic_curve.EPSILON and val < snd - generic_curve.EPSILON) 
        or (fst > val + generic_curve.EPSILON and val > snd + generic_curve.EPSILON)
    );
}


test "Bezier.Segment: can_project test" 
{
    const half = Bezier.Segment.init_from_start_end(
        .{ .in = -0.5, .out = -0.25, },
        .{ .in = 0.5, .out = 0.25, },
    );
    const double = Bezier.Segment.init_from_start_end(
        .{ .in = -0.5, .out = -1, },
        .{ .in = 0.5, .out = 1, },
    );

    try expectEqual(true, double.can_project(half));
    try expectEqual(false, half.can_project(double));
}

test "Bezier.Segment: debug_str test" 
{
    const seg = Bezier.Segment.init_from_start_end(
        .{.in = -0.5, .out = -0.5},
        .{.in =  0.5, .out = 0.5},
    );

    const result: []const u8=
        \\
        \\{
        \\    "p0": { "in": -0.500000, "out": -0.500000 },
        \\    "p1": { "in": -0.166667, "out": -0.166667 },
        \\    "p2": { "in": 0.166667, "out": 0.166667 },
        \\    "p3": { "in": 0.500000, "out": 0.500000 }
        \\}
        \\
            ;

        const blob = try seg.debug_json_str(std.testing.allocator);
        defer std.testing.allocator.free(blob);

        try expectEqualStrings( result,blob);
}

fn _is_approximately_linear(
    segment: Bezier.Segment,
    tolerance: f32
) bool 
{
    const u = (
        (segment.p1.mul(3.0)).sub(segment.p0.mul(2.0)).sub(segment.p3)
    );
    var ux = u.in * u.in;
    var uy = u.out * u.out;

    const v = (
        (segment.p2.mul(3.0)).sub(segment.p3.mul(2.0)).sub(segment.p0)
    );
    const vx = v.in * v.in;
    const vy = v.out * v.out;

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
    segment: Bezier.Segment,
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
        .{ .in = -0.5,     .out = -0.5},
        .{ .in = -0.16666, .out = -0.16666},
        .{ .in = 0.166666, .out = 0.16666},
        .{ .in = 0.5,      .out = 0.5}
    };
    const ident = Bezier.Segment.from_pt_array(original_knots_ident);

    try expectApproxEql(@as(opentime.Ordinate, 0), ident.eval_at(0.5).out);

    const linearized_ident_knots = try linearize_segment(
        std.testing.allocator,
        ident,
        0.01
    );
    defer std.testing.allocator.free(linearized_ident_knots);
    try expectEqual(@as(usize, 2), linearized_ident_knots.len);

    try expectApproxEql(
        original_knots_ident[0].in,
        linearized_ident_knots[0].in
    );
    try expectApproxEql(
        original_knots_ident[0].out,
        linearized_ident_knots[0].out
    );

    try expectApproxEql(
        original_knots_ident[3].in,
        linearized_ident_knots[1].in
    );
    try expectApproxEql(
        original_knots_ident[3].out,
        linearized_ident_knots[1].out
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
    file_path: string_stuff.latin_s8,
) !Bezier.Segment 
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32)
    );
    defer allocator.free(source);

    const result = try std.json.parseFromSlice(
        Bezier.Segment,
        allocator,
        source,
        .{}
    );
    defer result.deinit();

    return result.value;
}

test "segment: output_at_input and findU test over linear curve" 
{
    const seg = Bezier.Segment.init_from_start_end(
        .{.in = 2, .out = 2},
        .{.in = 3, .out = 3},
    );

    inline for ([_]opentime.Ordinate{2.1, 2.2, 2.3, 2.5, 2.7}) 
               |coord| 
    {
        try expectApproxEql(coord, seg.output_at_input(coord));
    }
}

test "segment: dual_eval_at over linear curve" 
{
    // identity curve
    {
        const seg = Bezier.Segment.init_identity(0, 1);

        inline for ([_]opentime.Ordinate{0.2, 0.4, 0.5, 0.98}) 
            |coord| 
        {
            const result = seg.eval_at_dual(.{ .r = coord, .i = 1});
            errdefer std.log.err(
                "coord: {any}, result: {any}\n",
                .{ coord, result }
            );
            try expectApproxEql(coord, result.r.in);
            try expectApproxEql(coord, result.r.out);
            try expectApproxEql(@as(f32, 1), result.i.in);
            try expectApproxEql(@as(f32, 1), result.i.out);
        }
    }

    // curve with slope 2
    {
        const seg = Bezier.Segment.init_from_start_end(
            .{ .in = 0, .out = 0 },
            .{ .in = 1, .out = 2 },
        );

        inline for ([_]opentime.Ordinate{0.2, 0.4, 0.5, 0.98}) 
            |coord| 
        {
            const result = seg.eval_at_dual(.{ .r = coord, .i = 1 });
            errdefer std.log.err(
                "coord: {any}, result: {any}\n",
                .{ coord, result }
            );
            try expectApproxEql(coord, result.r.in);
            try expectApproxEql(coord * 2, result.r.out);
            try expectApproxEql(@as(f32, 1), result.i.in);
            try expectApproxEql(@as(opentime.Ordinate, 2), result.i.out);
        }
    }
}

test "Bezier.Segment.init_identity check cubic spline" 
{
    // ensure that points are along line even for linear case
    const seg = Bezier.Segment.init_identity(0, 1);

    try expectEqual(@as(opentime.Ordinate, 0), seg.p0.in);
    try expectEqual(@as(opentime.Ordinate, 0), seg.p0.out);
    try expectEqual(@as(opentime.Ordinate, 1.0/3.0), seg.p1.in);
    try expectEqual(@as(opentime.Ordinate, 1.0/3.0), seg.p1.out);
    try expectEqual(@as(opentime.Ordinate, 2.0/3.0), seg.p2.in);
    try expectEqual(@as(opentime.Ordinate, 2.0/3.0), seg.p2.out);
    try expectEqual(@as(opentime.Ordinate, 1), seg.p3.in);
    try expectEqual(@as(opentime.Ordinate, 1), seg.p3.out);
}

/// A bezier interpolation mapping input times to output times
///
/// The Bezier is a sequence of 2d cubic bezier segments, closed at the start,
/// and open at the end, where each segment is met by the previous one.
///
/// The evaluation of a Bezier (S0, S1, ... Sn) at t, is therefore t if t <
/// S0.p0.in or t >= S0.p3.in. Otherwise, the segment S whose interval
/// [S.p0.in, S.p3.in) contains t is evaluated according to the cubic Bezier
/// equations.
pub const Bezier = struct {
    segments: []Segment = &.{},

    /// Bezier Curve Segment
    pub const Segment = struct {
        p0: control_point.ControlPoint = .{
            .in = 0,
            .out = 0,
        },
        p1: control_point.ControlPoint = .{
            .in = 0,
            .out = 0,
        },
        p2: control_point.ControlPoint = .{
            .in = 1,
            .out = 1,
        },
        p3: control_point.ControlPoint = .{
            .in = 1,
            .out = 1,
        },

        pub fn init_identity(
            input_start: opentime.Ordinate,
            input_end: opentime.Ordinate,
        ) Segment
        {
            return Segment.init_from_start_end(
                .{ .in = input_start, .out = input_start },
                .{ .in = input_end, .out = input_end }
            );
        }

        pub fn init_from_start_end(
            start: control_point.ControlPoint,
            end: control_point.ControlPoint
        ) Segment 
        {
            if (end.in >= start.in) 
            {
                return .{
                    .p0 = start,
                    .p1 = bezier_math.lerp(1.0/3.0, start, end),
                    .p2 = bezier_math.lerp(2.0/3.0, start, end),
                    .p3 = end,
                };
            }

            std.debug.panic(
                "Create linear segment failed, t0: {d} > t1: {d}\n",
                .{start.in, end.in}
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
            unorm_dual:opentime.Dual_Ord,
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

        /// output value of the segment at parameter unorm, [0, 1)
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
        pub fn overlaps_input_ordinate(
            self:@This(),
            t:opentime.Ordinate
        ) bool 
        {
            return (self.p0.in <= t and self.p3.in > t);
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

        pub fn extents_input(
            self: @This()
        ) opentime.ContinuousInterval
        {
            return .{
                .start = self.p0.in,
                .end = self.p3.in,
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
                        .in = @min(min.in, pt.in),
                        .out = @min(min.out, pt.out),
                    };
                    max = .{
                        .in = @max(max.in, pt.in),
                        .out = @max(max.out, pt.out),
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
                other_extents[0].out >= my_extents[0].in - generic_curve.EPSILON
                and other_extents[1].out < my_extents[1].in + generic_curve.EPSILON
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
                        .in = pt.in,
                        .out = self.output_at_input(pt.out),
                    };
                }

            return result;
        }

        /// @TODO: this function only works if the value is increasing over the 
        ///        segment.  The monotonicity and increasing -ness of a segment is
        ///        guaranteed for the input space, but not for the output space.
        pub fn findU_value(
            self:@This(),
            tgt_value: opentime.Ordinate
        ) f32 
        {
            return bezier_math.findU(
                tgt_value,
                self.p0.out,
                self.p1.out,
                self.p2.out,
                self.p3.out,
            );
        }

        pub fn findU_value_dual(
            self:@This(),
            tgt_value: opentime.Ordinate
        ) opentime.Dual_Ord 
        {
            return bezier_math.findU_dual(
                tgt_value,
                self.p0.out,
                self.p1.out,
                self.p2.out,
                self.p3.out,
            );
        }

        pub fn findU_input(
            self:@This(),
            input_ordinate: opentime.Ordinate
        ) f32 
        {
            return bezier_math.findU(
                input_ordinate,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in,
            );
        }

        pub fn findU_input_dual(
            self:@This(),
            input_ordinate: opentime.Ordinate
        ) opentime.Dual_Ord 
        {
            return bezier_math.findU_dual(
                input_ordinate,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in,
            );
        }

        /// returns the output value for the given input ordinate
        pub fn output_at_input(
            self: @This(),
            input_ord:opentime.Ordinate,
        ) opentime.Ordinate 
        {
            const u:f32 = bezier_math.findU(
                input_ord,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in
            );
            return self.eval_at(u).out;
        }

        pub fn output_at_input_dual(
            self: @This(),
            x:opentime.Ordinate
        ) control_point.Dual_CP 
        {
            const u = bezier_math.findU_dual(
                x,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in
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
            \\    "p0": {{ "in": {d:.6}, "out": {d:.6} }},
            \\    "p1": {{ "in": {d:.6}, "out": {d:.6} }},
            \\    "p2": {{ "in": {d:.6}, "out": {d:.6} }},
            \\    "p3": {{ "in": {d:.6}, "out": {d:.6} }}
            \\}}
            \\
            ,
            .{
                self.p0.in, self.p0.out,
                self.p1.in, self.p1.out,
                self.p2.in, self.p2.out,
                self.p3.in, self.p3.out,
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
                            tmp[pt_ind] = .{ .x = pt.in, .y = pt.out };
                        }

                    break :translate tmp;
                },
            };
        }
    };


    /// dupe the segments argument into the returned object
    pub fn init(
        allocator:std.mem.Allocator,
        segments: []const Segment,
    ) !Bezier 
    {
        return Bezier{ 
            .segments = try allocator.dupe(
                Segment,
                segments
            ) 
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator
    ) void 
    {
        allocator.free(self.segments);
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator
    ) !Bezier
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
    ) !Bezier 
    {
        return try Bezier.init(
            allocator,
            &.{ Segment.init_from_start_end(p0, p1) }
        );
    }

    /// convert a linear curve into a bezier one
    pub fn init_from_linear_curve(
        allocator:std.mem.Allocator,
        crv: linear_curve.Linear,
    ) !Bezier 
    {
        var result = std.ArrayList(Segment).init(allocator);
        result.deinit();

        const knots = crv.knots.len;

        for (crv.knots[0..knots-1], crv.knots[1..]) 
            |knot, next_knot| 
        {
            try result.append(Segment.init_from_start_end(knot, next_knot));
        }

        return Bezier{ .segments = try result.toOwnedSlice() };
    }

    /// output_at_input the curve at ordinate t in the input space
    pub fn output_at_input(
        self: @This(),
        input_space_ord: opentime.Ordinate,
    ) error{OutOfBounds}!opentime.Ordinate 
    {
        if (self.find_segment(input_space_ord)) 
           |seg|
        {
            return seg.output_at_input(input_space_ord);
        }

        // no segment found
        return error.OutOfBounds;
    }

    /// find the index of the segment that overlaps with the ordinate in input
    /// space
    pub fn find_segment_index(
        self: @This(),
        ord_input: opentime.Ordinate,
    ) ?usize 
    {
        const input_start = self.segments[0].p0.in - generic_curve.EPSILON;
        const last_seg = self.segments[self.segments.len - 1];
        const input_end = last_seg.p3.in - generic_curve.EPSILON;

        // @TODO: should this be inclusive of the endpoint?
        if (
            self.segments.len == 0 
            or ord_input < input_start
            or ord_input >= input_end
        )
        {
            return null;
        }

        // quick check if it is exactly the start ordinate of the first segment
        if (ord_input < input_start) {
            return 0;
        }

        for (self.segments, 0..) 
            |seg, index| 
        {
            if (
                seg.p0.in <= ord_input + generic_curve.EPSILON 
                and ord_input < seg.p3.in - generic_curve.EPSILON
            ) 
            {
                // exactly in a segment
                return index;
            }
        }

        // between segments, identity
        return null;
    }

    /// find the segment that overlaps with the input ordinate t_arg
    pub fn find_segment(
        self: @This(),
        ord_input: opentime.Ordinate,
    ) ?*Segment 
    {
        if (self.find_segment_index(ord_input)) 
           |ind|
        {
            return &self.segments[ind];
        }

        return null;
    }

    /// build a linearized version of this Bezier
    pub fn linearized(
        self: @This(),
        allocator:std.mem.Allocator,
    ) !linear_curve.Linear 
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

            // @TODO: expose the tolerance as a parameter(?)
            const subseg = try linearize_segment(
                allocator,
                seg,
                0.000001
            );
            defer allocator.free(subseg);

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

    /// project another curve through this one.  A curve maps 'input' to
    /// 'output' parameters.  
    ///
    /// if self maps from space b->c, and other maps from a->b, then the result
    /// will map a->c.
    pub fn project_curve(
        self: @This(),
        allocator: std.mem.Allocator,
        other: Bezier
        // @TODO: should be []Bezier <-  come back to this later
    ) !Bezier 
    {
        const result = try project_curve_guts(
            self,
            allocator,
            other,
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
        allocator: std.mem.Allocator,
        result : ?Bezier = null,
        self_split: ?Bezier = null,
        other_split: ?Bezier = null,
        to_project : ?Bezier = null,
        tpa: ?[]tpa_result = null,
        segments_to_project_through: ?[]usize = null,
        midpoint_derivatives: ?[]control_point.ControlPoint = null,
        f_prime_of_g_of_t: ?[]control_point.ControlPoint = null,
        g_prime_of_t: ?[]control_point.ControlPoint = null,

        pub fn deinit(
            self: @This(),
        ) void 
        {
            inline for (
                &.{
                    "result",
                    "self_split",
                    "other_split",
                    "to_project",
                }
            ) |it|
            {
                if (@field(self, it)) 
                    |thing| 
                {
                    thing.deinit(self.allocator);
                }
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
        allocator: std.mem.Allocator,
        other: Bezier,
        // should be []Bezier <-  come back to this later
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
            var split_points = std.ArrayList(opentime.Ordinate).init(allocator);
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
                            other_knot.out,
                            self_bounds[0].in,
                            self_bounds[1].in
                        )
                        // @TODO: omit cases where either endpoint is within an
                        //        epsilon of an endpoint
                    ) {
                        try split_points.append(other_knot.out);
                    }
                }
                const old_ptr = self_split.segments;
                defer allocator.free(old_ptr);

                self_split = (
                    try self_split.split_at_each_input_ordinate(
                        allocator,
                        split_points.items,
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
                            self_knot.in,
                            other_bounds[0].out,
                            other_bounds[1].out
                        )
                    ) {
                        try split_points.append(self_knot.in);
                    }
                }
                const old_ptr = other_split.segments;
                defer allocator.free(old_ptr);

                other_split = (
                    try other_split.split_at_each_output_ordinate(
                        allocator,
                        split_points.items,
                    )
                );
            }
        }

        result.other_split = try other_split.clone(allocator);

        var curves_to_project = std.ArrayList(Bezier).init(allocator);
        defer curves_to_project.deinit();

        var last_index: i32 = -10;
        var current_curve = std.ArrayList(Segment).init(allocator);
        defer current_curve.deinit();

        // having split both curves by both endpoints, throw out the segments
        // in other that will not be projected
        for (other_split.segments, 0..) 
            |other_segment, index| 
        {
            const other_seg_ext = other_segment.extents();

            if (
                (other_seg_ext[0].out < self_bounds[1].in - generic_curve.EPSILON)
                and (other_seg_ext[1].out > self_bounds[0].in + generic_curve.EPSILON)
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
                            Bezier{
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
                Bezier{
                    .segments = try current_curve.toOwnedSlice()
                }
            );
        }
        current_curve.deinit();

        if (curves_to_project.items.len == 0) 
        {
            result.result = Bezier{};
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
                const self_seg = self_split.find_segment(segment.p0.in) orelse {
                    continue;
                };
                try segments_to_project_through.append(
                    self_split.find_segment_index(segment.p0.in) orelse continue
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
                                .in  = pt.in,
                                .out = self_seg.output_at_input(pt.out)
                            };
                        }

                        // chain rule: h'(x) = f'(g(x)) * g'(x)
                        // chain rule: h'(t) = f'(g(t)) * g'(t)
                        // g(t) == midpoint (other @ t = 0.5)
                        // f'(g(t)) == f'(midpoint -- other @ t = 0.5)
                        // g'(t) == hodograph of other @ t = 0.5
                        // h'(t) = f'(midpoint) * hodograph of other @ t= 0.5
                        const u_in_self = self_seg.findU_input(
                            midpoint.out
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
                                    .in = f_prime_of_g_of_t.x, 
                                    .out= f_prime_of_g_of_t.y
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
                                    .in = g_prime_of_t.x, 
                                    .out= g_prime_of_t.y
                                }
                            );

                            if (true) {
                                break :chain_rule control_point.ControlPoint{
                                    .in  = f_prime_of_g_of_t.x * g_prime_of_t.x,
                                    .out = f_prime_of_g_of_t.y * g_prime_of_t.y,
                                };
                            } else {
                                break :chain_rule control_point.ControlPoint{
                                    .in  = g_prime_of_t.x,
                                    .out = f_prime_of_g_of_t.y * g_prime_of_t.y,
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
                            const projection_dual = self_seg.output_at_input_dual(
                                pt.out
                            );

                            // project the point
                            pt.* = .{
                                .in  = pt.in,
                                .out = projection_dual.r.out,
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
        other: linear_curve.Linear,
        // should return []Bezier
    ) ![]linear_curve.Linear
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
        allocator: std.mem.Allocator,
        aff: opentime.transform.AffineTransform1D,
    ) !Bezier 
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
                pt.in = aff.applied_to_ordinate(pt.in);
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
    pub fn extents_input(
        self:@This()
    ) opentime.ContinuousInterval 
    {
        return .{
            .start = self.segments[0].p0.in,
            .end = self.segments[self.segments.len - 1].p3.in,
        };
    }

    /// return the extents of the curve's output space
    pub fn extents_output(
        self:@This()
    ) opentime.ContinuousInterval 
    {
        const result = self.extents();
        return .{
            .start = result[0].out,
            .end = result[1].out,
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
                .in = @min(min.in, seg_extents[0].in),
                .out = @min(min.out, seg_extents[0].out),
            };
            max = .{
                .in = @max(min.in, seg_extents[1].in),
                .out = @max(min.out, seg_extents[1].out),
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
        allocator: std.mem.Allocator,
        ordinate:opentime.Ordinate,
    ) !Bezier 
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
        allocator: std.mem.Allocator,
        ordinates:[]const opentime.Ordinate,
    ) !Bezier 
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
                        ext[0].out,
                        ext[1].out
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
        allocator: std.mem.Allocator,
        ordinates:[]const opentime.Ordinate,
    ) !Bezier 
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
                        ext[0].in,
                        ext[1].in
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
        allocator: std.mem.Allocator,
        ordinate: opentime.Ordinate,
        direction: TrimDir,
    ) !Bezier 
    {
        if (
            (
             self.extents_input().start >= ordinate
             and direction == .trim_before
            )
            or
            (
             self.extents_input().end <= ordinate
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
                    seg_to_split.p0.in, 
                    ordinate,
                    0.00001,
                )
                or std.math.approxEqAbs(
                    @TypeOf(ordinate),
                    seg_to_split.p3.in, 
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
        allocator: std.mem.Allocator,
        bounds: opentime.ContinuousInterval,
    ) !Bezier 
    {
        // @TODO; implement this using slices of a larger segment buffer to
        //        reduce the number of allocations/copies
        var front_split = try self.trimmed_from_input_ordinate(
            allocator,
            bounds.start,
            .trim_before,
        );
        defer front_split.deinit(allocator);

        // @TODO: - does the above trim reset the origin on the input space?
        const result = try front_split.trimmed_from_input_ordinate(
            allocator,
            bounds.end,
            .trim_after,
        );

        return result;
    }

    /// split the segments on their first derivative roots, return a new curve
    /// with all the split segments and copies of the segments that were not
    /// split, memory is owned by the caller
    pub fn split_on_critical_points(
        self: @This(),
        allocator: std.mem.Allocator
    ) !Bezier 
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
                p.x = pt.in;
                p.y = pt.out;
            }

            var hodo = hodographs.compute_hodograph(&cSeg);
            const roots = hodographs.bezier_roots(&hodo);
            const inflections = hodographs.inflection_points(&cSeg);

            //-----------------------------------------------------------------
            // compute splits
            //-----------------------------------------------------------------
            var splits:[3]opentime.Ordinate = .{ 1, 1, 1};

            var split_count:usize = 0;

            const possible_splits:[3]opentime.Ordinate = .{
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

            std.mem.sort(opentime.Ordinate, &splits, {}, std.sort.asc(opentime.Ordinate));

            var current_seg = seg;

            for (0..split_count) 
                |i| 
            {
                const pt = seg.eval_at(splits[i]);
                const u = current_seg.findU_input(pt.in);
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

/// parse a .curve.json file from disk and return a Bezier
pub fn read_curve_json(
    file_path: string_stuff.latin_s8,
    allocator:std.mem.Allocator
) !Bezier 
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32)
    );
    defer allocator.free(source);

    // if its a linear curve
    if (
        std.mem.indexOf(
            u8,
            file_path,
            ".linear.json"
        ) != null
    )
    {
        return read_linear_curve_data(allocator, source);
    }

    return read_bezier_curve_data(allocator, source);
}

pub fn read_bezier_curve_data(
    allocator: std.mem.Allocator,
    source: []const u8,
) !Bezier
{
    return try std.json.parseFromSliceLeaky(
        Bezier,
        allocator,
        source,
        .{}
    );
}

pub fn read_linear_curve_data(
    allocator: std.mem.Allocator,
    source: []const u8,
) !Bezier
{
    const lin_curve = try std.json.parseFromSliceLeaky(
        linear_curve.Linear,
        allocator,
        source, .{}
    );
    return Bezier.init_from_linear_curve(
        allocator,
        lin_curve
    );
}

test "Curve: read_curve_json" 
{
    const curve = try read_curve_json(
        "curves/linear.curve.json",
        std.testing.allocator
    );
    defer curve.deinit(std.testing.allocator);

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
    try std.testing.expectEqualSlices(
        control_point.ControlPoint,
        &[_]control_point.ControlPoint{
            .{ .in = -0.5, .out = -0.5 },
            .{ .in =  0.5, .out =  0.5 },
        },
        linearized_knots,
    );
}

test "Bezier.Segment: projected_segment to 1/2" 
{
    {
        const half = Bezier.Segment.init_from_start_end(
            .{ .in = -0.5, .out = -0.25, },
            .{ .in = 0.5, .out = 0.25, },
        );
        const double = Bezier.Segment.init_from_start_end(
            .{ .in = -0.5, .out = -1, },
            .{ .in = 0.5, .out = 1, },
        );

        const half_through_double = double.project_segment(half);

        var u:f32 = 0;
        while (u<1) 
            : (u += 0.01)
        {
            try expectApproxEql(
                // t at u = 0 is -0.5
                u-0.5,
                half_through_double.eval_at(u).out
            );
        }
    }

    {
        const half = Bezier.Segment.init_from_start_end(
            .{ .in = -0.5, .out = -0.5, },
            .{ .in = 0.5, .out = 0.0, },
        );
        const double = Bezier.Segment.init_from_start_end(
            .{ .in = -0.5, .out = -0.5, },
            .{ .in = 0.5, .out = 1.5, },
        );

        const half_through_double = double.project_segment(half);

        var u:f32 = 0;
        while (u<1) 
            : (u += 0.01)
        {
            try expectApproxEql(
                // t at u = 0 is -0.5
                u-0.5,
                half_through_double.eval_at(u).out
            );
        }
    }
}

test "Bezier: positive length 1 linear segment test" 
{
    var crv_seg = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .{ .in = 1, .out = 0, },
            .{ .in = 2, .out = 1, },
        )
    };
    const xform_curve: Bezier = .{ .segments = &crv_seg, };

    // out of range returns error.OutOfBounds
    try expectError(error.OutOfBounds, xform_curve.output_at_input(2));
    try expectError(error.OutOfBounds, xform_curve.output_at_input(3));
    try expectError(error.OutOfBounds, xform_curve.output_at_input(0));

    // find segment
    try expect(xform_curve.find_segment(1) != null);
    try expect(xform_curve.find_segment(1.5) != null);
    try expectEqual(@as(?*Bezier.Segment, null), xform_curve.find_segment(2));

    // within the range of the curve
    try expectEqual(@as(opentime.Ordinate, 0),    try xform_curve.output_at_input(1));
    try std.testing.expectApproxEqAbs(@as(opentime.Ordinate, 0.25), try xform_curve.output_at_input(1.25), generic_curve.EPSILON);
    try std.testing.expectApproxEqAbs(@as(opentime.Ordinate, 0.5),  try xform_curve.output_at_input(1.5), generic_curve.EPSILON);
    try expectApproxEql(@as(opentime.Ordinate, 0.75), try xform_curve.output_at_input(1.75));
}

// removing the projection functions?
// test "Bezier: project_linear_curve to identity" 
// {
//
//     var seg_0_4 = [_]Bezier.Segment{
//         Bezier.Segment.init_from_start_end(
//             .{ .in = 0, .out = 0, },
//             .{ .in = 4, .out = 8, },
//         ) 
//     };
//     const fst: Bezier = .{ .segments = &seg_0_4 };
//
//     var seg_0_8 = [_]Bezier.Segment{
//         Bezier.Segment.init_from_start_end(
//             .{ .in = 0, .out = 0, },
//             .{ .in = 8, .out = 4, },
//         )
//     };
//     const snd: Bezier = .{ .segments = &seg_0_8 };
//
//     const fst_lin = try fst.linearized(std.testing.allocator);
//     defer fst_lin.deinit(std.testing.allocator);
//     try expectEqual(@as(usize, 2), fst_lin.knots.len);
//
//     const snd_lin = try snd.linearized(std.testing.allocator);
//     defer snd_lin.deinit(std.testing.allocator);
//     try expectEqual(@as(usize, 2), snd_lin.knots.len);
//
//     const results = try fst.project_linear_curve(
//         std.testing.allocator,
//         snd_lin,
//     );
//     defer {
//         for (results)
//             |crv|
//             {
//                 crv.deinit(std.testing.allocator);
//             }
//         std.testing.allocator.free(results);
//     }
//     try expectEqual(@as(usize, 1), results.len);
//
//     if (results.len > 0) 
//     {
//         const result = results[0];
//         try expectEqual(@as(usize, 2), result.knots.len);
//
//         var x:opentime.Ordinate = 0;
//         while (x < 1) 
//         {
//             // @TODO: fails because evaluating a linear curve
//             try expectApproxEql(x, try result.output_at_input(x));
//             x += 0.1;
//         }
//     }
// }

test "Bezier: projection_test non-overlapping" 
{
    var seg_0_1 = [_]Bezier.Segment{ Bezier.Segment.init_identity(0, 1) };
    const fst: Bezier = .{ .segments = &seg_0_1 };

    var seg_1_9 = [_]Bezier.Segment{ 
        Bezier.Segment.init_from_start_end(
            .{ .in = 1, .out = 1, },
            .{ .in = 9, .out = 5, },
        )
    };
    const snd: Bezier = .{ .segments = &seg_1_9 };

    const result = try fst.project_curve(
        std.testing.allocator,
        snd,
    );
    defer result.deinit(std.testing.allocator);

    try expectEqual(@as(usize, 0), result.segments.len);
}

test "positive slope 2 linear segment test" 
{
    var test_segment_arr = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .{ .in = 1, .out = 0, },
            .{ .in = 2, .out = 2, },
        )
    };
    const xform_curve = Bezier{ .segments = &test_segment_arr };

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
            try xform_curve.output_at_input(t[1]),
            generic_curve.EPSILON
        );
    }
}

test "negative length 1 linear segment test" 
{
    // declaring the segment here means that the memory management is handled
    // by stack unwinding
    var segments_xform = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .{ .in = -2, .out = 0, },
            .{ .in = -1, .out = 1, },
        )
    };
    const xform_curve = Bezier{ .segments = &segments_xform };

    // outside of the range should return the original result
    // (identity transform)
    try expectError(error.OutOfBounds, xform_curve.output_at_input(0));
    try expectError(error.OutOfBounds, xform_curve.output_at_input(-3));
    try expectError(error.OutOfBounds, xform_curve.output_at_input(-1));

    // within the range
    try expectEqual(try xform_curve.output_at_input(-2), 0);
    try expectApproxEql(try xform_curve.output_at_input(-1.5), 0.5);
}

fn line_orientation(
    test_point: control_point.ControlPoint,
    segment: Bezier.Segment
) f32 
{
    const v1 = control_point.ControlPoint {
        .in  = test_point.in  - segment.p0.in,
        .out = test_point.out - segment.p0.out,
    };

    const v2 = control_point.ControlPoint {
        .in  = segment.p3.in  - segment.p0.in,
        .out = segment.p3.out - segment.p0.out,
    };

    return (v1.in * v2.out - v1.out * v2.in);
}

test "convex hull test" 
{
    const segment:Bezier.Segment = .{
        .p0 = .{ .in = 1, .out = 0, },
        .p1 = .{ .in = 1.25, .out = 1, },
        .p2 = .{ .in = 1.75, .out = 0.65, },
        .p3 = .{ .in = 2, .out = 0.24, },
    };

    const p0 = segment.p0;
    const p1 = segment.p1;
    var p2 = segment.p2;
    var p3 = segment.p3;

    const left_bound_segment = Bezier.Segment.init_from_start_end(p0, p1);
    var right_bound_segment = Bezier.Segment.init_from_start_end(p2, p3);

    // swizzle the right if necessary
    if (line_orientation(p0, right_bound_segment) < 0) 
    {
        const tmp = p3;
        p3 = p2;
        p2 = tmp;
        right_bound_segment = Bezier.Segment.init_from_start_end(
            p2,
            p3,
        );
    }

    const top_bound_segment = Bezier.Segment.init_from_start_end(
        p1,
        p2,
    );

    // NOTE: reverse the winding order because linear segment requires the 
    //       second point be _after_ the first in input space
    const bottom_bound_segment = Bezier.Segment.init_from_start_end(
        p0,
        p3,
    );

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

test "Bezier.Segment: eval_at for out of range u" 
{
    var seg = [1]Bezier.Segment{Bezier.Segment.init_identity(3, 4)};
    const tc = Bezier{ .segments = &seg};

    try expectError(error.OutOfBounds, tc.output_at_input(0));
    // right open intervals means the end point is out
    try expectError(error.OutOfBounds, tc.output_at_input(4));
    try expectError(error.OutOfBounds, tc.output_at_input(5));
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
    const ident = try Bezier.init(
        std.testing.allocator,
        &.{ Bezier.Segment.init_identity(-20, 30) },
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
    const test_segment = Bezier.Segment.init_identity(1,2);
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

test "Bezier: project u loop bug" 
{
    // specific to the linearized implementation
    const old_project_algo = project_algo;
    project_algo = ProjectionAlgorithms.linearized;
    defer project_algo = old_project_algo;

    const simple_s_segments = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .{ .in = 0, .out = 0},
            .{ .in = 30, .out = 10},
        ),
        Bezier.Segment.init_from_start_end(
            .{ .in = 30, .out = 10},
            .{ .in = 60, .out = 90},
        ),
        Bezier.Segment.init_from_start_end(
            .{ .in = 60, .out = 90},
            .{ .in = 100, .out = 100},
        ),
    };
    const simple_s = try Bezier.init(
        std.testing.allocator,
        &simple_s_segments
    );
    defer simple_s.deinit(std.testing.allocator);

    const u_seg = [_]Bezier.Segment{
        Bezier.Segment{
            .p0 = .{ .in = 0, .out = 0 },
            .p1 = .{ .in = 0, .out = 100 },
            .p2 = .{ .in = 100, .out = 100 },
            .p3 = .{ .in = 100, .out = 0 },
        },
    }; 
    const upside_down_u = try Bezier.init(
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
            try std.testing.expect(!std.math.isNan(p.in));
            try std.testing.expect(!std.math.isNan(p.out));
        }
    }

    errdefer std.log.err("simple_s: {!s}\n", .{ simple_s.debug_json_str(std.testing.allocator) } );
    errdefer std.log.err("u: {!s}\n", .{ upside_down_u.debug_json_str(std.testing.allocator) } );
    errdefer std.log.err("result: {!s}\n", .{ result.debug_json_str(std.testing.allocator) } );

    try expectEqual(@as(usize, 5), result.segments.len);
}

test "Bezier: project linear identity with linear 1/2 slope" 
{
    const linear_segment = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .{ .in = 60, .out = 60},
            .{ .in = 230, .out = 230},
        ),
    };
    const linear_crv = try Bezier.init(
        std.testing.allocator,
        &linear_segment,
    );
    defer linear_crv.deinit(std.testing.allocator);

    const linear_half_segment = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .{ .in = 0, .out = 100},
            .{ .in = 200, .out = 200},
        ),
    };
    const linear_half_crv = try Bezier.init(
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

// // this test is disabled because at it is testing projecting a bezier curve
// // through another bezier curve.  At present, the library only supports
// // this through linearization.  This could be re-enabled at some point if
// // the bezier/bezier projection is implemented correctly or if another curve
// // base was used that wasn't linear - for example b-splines.  At present,
// // this isn't a particularly useful test.
// test "Bezier: project linear u with out-of-bounds segments" 
// {
//     if (true) {
//         return error.SkipZigTest;
//     }
//
//     var linear_segment = [_]Bezier.Segment{
//         Bezier.Segment.init_from_start_end(
//             .{ .in = 60, .out = 60},
//             .{ .in = 130, .out = 130},
//         ),
//     };
//     const linear_crv = Bezier{
//         .segments = &linear_segment,
//     };
//     const linear_crv_lin = try linear_crv.linearized(
//         std.testing.allocator
//     );
//     defer linear_crv_lin.deinit(std.testing.allocator);
//
//     var u_seg = [_]Bezier.Segment{
//         Bezier.Segment{
//             .p0 = .{ .in = 0, .out = 0 },
//             .p1 = .{ .in = 0, .out = 100 },
//             .p2 = .{ .in = 100, .out = 100 },
//             .p3 = .{ .in = 100, .out = 0 },
//         },
//     }; 
//     const upside_down_u = Bezier{
//         .segments = &u_seg,
//     };
//
//     const upside_down_u_linearizied = try upside_down_u.linearized(
//         std.testing.allocator
//     );
//     defer upside_down_u.deinit(std.testing.allocator);
//
//     const result : Bezier = try upside_down_u.project_curve(
//         std.testing.allocator,
//         linear_crv,
//     );
//     defer result.deinit(std.testing.allocator);
//
//     const result_lin = try upside_down_u_linearizied.project_curve(
//         std.testing.allocator,
//         linear_crv_lin
//     );
//     defer {
//         for (result_lin)
//             |crv|
//         {
//             crv.deinit(std.testing.allocator);
//         }
//         std.testing.allocator.free(result_lin);
//     }
//
//     errdefer {
//         std.debug.print( "Projection made result:\n",.{});
//
//         for (result.segments, 0..)
//             |seg, seg_ind|
//         {
//             std.debug.print("  {d}:\n", .{ seg_ind });
//             for (seg.points())
//                 |pt|
//             {
//                 std.debug.print(
//                     "    ({d}, {d})\n",
//                     .{ pt.in, pt.out }
//                 );
//             }
//         }
//
//         std.debug.print( "Linearized result:\n",.{});
//
//         for (result_lin, 0..)
//             |crv, crv_ind|
//         {
//             std.debug.print(
//                 "curve: {d}\n",
//                 .{ crv_ind }
//             );
//             for (crv.knots, 0..)
//                 |knot, knot_ind|
//                 {
//                     std.debug.print(
//                         "  {d}: ({d}, {d})\n",
//                         .{ knot_ind, knot.in, knot.out }
//                     );
//                 }
//         }
// }
//
//     try expectEqual(
//         @as(usize, 4),
//         result.segments.len
//     );
// }

test "Bezier: split_at_each_value u curve" 
{
    const u_seg = [_]Bezier.Segment{
        Bezier.Segment{
            .p0 = .{ .in = 0, .out = 0 },
            .p1 = .{ .in = 0, .out = 100 },
            .p2 = .{ .in = 100, .out = 100 },
            .p3 = .{ .in = 100, .out = 0 },
        },
    }; 
    const upside_down_u = try Bezier.init(
        std.testing.allocator,
        &u_seg
    );
    defer upside_down_u.deinit(std.testing.allocator);

    const upside_down_u_hodo = try upside_down_u.split_on_critical_points(
        std.testing.allocator
    );
    defer upside_down_u_hodo.deinit(std.testing.allocator);

    const split_points = [_]opentime.Ordinate{
        u_seg[0].eval_at(0).out, 
        u_seg[0].eval_at(0.5).out, 
        u_seg[0].eval_at(0.75).out, 
        u_seg[0].eval_at(0.88).out, 
        u_seg[0].eval_at(1).out, 
    };

    const result = try upside_down_u_hodo.split_at_each_output_ordinate(
        std.testing.allocator,
        &split_points,
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
                    opentime.Ordinate,
                    sp_p,
                    pt.out,
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

test "Bezier: split_at_each_value linear" 
{
    const identSeg = Bezier.Segment.init_identity(-0.2, 1) ;
    const lin = try Bezier.init(
        std.testing.allocator,
        &.{identSeg},
    );
    defer lin.deinit(std.testing.allocator);

    const split_points = [_]opentime.Ordinate{ -0.2, 0, 0.5, 1 };

    const result = try lin.split_at_each_output_ordinate(
        std.testing.allocator,
        &split_points,
    );
    defer result.deinit(std.testing.allocator);

    var fbuf: [1024]opentime.Ordinate = undefined;
    const endpoints_cp = try result.segment_endpoints(
        std.testing.allocator
    );
    defer std.testing.allocator.free(endpoints_cp);
    for (endpoints_cp, 0..) 
        |cp, index| 
    {
        fbuf[index] = cp.out;
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
            if (std.math.approxEqAbs(opentime.Ordinate, sp_p, pt, 0.00001)) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try expectEqual(@as(usize, 3), result.segments.len);
}

test "Bezier: split_at_each_input_ordinate linear" 
{
    const identSeg = Bezier.Segment.init_identity(-0.2, 1) ;
    const lin = try Bezier.init(
        std.testing.allocator,
        &.{identSeg},
    );
    defer lin.deinit(std.testing.allocator);

    const split_points = [_]opentime.Ordinate{ -0.2, 0, 0.5, 1 };

    const result = try lin.split_at_each_input_ordinate(
        std.testing.allocator,
        &split_points,
    );
    defer result.deinit(std.testing.allocator);

    var fbuf: [1024]opentime.Ordinate = undefined;
    const endpoints_cp = try result.segment_endpoints(
        std.testing.allocator
    );
    defer std.testing.allocator.free(endpoints_cp);

    for (endpoints_cp, 0..) 
        |cp, index| 
    {
        fbuf[index] = cp.out;
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
            if (std.math.approxEqAbs(opentime.Ordinate, sp_p, pt, 0.00001)) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try expectEqual(@as(usize, 3), result.segments.len);
}

test "Bezier: split_at_input_ordinate" 
{

    const test_curves = [_]Bezier{
        try Bezier.init(
            std.testing.allocator,
            &.{ Bezier.Segment.init_identity(-20, 30) },
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
        var split_loc:opentime.Ordinate = extents[0].in + 1;

        while (split_loc < extents[1].in) 
            : (split_loc += 1) 
        {
            errdefer std.log.err(
                "loop_index: {} extents: {any}, split_loc: {} curve: {!s}\n",
                .{
                    loop, extents, split_loc, ident.debug_json_str(std.testing.allocator)
                }
            );
            const split_ident = try ident.split_at_input_ordinate(
                std.testing.allocator,
                split_loc,
            );
            defer split_ident.deinit(std.testing.allocator);

            try expectEqual(
                ident.segments.len + 1,
                split_ident.segments.len
            );

            // check that the end points are the same
            try expectEqual(
                ident.segments[0].p0.in,
                split_ident.segments[0].p0.in
            );
            try expectEqual(
                ident.segments[0].p3.in,
                split_ident.segments[1].p3.in
            );

            var i:opentime.Ordinate = extents[0].in;
            while (i < extents[1].in) 
                : (i += 1) 
            {
                const fst = try ident.output_at_input(i);
                const snd = try split_ident.output_at_input(i);
                errdefer std.log.err(
                    "Loop: {} orig: {} new: {}",
                    .{i, fst, snd}
                );
                try std.testing.expectApproxEqAbs(
                    fst,
                    snd,
                    0.0001
                );
            }
        }
    }
}

test "Bezier: trimmed_from_input_ordinate" 
{
    const TestData = struct {
        // inputs
        ordinate:opentime.Ordinate,
        direction: Bezier.TrimDir,

        // expected results
        result_extents:opentime.ContinuousInterval,
        result_segment_count: usize,
    };

    const test_curves = [_]Bezier{
        try read_curve_json(
            "curves/linear_scurve_u.curve.json",
            std.testing.allocator
        ), 
        try Bezier.init(
            std.testing.allocator,
            &.{
                Bezier.Segment.init_identity(-25, -5), 
                Bezier.Segment.init_identity(-5, 5), 
                Bezier.Segment.init_identity(5, 25), 
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
                .ordinate = extents[0].in * 0.25,
                .direction = .trim_before,
                .result_extents = .{
                    .start = extents[0].in * 0.25,
                    .end = extents[1].in,
                },
                .result_segment_count = ident.segments.len,
            },
            .{
                .ordinate = extents[0].in * 0.25,
                .direction = .trim_after,
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[0].in * 0.25,
                },
                .result_segment_count = 1,
            },
            // trim the last segment
            .{
                .ordinate = extents[1].in * 0.75,
                .direction = .trim_before,
                .result_extents = .{
                    .start = extents[1].in * 0.75,
                    .end = extents[1].in,
                },
                .result_segment_count = 1,
            },
            .{
                .ordinate = extents[1].in * 0.75,
                .direction = .trim_after,
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in * 0.75,
                },
                .result_segment_count = ident.segments.len,
            },
            // trim on an existing split
            .{
                .ordinate = ident.segments[0].p3.in,
                .direction = .trim_after,
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in,
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
                std.testing.allocator,
                td.ordinate,
                td.direction,
            );
            const trimmed_extents = trimmed_curve.extents();
            defer trimmed_curve.deinit(std.testing.allocator);

            errdefer std.debug.print(
                "\n test: {any}\n trimmed_extents: {any} \n\n",
                .{ td , trimmed_extents}
            );

            try std.testing.expectApproxEqAbs(
                td.result_extents.start,
                trimmed_extents[0].in,
                0.001
            );
            try std.testing.expectApproxEqAbs(
                td.result_extents.end,
                trimmed_extents[1].in,
                0.001
            );
        }
    }
}

test "Bezier: trimmed_in_input_space" 
{
    const TestData = struct {
        trim_range: opentime.ContinuousInterval,
        result_extents: opentime.ContinuousInterval,
    };

    const test_curves = [_]Bezier{
        try Bezier.init(
            std.testing.allocator,
            &.{ Bezier.Segment.init_identity(-20, 30) }
        ),
        try read_curve_json("curves/upside_down_u.curve.json", std.testing.allocator), 
        try read_curve_json("curves/scurve.curve.json", std.testing.allocator), 
    };

    defer test_curves[0].deinit(std.testing.allocator);
    defer test_curves[1].deinit(std.testing.allocator);
    defer test_curves[2].deinit(std.testing.allocator);

    for (test_curves, 0..) 
        |ident, crv_ind|
    {
        const extents = ident.extents();

        const test_data = [_]TestData{
            // trim both
            .{
                .trim_range = .{
                    .start = extents[0].in * 0.25,
                    .end = extents[1].in * 0.75,
                },
                .result_extents = .{
                    .start = extents[0].in * 0.25,
                    .end = extents[1].in * 0.75,
                },
                },
            // trim start
            .{
                .trim_range = .{
                    .start = extents[0].in * 0.25,
                    .end = extents[1].in * 1.75,
                },
                .result_extents = .{
                    .start = extents[0].in * 0.25,
                    .end = extents[1].in,
                },
                },
            // trim end
            .{
                .trim_range = .{
                    .start = extents[0].in * 1.25,
                    .end = extents[1].in * 0.75,
                },
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in * 0.75,
                },
                },
            // trim neither
            .{
                .trim_range = .{
                    .start = extents[0].in * 1.25,
                    .end = extents[1].in * 1.75,
                },
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in,
                },
                },
            .{
                .trim_range = .{
                    .start = extents[0].in,
                    .end = extents[1].in,
                },
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in,
                },
                },
            };

        for (test_data, 0..) 
            |td, td_ind|
        {
            errdefer {
                const crv_str = ident.debug_json_str(
                    std.testing.allocator
                ) catch "ERRMAKESTRING";
                defer std.testing.allocator.free(crv_str);
                const crv_extents = ident.extents();

                std.debug.print(
                    "test curve:{d}\n  {s}\n  extents: (({d}, {d}), ({d}, {d}))\n",
                    .{
                        crv_ind,
                        crv_str,
                        crv_extents[0].in, crv_extents[0].out,
                        crv_extents[1].in, crv_extents[1].out,
                    }
                );
                std.debug.print("  Error on iteration: {d}\n", .{ td_ind });
                std.debug.print(
                    "    trim_range: ({d}, {d})\n    result_extents: ({d}, {d})\n",
                    .{
                        td.trim_range.start, 
                        td.trim_range.end,
                        td.result_extents.start, 
                        td.result_extents.end,
                    },
                );
            }
            const trimmed_curve = try ident.trimmed_in_input_space(
                std.testing.allocator,
                td.trim_range,
            );
            defer trimmed_curve.deinit(std.testing.allocator);

            const trimmed_extents = trimmed_curve.extents();
            errdefer {
                std.debug.print(
                    "    measured result_extents: ({d}, {d}), ({d}, {d})\n",
                    .{
                        trimmed_extents[0].in, 
                        trimmed_extents[0].out,
                        trimmed_extents[1].in, 
                        trimmed_extents[1].out,
                    },
                );
            }

            try std.testing.expectApproxEqAbs(
                td.result_extents.start,
                trimmed_extents[0].in,
                0.001
            );
            try std.testing.expectApproxEqAbs(
                td.result_extents.end,
                trimmed_extents[1].in,
                0.001
            );
        }
    }
}

test "Bezier: project_affine" 
{
    // @TODO: test bounds

    const test_crv = try read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer test_crv.deinit(std.testing.allocator);

    const test_affine = [_]opentime.transform.AffineTransform1D{
        .{
            .offset = -10,
            .scale = 0.5,
        },
        .{
            .offset = 0,
            .scale = 1,
        },
        .{
            .offset = 0,
            .scale = 2,
        },
        .{
            .offset = 10,
            .scale = 1,
        },
    };

    // @TODO: this seems like it could be cleaned up
    for (test_affine) 
        |testdata| 
    {
        const result = try test_crv.project_affine(
            std.testing.allocator,
            testdata,
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
                        pt.in,
                        pt.out,
                        result_pt.in,
                        result_pt.out, 
                    }
                );
                try expectApproxEql(
                    @as(
                        opentime.Ordinate,
                        testdata.scale * pt.in + testdata.offset
                    ), 
                    result_pt.in
                );
            }
        }
    }
}

pub fn join_bez_aff_unbounded(
    allocator: std.mem.Allocator,
    args: struct {
        b2c: opentime.transform.AffineTransform1D,
        a2b: Bezier,
    },
) !Bezier 
{
    const a2c = try args.a2b.clone(allocator);

    for (a2c.segments) 
        |*seg| 
    {
        for (seg.point_ptrs()) 
            |pt| 
        {
            pt.out = args.b2c.applied_to_ordinate(pt.out);
        }
    }

    return a2c;
}

test "join_bez_aff_unbounded" 
{
    // @TODO: test bounds

    const test_crv = try read_curve_json(
        "curves/upside_down_u.curve.json",
        std.testing.allocator
    );
    defer test_crv.deinit(std.testing.allocator);

    const test_affine = [_]opentime.transform.AffineTransform1D{
        .{
            .offset = -10,
            .scale = 0.5,
        },
        .{
            .offset = 0,
            .scale = 1,
        },
        .{
            .offset = 0,
            .scale = 2,
        },
        .{
            .offset = 10,
            .scale = 1,
        },
    };

    for (test_affine, 0..) 
        |testdata, test_loop_index| 
    {
        errdefer std.debug.print(
            "\ntest: {}, offset: {d:.2}, scale: {d:.2}\n",
            .{ test_loop_index, testdata.offset, testdata.scale }
        );
        const result = try join_bez_aff_unbounded(
            std.testing.allocator,
            .{
                .a2b = test_crv,
                .b2c = testdata,
            },
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
                        pt.in,
                        pt.out,
                        result_pt.in,
                        result_pt.out, 
                    }
                );
                try expectApproxEql(
                    @as(
                        opentime.Ordinate,
                        testdata.scale * pt.out + testdata.offset
                    ), 
                    result_pt.out
                );
            }
        }
    }
}

test "Bezier: split_on_critical_points s curve" 
{
    const s_seg = [_]Bezier.Segment{
        Bezier.Segment{
            .p0 = .{ .in = 0, .out = 0 },
            .p1 = .{ .in = 0, .out = 200 },
            .p2 = .{ .in = 100, .out = -100 },
            .p3 = .{ .in = 100, .out = 100 },
        },
    }; 
    const s_curve_seg = try Bezier.init(
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

test "Bezier: split_on_critical_points symmetric about the origin" 
{

    const TestData = struct {
        segment: Bezier.Segment,
        inflection_point: opentime.Ordinate,
        roots: [2]opentime.Ordinate,
        split_segments: usize,
    };

    const tests = [_]TestData{
        .{
            .segment = Bezier.Segment{
                .p0 = .{ .in = -0.5, .out = -0.5 },
                .p1 = .{ .in =    0, .out = -0.5 },
                .p2 = .{ .in =    0, .out =  0.5 },
                .p3 = .{ .in =  0.5, .out =  0.5 },
            },
            .inflection_point = 0.5,
            .roots = .{ -1, -1 },
            .split_segments = 2,
        },
        .{
            .segment = Bezier.Segment{
                .p0 = .{ .in = -0.5, .out =    0 },
                .p1 = .{ .in =    0, .out =   -1 },
                .p2 = .{ .in =    0, .out =    1 },
                .p3 = .{ .in =  0.5, .out =    0 },
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
        const s_seg:[1]Bezier.Segment = .{ td.segment };
        const s_curve_seg = try Bezier.init(
            std.testing.allocator,
            &s_seg
        );
        defer s_curve_seg.deinit(std.testing.allocator);

        const cSeg : hodographs.BezierSegment = .{
            .order = 3,
            .p = .{
                .{ .x = s_seg[0].p0.in, .y = s_seg[0].p0.out },
                .{ .x = s_seg[0].p1.in, .y = s_seg[0].p1.out },
                .{ .x = s_seg[0].p2.in, .y = s_seg[0].p2.out },
                .{ .x = s_seg[0].p3.in, .y = s_seg[0].p3.out },
            },
        };
        const inflections = hodographs.inflection_points(&cSeg);
        try std.testing.expectApproxEqAbs(
            @as(opentime.Ordinate, td.inflection_point),
            inflections.x,
            generic_curve.EPSILON
        );

        var t:opentime.Ordinate = 0.0;
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
                    std.debug.print("  {d}, {d}\n", .{p.in, p.out});
                }
                std.debug.print("\nzig right:\n", .{});
                for (zig_splits[1].points()) 
                    |p| 
                {
                    std.debug.print("  {d}, {d}\n", .{p.in, p.out});
                }
            }

            for (0..4) 
                |i|
            {
                errdefer std.debug.print("\n\npt: {d} t: {d}\n", .{ i, t });
                try std.testing.expectApproxEqAbs(
                    c_split_l.p[i].x,
                    zig_splits[0].points()[i].in,
                    generic_curve.EPSILON
                );
                try std.testing.expectApproxEqAbs(
                    c_split_l.p[i].y,
                    zig_splits[0].points()[i].out,
                    generic_curve.EPSILON
                );
                try std.testing.expectApproxEqAbs(
                    c_split_r.p[i].x,
                    zig_splits[1].points()[i].in,
                    generic_curve.EPSILON
                );
                try std.testing.expectApproxEqAbs(
                    c_split_r.p[i].y,
                    zig_splits[1].points()[i].out,
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
                // @as(opentime.Ordinate, -0.25),
                @as(opentime.Ordinate, td.roots[0]),
                roots.x,
                generic_curve.EPSILON
            );
            try std.testing.expectApproxEqAbs(
                @as(opentime.Ordinate, td.roots[1]),
                // @as(f32, 0.25),
                roots.y,
                generic_curve.EPSILON
            );
        }
    }
}

pub const tpa_result = struct {
    result: ?Bezier.Segment = null,
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
    t: ?opentime.Ordinate = null,
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
        .in= mid_point.in - d_mid_point_dt.in * (t_mid_point),
        .out= mid_point.out - d_mid_point_dt.out * (t_mid_point),
    };
    const e2 = control_point.ControlPoint{
        .in= mid_point.in + d_mid_point_dt.in * (1-t_mid_point),
        .out = mid_point.out + d_mid_point_dt.out * (1-t_mid_point),
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

    const result_seg : Bezier.Segment = .{
        .p0 = start_knot,
        .p1 = C1,
        .p2 = C2,
        .p3 = end_knot,
    };
    final_result.result = result_seg;

    return final_result;
}
