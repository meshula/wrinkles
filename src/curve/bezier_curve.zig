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
//! ```
//! -inf ------[---------)------- inf+
//!            in_1      in_2               input parameterization
//!            p0 p1 p2 p3                  segment parameterization
//! ```
//!
//! Includes functions that operate on `Dual_CP` for implicit differentation.

const std = @import("std");

const opentime = @import("opentime");

pub const hodographs = @import("spline_gym");
pub const math = @import("bezier_math.zig");

const linear_curve = @import("linear_curve.zig");
const control_point = @import("control_point.zig");

const epsilon = @import("epsilon.zig").epsilon;

/// Type of the `u` parameter of the Bezier curve, follows
/// `opentime.Ordinate.InnerType`.
pub const U_TYPE = opentime.Ordinate.InnerType;

/// Returns true if val is between fst and snd regardless of whether fst or snd
/// is greater.
inline fn _is_between(
    /// value to check
    val: anytype,
    /// first bound
    fst: anytype,
    /// second bound
    snd: anytype,
) bool 
{
    return (
        (
         fst.lt(val.sub(opentime.Ordinate.epsilon)) 
         and val.lt(snd.sub(opentime.Ordinate.epsilon))
        )
        or (
            fst.gt(val.add(opentime.Ordinate.epsilon)) 
            and val.gt(snd.add(opentime.Ordinate.epsilon))
        )
    );
}


test "Bezier.Segment: can_project test" 
{
    const half = Bezier.Segment.init_from_start_end(
        .init(.{ .in = -0.5, .out = -0.25, }),
        .init(.{ .in = 0.5, .out = 0.25, }),
    );
    const double = Bezier.Segment.init_from_start_end(
        .init(.{ .in = -0.5, .out = -1, }),
        .init(.{ .in = 0.5, .out = 1, }),
    );

    try std.testing.expectEqual(true, double.can_project(half));
    try std.testing.expectEqual(false, half.can_project(double));
}

test "Bezier.Segment: debug_str test" 
{
    const allocator = std.testing.allocator;

    const seg = Bezier.Segment.init_from_start_end(
        .init(.{.in = -0.5, .out = -0.5}),
        .init(.{.in =  0.5, .out = 0.5}),
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

        const blob = try seg.debug_json_str(allocator);
        defer allocator.free(blob);

        try std.testing.expectEqualStrings( result,blob);
}

fn _is_approximately_linear(
    segment: Bezier.Segment,
    tolerance: f32,
) bool 
{
    const u = (
        (segment.p1.mul(3.0)).sub(segment.p0.mul(2.0)).sub(segment.p3)
    );
    var ux = u.in.mul(u.in);
    var uy = u.out.mul(u.out);

    const v = (
        (segment.p2.mul(3.0)).sub(segment.p3.mul(2.0)).sub(segment.p0)
    );
    const vx = v.in.mul(v.in);
    const vy = v.out.mul(v.out);

    if (ux.lt(vx)) {
        ux = vx;
    }
    if (uy.lt(vy)) {
        uy = vy;
    }

    return (ux.add(uy).lteq(tolerance));
}

/// Based on this paper:
/// https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.86.162&rep=rep1&type=pdf
/// return a list of segments that approximate the segment with the given tolerance
///
/// ASSUMES THAT ALL POINTS ARE FINITE
pub fn linearize_segment(
    allocator: std.mem.Allocator,
    /// Bezier segment to linearize.
    segment: Bezier.Segment,
    /// How close the linearized segment should be to the original Bezier curve.
    tolerance:f32,
) ![]control_point.ControlPoint
{
    // @TODO: this function should compute and preserve the derivatives on the
    //        bezier segments
    var result: std.ArrayList(control_point.ControlPoint) = .empty;

    if (_is_approximately_linear(segment, tolerance)) 
    {
        // terminal condition
        try result.append(allocator, segment.p0);
        try result.append(allocator, segment.p3);
    } 
    else 
    {
        // recursion
        const subsegments = (
            segment.split_at(0.5) orelse return error.NoSplitForLinearization
        );

        {
            const l_result = try linearize_segment(
                allocator,
                subsegments[0],
                tolerance,
            );
            defer allocator.free(l_result);
            try result.appendSlice(allocator, l_result);
        }

        {
            const r_result = try linearize_segment(
                allocator,
                subsegments[1],
                tolerance,
            );
            defer allocator.free(r_result);
            try result.appendSlice(allocator, r_result[1..]);
        }
    }

    return result.toOwnedSlice(allocator);
}

test "segment: linearize basic test" 
{
    const allocator = std.testing.allocator;

    const segment = try read_segment_json(
        allocator,
        "segments/upside_down_u.json"
    );

    {
        const linearized_knots = try linearize_segment(
            allocator,
            segment,
            0.01,
        );
        defer allocator.free(linearized_knots);
        try std.testing.expectEqual(
            8+1,
            linearized_knots.len,
        );
    }

    {
        const linearized_knots = try linearize_segment(
            allocator,
            segment,
            0.000001,
        );
        defer allocator.free(linearized_knots);
        try std.testing.expectEqual(
            68+1,
            linearized_knots.len,
        );
    }

    {
        const linearized_knots = try linearize_segment(
            allocator,
            segment,
            0.00000001,
        );
        defer allocator.free(linearized_knots);
        try std.testing.expectEqual(
            256+1,
            linearized_knots.len,
        );
    }
}

test "segment from point array" 
{
    const allocator = std.testing.allocator;

    const original_knots_ident: [4]control_point.ControlPoint = .{
        .init(.{ .in = -0.5,     .out = -0.5}),
        .init(.{ .in = -0.16666, .out = -0.16666}),
        .init(.{ .in = 0.166666, .out = 0.16666}),
        .init(.{ .in = 0.5,      .out = 0.5})
    };
    const ident = Bezier.Segment.from_pt_array(original_knots_ident);

    try opentime.expectOrdinateEqual(
        0,
        ident.eval_at(0.5).out,
    );

    const linearized_ident_knots = try linearize_segment(
        allocator,
        ident,
        0.01
    );
    defer allocator.free(linearized_ident_knots);
    try std.testing.expectEqual(
        2,
        linearized_ident_knots.len,
    );

    try opentime.expectOrdinateEqual(
        original_knots_ident[0].in,
        linearized_ident_knots[0].in,
    );
    try opentime.expectOrdinateEqual(
        original_knots_ident[0].out,
        linearized_ident_knots[0].out,
    );

    try opentime.expectOrdinateEqual(
        original_knots_ident[3].in,
        linearized_ident_knots[1].in,
    );
    try opentime.expectOrdinateEqual(
        original_knots_ident[3].out,
        linearized_ident_knots[1].out,
    );
}

test "segment: linearize already linearized curve" 
{
    const allocator = std.testing.allocator;

    const segment = try read_segment_json(
        allocator,
        "segments/linear.json"
    );
    const linearized_knots = try linearize_segment(
        allocator,
        segment,
        0.01
    );
    defer allocator.free(linearized_knots);

    // already linear!
    try std.testing.expectEqual(2, linearized_knots.len);
}

/// Read a Bezier segment from a json file on disk.
pub fn read_segment_json(
    allocator:std.mem.Allocator,
    file_path: []const u8,
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
        BezierF.Segment,
        allocator,
        source,
        .{}
    );
    defer result.deinit();

    return .{
        .p0 = .init(result.value.p0),
        .p1 = .init(result.value.p1),
        .p2 = .init(result.value.p2),
        .p3 = .init(result.value.p3),
    };
}

test "segment: output_at_input and findU test over linear curve" 
{
    const seg = Bezier.Segment.init_from_start_end(
        .init(.{.in = 2, .out = 2}),
        .init(.{.in = 3, .out = 3}),
    );

    for ([_]opentime.Ordinate.InnerType{2.1, 2.2, 2.3, 2.5, 2.7}) 
               |coord| 
    {
        try opentime.expectOrdinateEqual(
            coord,
            seg.output_at_input(coord)
        );
    }
}

test "segment: dual_eval_at over linear curve" 
{
    // identity curve
    {
        const seg = Bezier.Segment.ident_zero_one;

        for ([_]opentime.Ordinate.InnerType{0.2, 0.4, 0.5, 0.98}) 
            |coord| 
        {
            const result = seg.eval_at_dual(
                .init_ri(coord, 1),
            );
            errdefer std.log.err(
                "coord: {any}, result: {any}\n",
                .{ coord, result }
            );
            try opentime.expectOrdinateEqual(
                coord,
                result.r.in,
            );
            try opentime.expectOrdinateEqual(
                coord,
                result.r.out,
            );
            try opentime.expectOrdinateEqual(
                1,
                result.i.in,
            );
            try opentime.expectOrdinateEqual(
                1,
                result.i.out,
            );
        }
    }

    // curve with slope 2
    {
        const seg = Bezier.Segment.init_from_start_end(
            .init(.{ .in = 0, .out = 0 }),
            .init(.{ .in = 1, .out = 2 }),
        );

        inline for (
            [_]opentime.Ordinate{
                .init(0.2),
                .init(0.4),
                .init(0.5),
                .init(0.98),
            }
        ) |coord| 
        {
            const result = seg.eval_at_dual(
                .init_ri(coord, 1)
            );
            errdefer std.log.err(
                "coord: {any}, result: {any}\n",
                .{ coord, result }
            );
            try opentime.expectOrdinateEqual(
                coord,
                result.r.in,
            );
            try opentime.expectOrdinateEqual(
                coord.mul(2),
                result.r.out,
            );
            try opentime.expectOrdinateEqual(
                1,
                result.i.in,
            );
            try opentime.expectOrdinateEqual(
                2,
                result.i.out,
            );
        }
    }
}

test "Bezier.Segment.init_identity check cubic spline" 
{
    // ensure that points are along line even for linear case
    const seg = Bezier.Segment.ident_zero_one;

    try opentime.expectOrdinateEqual(0, seg.p0.in);
    try opentime.expectOrdinateEqual(0, seg.p0.out);
    try opentime.expectOrdinateEqual(1.0/3.0, seg.p1.in);
    try opentime.expectOrdinateEqual(1.0/3.0, seg.p1.out);
    try opentime.expectOrdinateEqual(2.0/3.0, seg.p2.in);
    try opentime.expectOrdinateEqual(2.0/3.0, seg.p2.out);
    try opentime.expectOrdinateEqual(1, seg.p3.in);
    try opentime.expectOrdinateEqual(1, seg.p3.out);
}

/// A sequence of 2d cubic right met bezier segments.
///
/// The evaluation of a Bezier (S0, S1, ... Sn) at t, is therefore t if t <
/// S0.p0.in or t >= S0.p3.in. Otherwise, the segment S whose interval
/// [S.p0.in, S.p3.in) contains t is evaluated according to the cubic Bezier
/// equations.
pub const Bezier = struct {
    /// Bezier segments that compose the curve.
    segments: []const Segment,

    pub const empty: Bezier = .{ .segments = &.{} };

    pub const Segment = struct {
        p0: control_point.ControlPoint,
        p1: control_point.ControlPoint,
        p2: control_point.ControlPoint,
        p3: control_point.ControlPoint,

        pub const ident_zero_one = Segment.init_identity(
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
        );

        pub fn init_f32(
            in_seg : struct{
                p0: control_point.ControlPoint_InnerType,
                p1: control_point.ControlPoint_InnerType,
                p2: control_point.ControlPoint_InnerType,
                p3: control_point.ControlPoint_InnerType,
            },
        ) Segment
        {
            return .{
                .p0 = .init(in_seg.p0),
                .p1 = .init(in_seg.p1),
                .p2 = .init(in_seg.p2),
                .p3 = .init(in_seg.p3),
            };
        }

        pub fn init_identity(
            input_start: opentime.Ordinate,
            input_end: opentime.Ordinate,
        ) Segment
        {
            return Segment.init_from_start_end(
                .{
                    .in = input_start,
                    .out = input_start,
                },
                .{
                    .in = input_end,
                    .out = input_end,
                }
            );
        }

        pub fn init_from_start_end(
            start: control_point.ControlPoint,
            end: control_point.ControlPoint
        ) Segment 
        {
            if (end.in.gteq(start.in))
            {
                return .{
                    .p0 = start,
                    .p1 = opentime.lerp(1.0/3.0, start, end),
                    .p2 = opentime.lerp(2.0/3.0, start, end),
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
            t_mid_point: U_TYPE,
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

        /// Evaluate the segment with implicit differentiation.
        pub fn eval_at_dual(
            self: @This(),
            unorm_dual: opentime.Dual_Ord,
        ) control_point.Dual_CP
        {
            var self_dual : [4]control_point.Dual_CP = undefined;
            const self_p = self.points();

            inline for (self_p, &self_dual) 
                |p, *dual_p| 
            {
                dual_p.* = control_point.Dual_CP.init(p);
            }

            const seg3 = math.segment_reduce4_dual(unorm_dual, self_dual);
            const seg2 = math.segment_reduce3_dual(unorm_dual, seg3);
            const result = math.segment_reduce2_dual(unorm_dual, seg2);

            return result[0];
        }

        /// Compute the point on the curve for parameter unorm along the curve
        /// [0, 1).
        pub inline fn eval_at(
            self: @This(),
            unorm: anytype,
        ) control_point.ControlPoint
        {
            return switch (@TypeOf(unorm)) {
                opentime.Ordinate => self.eval_at_ord(unorm),
                else => self.eval_at_ord(opentime.Ordinate.init(unorm)),
            };
        }

        /// output value of the segment at parameter unorm, [0, 1)
        pub fn eval_at_ord(
            self: @This(),
            unorm: opentime.Ordinate,
        ) control_point.ControlPoint
        {
            const seg3 = math.segment_reduce4(unorm, self);
            const seg2 = math.segment_reduce3(unorm, seg3);
            const result = math.segment_reduce2(unorm, seg2);
            return result.p0;
        }

        /// return the segment split at u [0, 1.0)
        /// note: u of < 0 or >= 1 will result in a null result, no split
        pub fn split_at(
            self: @This(),
            unorm:U_TYPE,
        ) ?[2]Segment 
        {
            if (unorm < epsilon or unorm >= 1)
            {
                return null;
            }

            const p = self.points();

            const Q0 = self.p0;
            const Q1 = opentime.lerp(
                unorm,
                p[0],
                p[1],
            );
            const Q2 = opentime.lerp(
                unorm,
                Q1,
                opentime.lerp(unorm, p[1], p[2]),
            );
            const Q3 = opentime.lerp(
                unorm,
                Q2,
                opentime.lerp(
                    unorm,
                    opentime.lerp(unorm, p[1], p[2]),
                    opentime.lerp(unorm, p[2], p[3]),
                ),
            );

            const R0 = Q3;
            const R2 = opentime.lerp(unorm, p[2], p[3]);
            const R1 = opentime.lerp(
                unorm,
                opentime.lerp(unorm, p[1], p[2]), 
                R2,
            );
            const R3 = p[3];

            return .{
                Segment{ 
                    .p0 = Q0,
                    .p1 = Q1,
                    .p2 = Q2,
                    .p3 = Q3,
                },
                Segment{
                    .p0 = R0,
                    .p1 = R1,
                    .p2 = R2,
                    .p3 = R3,
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
            self: @This(),
        ) [2]control_point.ControlPoint 
        {
            var min: control_point.ControlPoint = self.p0;
            var max: control_point.ControlPoint = self.p0;

            inline for ([3][]const u8{"p1", "p2", "p3"}) 
                |field| 
            {
                const pt = @field(self, field);
                min = .{
                    .in = opentime.min(min.in, pt.in),
                    .out = opentime.min(min.out, pt.out),
                };
                max = .{
                    .in = opentime.max(max.in, pt.in),
                    .out = opentime.max(max.out, pt.out),
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
                other_extents[0].out.gteq(
                    my_extents[0].in.sub(opentime.Ordinate.epsilon)
                )
                and other_extents[1].out.lt(
                    my_extents[1].in.add(opentime.Ordinate.epsilon)
                )
            );
        }

        /// Assuming that segment_to_project is contained by self, project the 
        /// points of segment_to_project through self.
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
        ) U_TYPE
        {
            return math.findU(
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
            return math.findU_dual(
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
        ) U_TYPE
        {
            return math.findU(
                input_ordinate,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in,
            );
        }

        pub fn findU_input_dual(
            self:@This(),
            input_ordinate: opentime.Ordinate,
        ) opentime.Dual_Ord 
        {
            return math.findU_dual(
                input_ordinate,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in,
            );
        }

        pub inline fn output_at_input(
            self: @This(),
            input:anytype,
        ) opentime.Ordinate 
        {
            return self.output_at_input_ord(
                switch (@TypeOf(input)) {
                    opentime.Ordinate => input,
                    else => opentime.Ordinate.init(input),
                }
            );
        }

        /// returns the output value for the given input ordinate
        pub fn output_at_input_ord(
            self: @This(),
            input_ord: opentime.Ordinate,
        ) opentime.Ordinate 
        {
            const u:U_TYPE = math.findU(
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
            x: opentime.Ordinate,
        ) control_point.Dual_CP 
        {
            const u = math.findU_dual(
                x,
                self.p0.in,
                self.p1.in,
                self.p2.in,
                self.p3.in,
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
                self.p0.in.as(f32), self.p0.out.as(f32),
                self.p1.in.as(f32), self.p1.out.as(f32),
                self.p2.in.as(f32), self.p2.out.as(f32),
                self.p3.in.as(f32), self.p3.out.as(f32),
            }
            );
        }

        pub fn debug_print_json(
            self: @This(),
            allocator: std.mem.Allocator,
        ) !void 
        {
            std.log.debug("\ndebug_print_json] p0: {}\n", .{ self.p0});

            const blob = try self.debug_json_str(allocator);
            defer allocator.free(blob);

            std.log.debug("{s}", .{ blob });
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
                        tmp[pt_ind] = .{
                            .x = pt.in.as(f32),
                            .y = pt.out.as(f32),
                        };
                    }

                    break :translate tmp;
                },
            };
        }

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) !void 
        {
            try writer.print("Bezier.Segment{{\n", .{});

            inline for (self.points(), 0..)
                |p, ind|
            {
                if (ind > 0)
                {
                    try writer.print(",\n", .{});
                }
                try writer.print("      {f}", .{p});
            }

            try writer.print("\n    }}", .{});
        }
    };

    /// dupe the segments argument into the returned object
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator
    ) void 
    {
        allocator.free(self.segments);
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
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
        return Bezier{
            .segments = try allocator.dupe(
                Segment,
                &.{ .init_from_start_end(p0, p1) }
            ),
        };
    }

    /// convert a linear curve into a bezier one
    pub fn init_from_linear_curve(
        allocator:std.mem.Allocator,
        crv: linear_curve.Linear,
    ) !Bezier 
    {
        var result: std.ArrayList(Segment) = .{};
        result.deinit(allocator);

        const knots = crv.knots.len;

        for (crv.knots[0..knots-1], crv.knots[1..]) 
            |knot, next_knot| 
        {
            try result.append(
                allocator,
                Segment.init_from_start_end(knot, next_knot),
            );
        }

        return Bezier{
            .segments = try result.toOwnedSlice(allocator),
        };
    }

    pub inline fn output_at_input(
        self: @This(),
        input_space_ord: anytype,
    ) error{OutOfBounds}!opentime.Ordinate 
    {
        return self.output_at_input_ord(
            switch (@TypeOf(input_space_ord)) {
                opentime.Ordinate => input_space_ord,
                else => opentime.Ordinate.init(input_space_ord),
            }
        );
    }

    /// output_at_input the curve at ordinate t in the input space
    pub fn output_at_input_ord(
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
        const input_start = (
            self.segments[0].p0.in.sub(opentime.Ordinate.epsilon)
        );
        const last_seg = self.segments[self.segments.len - 1];
        const input_end = last_seg.p3.in.sub(opentime.Ordinate.epsilon);

        // @TODO: should this be inclusive of the endpoint?
        if (
            self.segments.len == 0 
            or ord_input.lt(input_start)
            or ord_input.gt(input_end)
        )
        {
            return null;
        }

        // quick check if it is exactly the start ordinate of the first segment
        if (ord_input.lt(input_start)) {
            return 0;
        }

        for (self.segments, 0..) 
            |seg, index| 
        {
            if (
                seg.p0.in.lteq(ord_input.add(opentime.Ordinate.epsilon))
                and ord_input.lteq(seg.p3.in.sub(opentime.Ordinate.epsilon))
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
    ) ?*const Segment 
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
        var linearized_knots: std.ArrayList(control_point.ControlPoint) = .{};

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
            if (seg_ind > 0) 
            {
                start_knot = 1;
            }

            // @TODO: expose the tolerance as a parameter(?)
            const subseg = try linearize_segment(
                allocator,
                seg,
                0.000001,
            );
            defer allocator.free(subseg);

            try linearized_knots.appendSlice(
                allocator,
                // first knot of all interior segments should match the 
                // last knot of the previous segment, so can be skipped
                subseg[start_knot..],
            );
        }

        return .{
            .knots = (
                try linearized_knots.toOwnedSlice(allocator)
            ),
        };
    }

    /// compute an array of all the segment endpoints
    pub fn segment_endpoints(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]control_point.ControlPoint 
    {
        var result: std.ArrayList(control_point.ControlPoint) = .{};

        if (self.segments.len == 0) {
            return &[0]control_point.ControlPoint{};
        }

        try result.append(allocator, self.segments[0].p0);
        for (self.segments) 
            |seg| 
        {
            try result.append(allocator, seg.p3);
        }

        return try result.toOwnedSlice(allocator);
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
            self.segments,
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
        allocator: std.mem.Allocator,
    ) ![]const u8
    {
        var writer = std.Io.Writer.Allocating.init(allocator);

        try std.json.Stringify.value(
            self,
            .{},
            &writer.writer,
        );
        return writer.toOwnedSlice();
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
                .in = opentime.min(min.in, seg_extents[0].in),
                .out = opentime.min(min.out, seg_extents[0].out),
            };
            max = .{
                .in = opentime.max(min.in, seg_extents[1].in),
                .out = opentime.max(min.out, seg_extents[1].out),
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
    pub fn split_at_input_ord(
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
            unorm < opentime.EPSILON_F
            or opentime.EPSILON_F > opentime.abs(1 - unorm) 
        ) {
            return .{ 
                .segments = try allocator.dupe(
                    Segment,
                    self.segments,
                ) 
            };
        }

        const maybe_split_segments = seg_to_split.split_at(unorm);

        if (maybe_split_segments == null) 
        {
            std.log.err(
                "ordinate: {f} unorm: {} seg_to_split: {s}\n",
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
        var result_segments: std.ArrayList(Segment) = .{};
        defer result_segments.deinit(allocator);
        try result_segments.appendSlice(allocator, self.segments);

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
                    if (u > 0 + 0.000001 and u < 1 - 0.000001) 
                    {
                        const maybe_split_segments = seg.split_at(u);

                        if (maybe_split_segments) 
                            |split_segments| 
                        {
                            try result_segments.insertSlice(
                                allocator,
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
            .segments = try result_segments.toOwnedSlice(allocator),
        };
    }

    pub fn split_at_each_input_ordinate(
        self:@This(),
        allocator: std.mem.Allocator,
        ordinates:[]const opentime.Ordinate,
    ) !Bezier 
    {
        var result_segments: std.ArrayList(Segment) = .{};
        defer result_segments.deinit(allocator);

        try result_segments.appendSlice(allocator, self.segments);

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
                            allocator,
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

        return .{
            .segments = try result_segments.toOwnedSlice(allocator),
        };
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
             self.extents_input().start.gteq(ordinate)
             and direction == .trim_before
            )
            or
            (
             self.extents_input().end.lteq(ordinate)
             and direction == .trim_after
            )
        ) 
        {
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
                seg_to_split.p0.in.eql_approx(ordinate)
                or seg_to_split.p3.in.eql_approx(ordinate)
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
            return .empty;
        }
        const split_segments = maybe_split_segments.?;

        const result = result: switch (direction) {
            // keep later stuff
            .trim_before => {
                const new_split = split_segments[1];
                const segments_to_copy = self.segments[seg_to_split_index+1..];

                var new_segments = try allocator.alloc(
                    Segment,
                    segments_to_copy.len + 1
                );

                new_segments[0] = new_split;
                std.mem.copyForwards(
                    Segment,
                    new_segments[1..],
                    segments_to_copy
                );

                break :result new_segments;
            },
            // keep earlier stuff
            .trim_after => {
                const new_split = split_segments[0];
                const segments_to_copy = self.segments[0..seg_to_split_index];

                var new_segments = try allocator.alloc(
                    Segment,
                    segments_to_copy.len + 1
                );

                std.mem.copyForwards(
                    Segment,
                    new_segments[0..segments_to_copy.len],
                    segments_to_copy
                );
                new_segments[new_segments.len - 1] = new_split;

                break :result new_segments;
            },
        };

        return .{ .segments = result };
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

        var split_segments: std.ArrayList(Segment) = .{};
        defer split_segments.deinit(allocator);

        for (self.segments) 
            |seg| 
        {
            // build the segment to pass into the C library
            for (seg.points(), &cSeg.p) 
                |pt, *p| 
            {
                p.x = pt.in.as(@TypeOf(p.x));
                p.y = pt.out.as(@TypeOf(p.y));
            }

            var hodo = hodographs.compute_hodograph(&cSeg);
            const roots = hodographs.bezier_roots(&hodo);
            const inflections = hodographs.inflection_points(&cSeg);

            //-----------------------------------------------------------------
            // compute splits
            //-----------------------------------------------------------------
            var splits:[3]opentime.Ordinate.InnerType = .{ 1,1,1 };

            var split_count:usize = 0;

            const possible_splits:[3]opentime.Ordinate.InnerType = .{
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
                            opentime.abs(splits[s_i] - possible_split) 
                            < epsilon
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

            std.mem.sort(
                opentime.Ordinate.InnerType,
                &splits,
                {},
                std.sort.asc(opentime.Ordinate.InnerType),
            );

            var current_seg = seg;

            for (0..split_count) 
                |i| 
            {
                const pt = seg.eval_at(splits[i]);
                const u = current_seg.findU_input(pt.in);

                // @TODO: question - should the "U" in the bezier be a phase
                //        ordinate?
                const maybe_xsplits = current_seg.split_at(u);

                if (maybe_xsplits) 
                    |xsplits| 
                {
                    try split_segments.append(allocator,xsplits[0]);
                    current_seg = xsplits[1];
                }
            }
            try split_segments.append(allocator,current_seg);
        }

        return .{
            .segments = try split_segments.toOwnedSlice(allocator),
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print("Bezier{{\n  .segments: [\n", .{});

        for (self.segments, 0..)
            |s, ind|
        {
            if (ind > 0)
            {
                try writer.print(",\n", .{});
            }
            try writer.print("    {f}", .{ s});
        }

        try writer.print("\n  ]\n}}", .{});
    }
};

/// Parse a .curve.json file from disk and return a Bezier.
pub fn read_curve_json(
    allocator:std.mem.Allocator,
    file_path: []const u8,
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

/// Intermediate type that unboxes the ordinate for a convenient json format.
const BezierF = struct {
    const ControlPointType = control_point.ControlPoint_InnerType;
    const Segment = struct {
        p0 : ControlPointType,
        p1 : ControlPointType,
        p2 : ControlPointType,
        p3 : ControlPointType,
    };
    segments: []const Segment,
};

/// Parse curve json text and build a `Bezier`.
pub fn read_bezier_curve_data(
    allocator: std.mem.Allocator,
    /// Source text containing curve json.
    source: []const u8,
) !Bezier
{
    // parse float form
    const b_f = try std.json.parseFromSliceLeaky(
        BezierF,
        allocator,
        source,
        .{}
    );
    defer allocator.free(b_f.segments);

    const result_segments = try allocator.alloc(
        Bezier.Segment,
        b_f.segments.len,
    );

    for (b_f.segments, result_segments)
        |src_seg, *dst_seg|
    {
        dst_seg.* = .{
            .p0 = .init(src_seg.p0),
            .p1 = .init(src_seg.p1),
            .p2 = .init(src_seg.p2),
            .p3 = .init(src_seg.p3),
        };
    }

    return .{ .segments = result_segments, };
}

/// Inner function that reads linear curve knots from the json
fn read_linear_curve_data(
    allocator: std.mem.Allocator,
    source: []const u8,
) !Bezier
{
    const lin_curve = try std.json.parseFromSliceLeaky(
        linear_curve.LinearF,
        allocator,
        source, 
        .{},
    );

    const out_knots = try allocator.alloc(
        control_point.ControlPoint,
        lin_curve.knots.len,
    );

    for (lin_curve.knots, out_knots)
        |src_knot, *dst_knot|
    {
        dst_knot.* = .init(src_knot);
    }

    return try Bezier.init_from_linear_curve(
        allocator,
        .{
            .knots = out_knots,
        },
    );
}

test "Curve: read_curve_json" 
{
    const allocator = std.testing.allocator;

    const curve = try read_curve_json(
        allocator,
        "curves/linear.curve.json",
    );
    defer curve.deinit(allocator);

    try std.testing.expectEqual(1, curve.segments.len);

    // first segment should already be linear
    const segment = curve.segments[0];

    const linearized_knots = try linearize_segment(
        allocator,
        segment,
        0.01
    );
    defer allocator.free(linearized_knots);

    // already linear!
    try std.testing.expectEqual(2, linearized_knots.len);
    try std.testing.expectEqualSlices(
        control_point.ControlPoint,
        &[_]control_point.ControlPoint{
            .init(.{ .in = -0.5, .out = -0.5 }),
            .init(.{ .in =  0.5, .out =  0.5 }),
        },
        linearized_knots,
    );
}

test "Bezier.Segment: projected_segment to 1/2" 
{
    {
        const half = Bezier.Segment.init_from_start_end(
            .init(.{ .in = -0.5, .out = -0.25, }),
            .init(.{ .in = 0.5, .out = 0.25, }),
        );
        const double = Bezier.Segment.init_from_start_end(
            .init(.{ .in = -0.5, .out = -1, }),
            .init(.{ .in = 0.5, .out = 1, }),
        );

        const half_through_double = double.project_segment(half);

        var u:U_TYPE = 0;
        while (u<1) 
            : (u += 0.01)
        {
            try opentime.expectOrdinateEqual(
                // t at u = 0 is -0.5
                u-0.5,
                half_through_double.eval_at(u).out
            );
        }
    }

    {
        const half = Bezier.Segment.init_from_start_end(
            .init(.{ .in = -0.5, .out = -0.5, }),
            .init(.{ .in = 0.5, .out = 0.0, }),
        );
        const double = Bezier.Segment.init_from_start_end(
            .init(.{ .in = -0.5, .out = -0.5, }),
            .init(.{ .in = 0.5, .out = 1.5, }),
        );

        const half_through_double = double.project_segment(half);

        var u:U_TYPE = 0;
        while (u<1) 
            : (u += 0.01)
        {
            try opentime.expectOrdinateEqual(
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
            .init(.{ .in = 1, .out = 0, }),
            .init(.{ .in = 2, .out = 1, }),
        )
    };
    const xform_curve: Bezier = .{ .segments = &crv_seg, };

    // out of range returns error.OutOfBounds
    try std.testing.expectError(
        error.OutOfBounds,
        xform_curve.output_at_input(2),
    );
    try std.testing.expectError(
        error.OutOfBounds,
        xform_curve.output_at_input(3),
    );
    try std.testing.expectError(
        error.OutOfBounds,
        xform_curve.output_at_input(0),
    );

    // find segment
    try std.testing.expect(
        xform_curve.find_segment(opentime.Ordinate.init(1)) != null
    );
    try std.testing.expect(
        xform_curve.find_segment(opentime.Ordinate.init(1.5)) != null
    );
    try std.testing.expectEqual(
        null,
        xform_curve.find_segment(opentime.Ordinate.init(2)),
    );

    // within the range of the curve
    try opentime.expectOrdinateEqual(
        0,
        try xform_curve.output_at_input(1),
    );
    try opentime.expectOrdinateEqual(
        0.25,
        try xform_curve.output_at_input(1.25),
    );
    try opentime.expectOrdinateEqual(
        0.5,
        try xform_curve.output_at_input(1.5),
    );
    try opentime.expectOrdinateEqual(
        0.75,
        try xform_curve.output_at_input(1.75),
    );
}

test "positive slope 2 linear segment test" 
{
    var test_segment_arr = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .init(.{ .in = 1, .out = 0, }),
            .init(.{ .in = 2, .out = 2, }),
        )
    };
    const xform_curve = Bezier{ .segments = &test_segment_arr };

    const tests = &.{
        // std.testing.expect result
        .{ 0,   1   },
        .{ 0.5, 1.25},
        .{ 1,   1.5 },
        .{ 1.5, 1.75},
    };

    inline for (tests) 
        |t| 
    {
        try opentime.expectOrdinateEqual(
            t[0],
            try xform_curve.output_at_input(t[1]),
        );
    }
}

test "negative length 1 linear segment test" 
{
    // declaring the segment here means that the memory management is handled
    // by stack unwinding
    var segments_xform = [_]Bezier.Segment{
        Bezier.Segment.init_from_start_end(
            .init(.{ .in = -2, .out = 0, }),
            .init(.{ .in = -1, .out = 1, }),
        )
    };
    const xform_curve = Bezier{ .segments = &segments_xform };

    // outside of the range should return the original result
    // (identity transform)
    try std.testing.expectError(
        error.OutOfBounds,
        xform_curve.output_at_input(0),
    );
    try std.testing.expectError(
        error.OutOfBounds,
        xform_curve.output_at_input(-3),
    );
    try std.testing.expectError(
        error.OutOfBounds,
        xform_curve.output_at_input(-1),
    );

    // within the range
    try opentime.expectOrdinateEqual(
        0,
        try xform_curve.output_at_input(-2),
    );
    try opentime.expectOrdinateEqual(
        0.5,
        try xform_curve.output_at_input(-1.5),
    );
}

test "Bezier.Segment: eval_at for out of range u" 
{
    var seg = [1]Bezier.Segment{
        Bezier.Segment.init_identity(
            opentime.Ordinate.init(3),
            opentime.Ordinate.init(4),
        ),
    };
    const tc = Bezier{ .segments = &seg};

    try std.testing.expectError(
        error.OutOfBounds,
        tc.output_at_input(0),
    );

    // right open intervals means the end point is out
    try std.testing.expectError(
        error.OutOfBounds,
        tc.output_at_input(4),
    );

    try std.testing.expectError(
        error.OutOfBounds,
        tc.output_at_input(5),
    );
}

fn write_text_to_file(
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

    try write_text_to_file(
        json_blob,
        to_fpath,
    );
}

test "json writer: curve" 
{
    const allocator = std.testing.allocator;

    const ident = Bezier {
        .segments = &.{
            .init_identity(.init(-20), .init(30),)
        },
    };

    const fpath = "/var/tmp/test.curve.json";

    try write_json_file_curve(
        allocator,
        ident,
        fpath,
    );

    const file = try std.fs.cwd().openFile(
        fpath,
        .{ .mode = .read_only },
    );
    defer file.close();

    var buffer: [2048]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);

    const blob = try ident.debug_json_str(allocator);
    defer allocator.free(blob);

    try std.testing.expectEqualStrings(
        buffer[0..bytes_read],
        blob,
    );
}

test "segment: findU_value" 
{
    const test_segment = Bezier.Segment.init_identity(
        opentime.Ordinate.init(1),
        opentime.Ordinate.init(2),
    );
    try std.testing.expectApproxEqAbs(
        0.5,
        test_segment.findU_value(opentime.Ordinate.init(1.5)),
        opentime.EPSILON_F,
    );
    try std.testing.expectApproxEqAbs(
        0,
        test_segment.findU_value(opentime.Ordinate.init(0.5)),
        opentime.EPSILON_F,
    );
    try std.testing.expectApproxEqAbs(
        1,
        test_segment.findU_value(opentime.Ordinate.init(2.5)),
        opentime.EPSILON_F,
    );
}

test "Bezier: split_at_each_value u curve" 
{
    const allocator = std.testing.allocator;

    const upside_down_u = Bezier {
        .segments = &.{
            .init_f32(
                .{
                    .p0 = .{ .in = 0, .out = 0 },
                    .p1 = .{ .in = 0, .out = 100 },
                    .p2 = .{ .in = 100, .out = 100 },
                    .p3 = .{ .in = 100, .out = 0 },
                }
            ),
        },
    };
    const u_seg = upside_down_u.segments[0];

    const upside_down_u_hodo = try upside_down_u.split_on_critical_points(
        allocator
    );
    defer upside_down_u_hodo.deinit(allocator);

    const split_points = [_]opentime.Ordinate{
        u_seg.eval_at(0).out, 
        u_seg.eval_at(0.5).out, 
        u_seg.eval_at(0.75).out, 
        u_seg.eval_at(0.88).out, 
        u_seg.eval_at(1).out, 
    };

    const result = try upside_down_u_hodo.split_at_each_output_ordinate(
        allocator,
        &split_points,
    );
    defer result.deinit(allocator);

    const endpoints = try result.segment_endpoints(
        allocator
    );
    defer allocator.free(endpoints);

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
                    opentime.Ordinate.InnerType,
                    sp_p.as(opentime.Ordinate.InnerType),
                    pt.out.as(opentime.Ordinate.InnerType),
                    0.00001
                )
            ) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try std.testing.expectEqual(@as(usize, 4), result.segments.len);
}

test "Bezier: split_at_each_value linear" 
{
    const allocator = std.testing.allocator;

    const lin = Bezier {
        .segments = &.{
            .init_identity(.init(-0.2), .init(1),)
        },
    };

    const split_points = [_]opentime.Ordinate{ 
        opentime.Ordinate.init(-0.2),
        opentime.Ordinate.init(0),
        opentime.Ordinate.init(0.5),
        opentime.Ordinate.init(1),
    };

    const result = try lin.split_at_each_output_ordinate(
        allocator,
        &split_points,
    );
    defer result.deinit(allocator);

    var fbuf: [1024]opentime.Ordinate = undefined;
    const endpoints_cp = try result.segment_endpoints(
        allocator
    );
    defer allocator.free(endpoints_cp);
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
            if (
                std.math.approxEqAbs(
                    opentime.Ordinate.InnerType,
                    sp_p.as(opentime.Ordinate.InnerType),
                    pt.as(opentime.Ordinate.InnerType),
                    0.00001,
                )
            )
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try std.testing.expectEqual(3, result.segments.len);
}

test "Bezier: split_at_each_input_ordinate linear" 
{
    const allocator = std.testing.allocator;

    const lin = Bezier {
        .segments = &.{
            .init_identity( .init(-0.2), .one,)
        },
    };

    const split_points = [_]opentime.Ordinate{ 
        .init(-0.2),
        .init(0),
        .init(0.5),
        .init(1),
    };

    const result = try lin.split_at_each_input_ordinate(
        allocator,
        &split_points,
    );
    defer result.deinit(allocator);

    var fbuf: [1024]opentime.Ordinate = undefined;
    const endpoints_cp = try result.segment_endpoints(
        allocator
    );
    defer allocator.free(endpoints_cp);

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
            if (
                std.math.approxEqAbs(
                    opentime.Ordinate.InnerType,
                    sp_p.as(opentime.Ordinate.InnerType),
                    pt.as(opentime.Ordinate.InnerType),
                    0.00001,
                )
            ) 
            {
                found = true;
            }
        }

        try std.testing.expect(found);
    }

    try std.testing.expectEqual(@as(usize, 3), result.segments.len);
}

test "Bezier: split_at_input_ord" 
{
    const allocator = std.testing.allocator;

    const test_curves = [_]Bezier{
        .{
            .segments = &.{
                .init_identity(
                    opentime.Ordinate.init(-20),
                    opentime.Ordinate.init(30),
                ) 
            },
        },
        try read_curve_json(
            allocator,
            "curves/upside_down_u.curve.json",
        ), 
        try read_curve_json(
            allocator,
            "curves/scurve.curve.json",
        ), 
    };
    defer test_curves[1].deinit(allocator);
    defer test_curves[2].deinit(allocator);

    for (test_curves, 0..) 
        |ident, loop| 
    {
        const extents = ident.extents();
        var split_loc = (
            extents[0].in.as(opentime.Ordinate.InnerType) + 1
        );

        while (split_loc < extents[1].in.as(opentime.Ordinate.InnerType)) 
            : (split_loc += 1) 
        {
            errdefer std.log.err(
                "loop_index: {} extents: {any}, split_loc: {} curve: {!s}\n",
                .{
                    loop, extents, split_loc, ident.debug_json_str(allocator)
                }
            );
            const split_ident = try ident.split_at_input_ord(
                allocator,
                opentime.Ordinate.init(split_loc),
            );
            defer split_ident.deinit(allocator);

            try std.testing.expectEqual(
                ident.segments.len + 1,
                split_ident.segments.len
            );

            // check that the end points are the same
            try std.testing.expectEqual(
                ident.segments[0].p0.in,
                split_ident.segments[0].p0.in
            );
            try std.testing.expectEqual(
                ident.segments[0].p3.in,
                split_ident.segments[1].p3.in
            );

            var i:opentime.Ordinate = extents[0].in;
            while (i.lt(extents[1].in))
                : (i = i.add(1))
            {
                const fst = try ident.output_at_input(i);
                const snd = try split_ident.output_at_input(i);
                errdefer std.log.err(
                    "Loop: {d} orig: {f} new: {f}",
                    .{i, fst, snd}
                );
                try opentime.expectOrdinateEqual(
                    fst,
                    snd,
                );
            }
        }
    }
}

test "Bezier: trimmed_from_input_ordinate" 
{
    const allocator = std.testing.allocator;

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
            allocator,
            "curves/linear_scurve_u.curve.json",
        ), 
        .{
            .segments = &.{
                Bezier.Segment.init_identity(
                    opentime.Ordinate.init(-25),
                    opentime.Ordinate.init(-5),
                ), 
                Bezier.Segment.init_identity(
                    opentime.Ordinate.init(-5),
                    opentime.Ordinate.init(5),
                ), 
                Bezier.Segment.init_identity(
                    opentime.Ordinate.init(5),
                    opentime.Ordinate.init(25),
                ), 
            },
        },
    };

    defer test_curves[0].deinit(allocator);

    for (test_curves, 0..) 
        |ident, curve_index| 
    {
        const extents = ident.extents();

        // assumes that curve is 0-centered
        const test_data = [_]TestData{
            // trim the first segment
            .{
                .ordinate = extents[0].in.mul(0.25),
                .direction = .trim_before,
                .result_extents = .{
                    .start = extents[0].in.mul(0.25),
                    .end = extents[1].in,
                },
                .result_segment_count = ident.segments.len,
            },
            .{
                .ordinate = extents[0].in.mul(0.25),
                .direction = .trim_after,
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[0].in.mul(0.25),
                },
                .result_segment_count = 1,
            },
            // trim the last segment
            .{
                .ordinate = extents[1].in.mul(0.75),
                .direction = .trim_before,
                .result_extents = .{
                    .start = extents[1].in.mul(0.75),
                    .end = extents[1].in,
                },
                .result_segment_count = 1,
            },
            .{
                .ordinate = extents[1].in.mul(0.75),
                .direction = .trim_after,
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in.mul(0.75),
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
                allocator,
                td.ordinate,
                td.direction,
            );
            const trimmed_extents = trimmed_curve.extents();
            defer trimmed_curve.deinit(allocator);

            errdefer std.debug.print(
                "\n test: {any}\n trimmed_extents: {any} \n\n",
                .{ td , trimmed_extents}
            );

            try opentime.expectOrdinateEqual(
                td.result_extents.start,
                trimmed_extents[0].in,
            );
            try opentime.expectOrdinateEqual(
                td.result_extents.end,
                trimmed_extents[1].in,
            );
        }
    }
}

test "Bezier: trimmed_in_input_space" 
{
    const allocator = std.testing.allocator;

    const TestData = struct {
        trim_range: opentime.ContinuousInterval,
        result_extents: opentime.ContinuousInterval,
    };

    const test_curves = [_]Bezier{
        .{
            .segments = &.{
                .init_identity(
                    opentime.Ordinate.init(-20),
                    opentime.Ordinate.init(30),
                ) 
            }
        },
        try read_curve_json(
            allocator,
            "curves/upside_down_u.curve.json",
        ), 
        try read_curve_json(
            allocator,
            "curves/scurve.curve.json",
        ), 
    };

    defer test_curves[1].deinit(allocator);
    defer test_curves[2].deinit(allocator);

    for (test_curves, 0..) 
        |ident, crv_ind|
    {
        const extents = ident.extents();

        const test_data = [_]TestData{
            // trim both
            .{
                .trim_range = .{
                    .start = extents[0].in.mul(0.25),
                    .end = extents[1].in.mul(0.75),
                },
                .result_extents = .{
                    .start = extents[0].in.mul(0.25),
                    .end = extents[1].in.mul(0.75),
                },
                },
            // trim start
            .{
                .trim_range = .{
                    .start = extents[0].in.mul(0.25),
                    .end = extents[1].in.mul(1.75),
                },
                .result_extents = .{
                    .start = extents[0].in.mul(0.25),
                    .end = extents[1].in,
                },
                },
            // trim end
            .{
                .trim_range = .{
                    .start = extents[0].in.mul(1.25),
                    .end = extents[1].in.mul(0.75),
                },
                .result_extents = .{
                    .start = extents[0].in,
                    .end = extents[1].in.mul(0.75),
                },
                },
            // trim neither
            .{
                .trim_range = .{
                    .start = extents[0].in.mul(1.25),
                    .end = extents[1].in.mul(1.75),
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
                    allocator
                ) catch "ERRMAKESTRING";
                defer allocator.free(crv_str);
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
                allocator,
                td.trim_range,
            );
            defer trimmed_curve.deinit(allocator);

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

            try opentime.expectOrdinateEqual(
                td.result_extents.start,
                trimmed_extents[0].in,
            );
            try opentime.expectOrdinateEqual(
                td.result_extents.end,
                trimmed_extents[1].in,
            );
        }
    }
}

test "Bezier: project_affine" 
{
    const allocator = std.testing.allocator;

    const test_crv = try read_curve_json(
        allocator,
        "curves/upside_down_u.curve.json",
    );
    defer test_crv.deinit(allocator);

    const test_affine = [_]opentime.transform.AffineTransform1D{
        .{
            .offset = .init(-10),
            .scale = .init(0.5),
        },
        .{
            .offset = .init(0),
            .scale = .init(1),
        },
        .{
            .offset = .init(0),
            .scale = .init(2),
        },
        .{
            .offset = .init(10),
            .scale = .init(1),
        },
    };

    // @TODO: this seems like it could be cleaned up
    for (test_affine) 
        |testdata| 
    {
        const result = try test_crv.project_affine(
            allocator,
            testdata,
        );
        defer result.deinit(allocator);

        // number of segments shouldn't have changed
        try std.testing.expectEqual(
            test_crv.segments.len,
            result.segments.len,
        );

        for (test_crv.segments, 0..) 
            |t_seg, t_seg_index| 
        {
            for (t_seg.points(), 0..) 
                |pt, pt_index| 
            {
                const result_pt = (
                    result.segments[t_seg_index].points()[pt_index]
                );

                errdefer  std.log.err(
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

                try opentime.expectOrdinateEqual(
                    (testdata.scale.mul(pt.in)).add(testdata.offset),
                    result_pt.in,
                );
            }
        }
    }
}

/// Join `args.a2b` (a `Bezier`) with `args.b2c` (an Affine Transform) to
/// create a transformation curve `a2c`.
///
/// Resulting memory is owned by the caller.
pub fn join_bez_aff_unbounded(
    allocator: std.mem.Allocator,
    args: struct {
        a2b: Bezier,
        b2c: opentime.transform.AffineTransform1D,
    },
) !Bezier 
{
    const new_segments = try allocator.alloc(
        Bezier.Segment,
        args.a2b.segments.len,
    );

    for (args.a2b.segments, new_segments) 
        |src_seg, *dst_seg| 
    {
        for (src_seg.points(), dst_seg.point_ptrs()) 
            |pt, dst_pt| 
        {
            dst_pt.* = .{
                .in = pt.in,
                .out = args.b2c.applied_to_ordinate(pt.out),
            };
        }
    }

    return .{
        .segments = new_segments,
    };
}

test "join_bez_aff_unbounded" 
{
    const allocator = std.testing.allocator;

    const test_crv = try read_curve_json(
        allocator,
        "curves/upside_down_u.curve.json",
    );
    defer test_crv.deinit(allocator);

    const test_affine = [_]opentime.transform.AffineTransform1D{
        .{
            .offset = .init(-10),
            .scale = .init(0.5),
        },
        .{
            .offset = .init(0),
            .scale = .init(1),
        },
        .{
            .offset = .init(0),
            .scale = .init(2),
        },
        .{
            .offset = .init(10),
            .scale = .init(1),
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
            allocator,
            .{
                .a2b = test_crv,
                .b2c = testdata,
            },
        );
        defer result.deinit(allocator);

        // number of segments shouldn't have changed
        try std.testing.expectEqual(test_crv.segments.len, result.segments.len);

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
                try opentime.expectOrdinateEqual(
                        testdata.scale.mul(pt.out).add(testdata.offset),
                    result_pt.out
                );
            }
        }
    }
}

test "Bezier: split_on_critical_points s curve" 
{
    const allocator = std.testing.allocator;

    const s_curve_seg = Bezier {
        .segments = &.{
            .init_f32(
                .{
                    .p0 = .{ .in = 0, .out = 0 },
                    .p1 = .{ .in = 0, .out = 200 },
                    .p2 = .{ .in = 100, .out = -100 },
                    .p3 = .{ .in = 100, .out = 100 },
                }
            ),
        },
    };

    const s_curve_split = try s_curve_seg.split_on_critical_points(
        allocator
    );
    defer s_curve_split.deinit(allocator);

    try std.testing.expectEqual(4, s_curve_split.segments.len);
}

test "Bezier: split_on_critical_points symmetric about the origin" 
{
    const allocator = std.testing.allocator;

    const TestData = struct {
        segment: Bezier.Segment,
        inflection_point: opentime.Ordinate,
        roots: [2]opentime.Ordinate,
        split_segments: usize,
    };

    const tests = [_]TestData{
        .{
            .segment = .init_f32(
                .{
                    .p0 = .{ .in = -0.5, .out = -0.5 },
                    .p1 = .{ .in =    0, .out = -0.5 },
                    .p2 = .{ .in =    0, .out =  0.5 },
                    .p3 = .{ .in =  0.5, .out =  0.5 },
                }
            ),
            .inflection_point = .init(0.5),
            .roots = .{
                .init(-1),
                .init(-1), 
            },
            .split_segments = 2,
        },
        .{
            .segment = .init_f32(
                .{
                    .p0 = .{ .in = -0.5, .out =    0 },
                    .p1 = .{ .in =    0, .out =   -1 },
                    .p2 = .{ .in =    0, .out =    1 },
                    .p3 = .{ .in =  0.5, .out =    0 },
                }
            ),
            .inflection_point = .init(0.5),
            // assuming this is correct
            .roots = .{
                .init(0.21132487),
                .init(0.788675129),
            },
            .split_segments = 4,
        },
    };

    for (tests, 0..) 
        |td, td_ind| 
    {
        errdefer std.debug.print("test that failed: {d}\n", .{ td_ind });
        const s_curve_seg = Bezier {
            .segments = &.{ td.segment },
        };
        const seg = s_curve_seg.segments[0];

        const cSeg: hodographs.BezierSegment = .{
            .order = 3,
            .p = .{
                .{ .x = seg.p0.in.as(f32), .y = seg.p0.out.as(f32) },
                .{ .x = seg.p1.in.as(f32), .y = seg.p1.out.as(f32) },
                .{ .x = seg.p2.in.as(f32), .y = seg.p2.out.as(f32) },
                .{ .x = seg.p3.in.as(f32), .y = seg.p3.out.as(f32) },
            },
        };
        const inflections = hodographs.inflection_points(&cSeg);

        try std.testing.expectApproxEqAbs(
            td.inflection_point.as(f32),
            inflections.x,
            opentime.EPSILON_F,
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

            const maybe_zig_splits = seg.split_at(t);

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
                    zig_splits[0].points()[i].in.as(f32),
                    opentime.EPSILON_F,
                );
                try std.testing.expectApproxEqAbs(
                    c_split_l.p[i].y,
                    zig_splits[0].points()[i].out.as(f32),
                    opentime.EPSILON_F,
                );
                try std.testing.expectApproxEqAbs(
                    c_split_r.p[i].x,
                    zig_splits[1].points()[i].in.as(f32),
                    opentime.EPSILON_F,
                );
                try std.testing.expectApproxEqAbs(
                    c_split_r.p[i].y,
                    zig_splits[1].points()[i].out.as(f32),
                    opentime.EPSILON_F,
                );
            }
        }

        const s_curve_split = try s_curve_seg.split_on_critical_points(
            allocator,
        );
        defer s_curve_split.deinit(allocator);

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
                td.roots[0].as(f32),
                roots.x,
                opentime.EPSILON_F
            );
            try std.testing.expectApproxEqAbs(
                td.roots[1].as(f32),
                roots.y,
                opentime.EPSILON_F
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
    t: ?opentime.Ordinate.InnerType = null,
};

/// Plot the "three point approximation" of a bezier spline.
pub fn three_point_guts_plot(
    start_knot: control_point.ControlPoint,
    mid_point: control_point.ControlPoint,
    t_mid_point: U_TYPE,
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
    const C = opentime.lerp(
        1-u,
        start_knot,
        end_knot,
    );
    final_result.C = C;

    // abs( (t^3 + (1-t)^3 - 1) / ( t^3 + (1-t)^3 ) )
    const ratio_t = cmp_t: {
        const result = opentime.abs(
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
        .in= mid_point.in.sub(d_mid_point_dt.in.mul((t_mid_point))),
        .out= mid_point.out.sub(d_mid_point_dt.out.mul((t_mid_point))),
    };
    const e2 = control_point.ControlPoint{
        .in= mid_point.in.add(d_mid_point_dt.in.mul((1-t_mid_point))),
        .out = mid_point.out.add(d_mid_point_dt.out.mul((1-t_mid_point))),
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
