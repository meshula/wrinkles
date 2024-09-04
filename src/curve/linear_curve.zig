//! Linear curves are made of right-met connected line segments

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

const opentime = @import("opentime");

const bezier_curve = @import("bezier_curve.zig");
const bezier_math = @import("bezier_math.zig");
const generic_curve = @import("generic_curve.zig");
const ControlPoint = @import("control_point.zig").ControlPoint;

fn _is_between(
    val: anytype,
    fst: @TypeOf(val),
    snd: @TypeOf(val)
) bool 
{
    return (
        (fst <= val and val < snd) 
        or (fst >= val and val > snd)
    );
}

/// A polyline that is linearly interpolated between knots
pub const Linear = struct {
    knots: []ControlPoint = &.{},

    /// dupe the provided points into the result
    pub fn init(
        allocator: std.mem.Allocator,
        knots: []const ControlPoint
    ) !Linear 
    {
        return Linear{
            .knots = try allocator.dupe(
                ControlPoint,
                knots,
            ) 
        };
    }

    /// initialize an identity Linear with knots at the specified input
    /// ordinates
    pub fn init_identity(
        allocator: std.mem.Allocator,
        knot_input_ords:[]const f32
    ) !Linear 
    {
        var result = std.ArrayList(ControlPoint).init(
            allocator,
        );
        for (knot_input_ords) 
            |t| 
        {
            try result.append(.{.in = t, .out = t});
        }

        return Linear{
            .knots = try result.toOwnedSlice(), 
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        allocator.free(self.knots);
    }

    // @TODO: the same as init
    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator
    ) !Linear
    {
        return .{ 
            .knots = try allocator.dupe(
                ControlPoint,
                self.knots
            ),
        };
    }

    /// trim this curve via the bounds expressed in the input space of this
    /// curve.
    ///
    /// If the curve isn't trimmed, dupe the curve.
    pub fn trimmed_in_input_space(
        self: @This(),
        allocator: std.mem.Allocator,
        input_bounds: opentime.ContinuousTimeInterval,
    ) !Linear
    {
        var result = std.ArrayList(ControlPoint).init(
            allocator
        );
        result.deinit();

        const first_point = ControlPoint{
            .in = input_bounds.start_seconds,
            .out = try self.output_at_input(input_bounds.start_seconds),
        };
        try result.append(first_point);

        
        const last_point = if (
            input_bounds.end_seconds < self.extents()[1].in
        ) ControlPoint{ 
            .in = input_bounds.end_seconds,
            .out = try self.output_at_input(input_bounds.end_seconds),
        } else self.extents()[1];

        for (self.knots) 
            |knot|
        {
            if (
                knot.in > first_point.in
                and knot.in < last_point.in
            ) {
                try result.append(knot);
            }
        }

        try result.append(last_point);

        return Linear{ .knots = try result.toOwnedSlice() };
    }

    /// project an affine transformation through the curve, returning a new
    /// linear curve.  If self maps B->C, and xform maps A->B, then the result
    /// of self.project_affine(xform) will map A->C
    pub fn project_affine(
        self: @This(),
        allocator: std.mem.Allocator,
        other_to_input_xform: opentime.transform.AffineTransform1D,
        /// bounds on the input space of the curve (output space of the affine)
        /// ("B" in the comment above)
        input_bounds: opentime.ContinuousTimeInterval,
    ) !Linear 
    {
        // output bounds of the affine are in the input space of the curve
        const clipped_curve = try self.trimmed_in_input_space(
            allocator,
            input_bounds
        );
        defer clipped_curve.deinit(allocator);

        const result_knots = try allocator.dupe(
            ControlPoint,
            clipped_curve.knots,
        );

        const input_to_other_xform = other_to_input_xform.inverted();

        for (clipped_curve.knots, result_knots) 
            |pt, *target_knot| 
        {
            target_knot.in = input_to_other_xform.applied_to_seconds(pt.in);
        }

        return .{
            .knots = result_knots,
        };
    }

    /// compute the output ordinate at the input ordinate
    pub fn output_at_input(
        self: @This(),
        input_ord: f32,
    ) error{OutOfBounds}!f32 
    {
        if (self.nearest_smaller_knot_index(input_ord)) 
           |index| 
        {
            return bezier_math.output_at_input_between(
                input_ord,
                self.knots[index],
                self.knots[index+1],
            );
        }

        // specially handle the endpoint
        const last_knot = self.knots[self.knots.len - 1];
        if (input_ord == last_knot.in) {
            return last_knot.out;
        }

        return error.OutOfBounds;
    }

    pub fn output_at_input_at_value(
        self: @This(),
        value_ord: f32,
    ) !f32
    {
        if (self.nearest_smaller_knot_index_to_value(value_ord)) 
           |index| 
        {
            return bezier_math.input_at_output_between(
                value_ord,
                self.knots[index],
                self.knots[index+1],
            );
        }

        return error.OutOfBounds;
    }

    pub fn nearest_smaller_knot_index(
        self: @This(),
        t_arg: f32, 
    ) ?usize 
    {
        const last_index = self.knots.len-1;

        // out of bounds
        if (
            self.knots.len == 0 
            or (t_arg < self.knots[0].in)
            or t_arg >= self.knots[last_index].in
        )
        {
            return null;
        }

        // last knot is out of domain
        for (self.knots[0..last_index], self.knots[1..], 0..) 
            |knot, next_knot, index| 
        {
            if ( knot.in <= t_arg and t_arg < next_knot.in) 
            {
                return index;
            }
        }

        return null;
    }

    pub fn nearest_smaller_knot_index_to_value(
        self: @This(),
        value_ord: f32, 
    ) ?usize 
    {
        const last_index = self.knots.len-1;

        // out of bounds
        if (
            self.knots.len == 0 
            or (value_ord < self.knots[0].out)
            or value_ord >= self.knots[last_index].out
        )
        {
            return null;
        }

        // last knot is out of domain
        for (self.knots[0..last_index], self.knots[1..], 0..) 
            |knot, next_knot, index| 
        {
            if ( knot.out <= value_ord and value_ord < next_knot.out) 
            {
                return index;
            }
        }

        return null;
    }

    /// project another curve through this one.  A curve maps 'input' to
    /// 'output' parameters.  if curve self is v_self(t_self), and curve other
    /// is v_other(t_other) and other is being projected through self, the
    /// result function is v_self(v_other(t_other)).  This maps the the v_other
    /// value to the t_self parameter.
    ///
    /// To put it another way, if self maps B->C
    /// (B = t_self, C=v_self)
    /// and other maps A->B
    /// (A = t_other)
    /// then self.project_curve(other): A->C
    /// t_other -> v_self
    /// or if self.input -> self.output
    /// and other.input -> other.output
    /// self.project_topology(other) :: other.input -> self.output
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
        /// curve being projected _through_
        self: @This(),
        allocator: std.mem.Allocator,
        /// curve being projected
        other: Linear
    ) ![]Linear 
    {
        // @TODO: if there are preserved derivatives, project and compose them
        //        as well
        //
        const other_bounds = other.extents();

        // find all knots in self that are within the other bounds
        var split_points = std.ArrayList(f32).init(
            allocator,
        );
        defer split_points.deinit();

        for (self.knots)
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

        const other_split_at_self_knots = try other.split_at_each_value(
            allocator,
            split_points.items
        );

        // split other into curves where it goes in and out of the domain of self
        var curves_to_project = std.ArrayList(
            Linear,
        ).init(allocator);
        defer curves_to_project.deinit();

        // gather the curves to project by splitting
        {
            const self_bounds_t = self.extents_input();
            var last_index:?i32 = null;
            var current_curve = (
                std.ArrayList(ControlPoint).init(
                    allocator,
                )
            );

            for (other_split_at_self_knots.knots, 0..) 
                |other_knot, index| 
            {
                if (
                    self_bounds_t.start_seconds <= other_knot.out 
                    and other_knot.out <= self_bounds_t.end_seconds
                ) 
                {
                    if (last_index == null or index != last_index.?+1) 
                    {
                        // curves of less than one point are trimmed, because they
                        // have no duration, and therefore are not modelled in our
                        // system.
                        if (current_curve.items.len > 1) 
                        {
                            try curves_to_project.append(
                                Linear{
                                    .knots = (
                                        try current_curve.toOwnedSlice()
                                    ),
                                }
                            );
                        }
                        current_curve.clearAndFree();
                    }

                    try current_curve.append(other_knot);
                    last_index = @intCast(index);
                }
            }
            if (current_curve.items.len > 1) {
                try curves_to_project.append(
                    Linear{
                        .knots = try current_curve.toOwnedSlice(),
                    }
                );
            }
            current_curve.clearAndFree();
        }
        other_split_at_self_knots.deinit(allocator);

        if (curves_to_project.items.len == 0) {
            return &[_]Linear{};
        }

        for (curves_to_project.items) 
            |crv| 
        {
            // project each knot
            for (crv.knots) 
                |*knot| 
            {
                // 2. output_at_input grows a parameter to treat endpoint as in bounds
                // 3. check outside of output_at_input if it sits on a knot and use
                //    the value rather than computing
                // 4. catch the error and call a different function or do a
                //    check in that case
                const value = self.output_at_input(knot.out) catch (
                    if (self.knots[self.knots.len-1].in == knot.out) 
                        self.knots[self.knots.len-1].out 
                    else return error.NotInRangeError
                );

                knot.out  = value;
            }
        }

        // @TODO: we should write a test that exersizes this case
        if (curves_to_project.items.len > 1) {
            return error.MoreThanOneCurveIsNotImplemented;
        }


        return try curves_to_project.toOwnedSlice();
    }

    /// convienence wrapper around project_curve that assumes a single result
    /// and returns handles the cleanup of that.
    pub fn project_curve_single_result(
        self: @This(),
        allocator: std.mem.Allocator,
        other: Linear
    ) !Linear 
    {
        const result = try self.project_curve(
            allocator,
            other
        );

        if (result.len > 1) {
            @panic("Not Implemented");
        }

        defer { 
            for (result)
                |crv|
            {
                crv.deinit(allocator);
            }
            allocator.free(result);
        }

        if (result.len < 1)
        {
            std.debug.print(
                "Couldn't project:\n  self: {any}\n  other: {any}\n",
                .{ self.extents(), other.extents(), },
            );
            return error.NoProjectionResultError;
        }

        return try result[0].clone(allocator);
    }

    pub fn debug_json_str(
        self:@This(), 
        allocator: std.mem.Allocator,
    ) ![]const u8
    {
        var str = std.ArrayList(u8).init(allocator);

        try std.json.stringify(self, .{}, str.writer()); 

        return str.toOwnedSlice();
    }

    /// return the extents of the input domain of the curve  - O(1) because
    /// curves are monotonic over their input spaces by definition.
    pub fn extents_input(
        self:@This()
    ) opentime.ContinuousTimeInterval 
    {
        return .{
            .start_seconds = self.knots[0].in,
            .end_seconds = self.knots[self.knots.len - 1].in,
        };
    }

    /// compute the extents for the curve exhaustively
    pub fn extents(self:@This()) [2]ControlPoint {
        var min:ControlPoint = self.knots[0];
        var max:ControlPoint = self.knots[0];

        for (self.knots) 
            |knot| 
        {
            min = .{
                .in = @min(min.in, knot.in),
                .out = @min(min.out, knot.out),
            };
            max = .{
                .in = @max(max.in, knot.in),
                .out = @max(max.out, knot.out),
            };
        }
        return .{ min, max };
    }

    /// insert a knot each location on the curve that crosses the values in
    /// split_points
    pub fn split_at_each_value(
        self: @This(),
        allocator: std.mem.Allocator,
        split_points: []f32,
    ) !Linear 
    {
        var result = std.ArrayList(ControlPoint).init(
            allocator,
        );

        const last_minus_one = self.knots.len-1;

        // @TODO: there is probably a more effecient algorithm here than MxN
        for (self.knots[0..last_minus_one], self.knots[1..])
            |knot, next_knot, |
        {
            try result.append(knot);

            for (split_points) 
                |pt_value_space| 
            {
                if (
                    knot.out < pt_value_space 
                    and pt_value_space < next_knot.out
                )
                {
                    const u = bezier_math.invlerp(
                        pt_value_space,
                        knot.out,
                        next_knot.out
                    );
                    try result.append(
                        bezier_math.lerp(
                            u,
                            knot,
                            next_knot
                        )
                    );
                }
            }
        }
        try result.append(self.knots[last_minus_one]);

        return Linear{
            .knots = try result.toOwnedSlice() 
        };
    }
};

test "Linear: extents" 
{
    const crv = try Linear.init_identity(
        std.testing.allocator,
        &.{100, 200},
    );
    defer crv.deinit(std.testing.allocator);

    const bounds = crv.extents();

    try expectEqual(@as(f32, 100), bounds[0].in);
    try expectEqual(@as(f32, 200), bounds[1].in);

    const bounds_input = crv.extents_input();
    try expectEqual(@as(f32, 100), bounds_input.start_seconds);
    try expectEqual(@as(f32, 200), bounds_input.end_seconds);
}

test "Linear: proj_ident" 
{
    const ident = try Linear.init_identity(
        std.testing.allocator,
        &.{0, 100},
    );
    defer ident.deinit(std.testing.allocator);

    {
        var right_overhang= [_]ControlPoint{
            .{ .in = -10, .out = -10},
            .{ .in = 30, .out = 10},
        };
        const right_overhang_lin = Linear{
            .knots = &right_overhang,
        };
         
        const result = try ident.project_curve(
            std.testing.allocator,
            right_overhang_lin,
        );
        defer {
            for (result)
                |crv|
            {
                crv.deinit(std.testing.allocator);
            }
            std.testing.allocator.free(result);
        }

        try expectEqual(@as(usize, 1), result.len);
        try expectEqual(@as(usize, 2), result[0].knots.len);

        try expectEqual(@as(f32, 10), result[0].knots[0].in);
        try expectEqual(@as(f32, 0), result[0].knots[0].out);

        try expectEqual(@as(f32, 30), result[0].knots[1].in);
        try expectEqual(@as(f32, 10), result[0].knots[1].out);

        // @TODO: check the obviously out of bounds results as well
    }

    {
        const left_overhang = [_]ControlPoint{
            .{ .in = 90, .out = 90},
            .{ .in = 110, .out = 130},
        };
        const left_overhang_lin = try Linear.init(
            std.testing.allocator,
            &left_overhang,
        );
        defer left_overhang_lin.deinit(std.testing.allocator);

        const result = try ident.project_curve(
            std.testing.allocator,
            left_overhang_lin,
        );
        defer {
            for (result)
                |crv|
            {
                crv.deinit(std.testing.allocator);
            }
            std.testing.allocator.free(result);
        }

        try expectEqual(@as(usize, 1), result.len);
        try expectEqual(@as(usize, 2), result[0].knots.len);

        try expectEqual(@as(f32, 90), result[0].knots[0].in);
        try expectEqual(@as(f32, 90), result[0].knots[0].out);

        try expectEqual(@as(f32, 95),  result[0].knots[1].in);
        try expectEqual(@as(f32, 100), result[0].knots[1].out);
    }

    // @TODO: add third test case, with right AND left overhang
}

test "Linear: project s" 
{
    const ident = try Linear.init_identity(
        std.testing.allocator,
        &.{0, 100},
    );
    defer ident.deinit(std.testing.allocator);

    const simple_s: [4]ControlPoint = .{
        .{ .in = 0, .out = 0},
        .{ .in = 30, .out = 10},
        .{ .in = 60, .out = 90},
        .{ .in = 100, .out = 100},
    };

    const simple_s_lin = try Linear.init(
        std.testing.allocator,
        &simple_s,
    );
    defer simple_s_lin.deinit(std.testing.allocator);

    const result = try simple_s_lin.project_curve(
        std.testing.allocator,
        ident,
    );
    defer {
        for (result)
            |crv|
            {
                crv.deinit(std.testing.allocator);
            }
        std.testing.allocator.free(result);
    }

    try expectEqual(@as(usize, 1), result.len);
    try expectEqual(@as(usize, 4), result[0].knots.len);
}

test "Linear: projection_test - compose to identity" 
{
    const fst= try Linear.init(
        std.testing.allocator,
        &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 4, .out = 8, },
        }
    );
    defer fst.deinit(std.testing.allocator);
    const snd= try Linear.init(
        std.testing.allocator,
        &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 8, .out = 4, },
        },
    );
    defer snd.deinit(std.testing.allocator);

    const result = try fst.project_curve(
        std.testing.allocator,
        snd,
    );
    defer {
        for (result)
            |crv|
            {
                crv.deinit(std.testing.allocator);
            }
        std.testing.allocator.free(result);
    }

    try expectEqual(@as(usize, 1), result.len);
    try expectEqual(@as(f32, 8), result[0].knots[1].in);
    try expectEqual(@as(f32, 8), result[0].knots[1].out);

    var x:f32 = 0;
    while (x < 1) 
        : (x += 0.1)
    {
        try expectApproxEqAbs(
            x,
            try result[0].output_at_input(x),
            generic_curve.EPSILON
        );
    }
}

test "Linear: Affine through linear"
{
    // given a curve that maps space a -> space b
    // and a transform that maps b->c

    const b2c_crv= try Linear.init(
        std.testing.allocator,
        &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 4, .out = 8, },
        }
    );
    defer b2c_crv.deinit(std.testing.allocator);
    const b2c_extents = b2c_crv.extents();

    errdefer std.debug.print(
        "b2c_crv_b_extents: [{d}, {d})\nb2c_crv_c_extents: [{d}, {d})\n",
        .{
            b2c_extents[0].in, b2c_extents[1].in,
            b2c_extents[0].out, b2c_extents[1].out,
        }
    );

    const b_bound = opentime.ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 2,
    };
    errdefer std.debug.print(
        "b_bound: [{d}, {d})\n",
        .{
            b_bound.start_seconds, b_bound.end_seconds,
        }
    );

    errdefer std.debug.print("INPUTS:\n", .{});

    const a2b_transformation_tests = (
        [_]opentime.transform.AffineTransform1D{
            opentime.transform.AffineTransform1D{
                .offset_seconds = 0,
                .scale = 1,
            },
            opentime.transform.AffineTransform1D{
                .offset_seconds = 10,
                .scale = 1,
            },
            opentime.transform.AffineTransform1D{
                .offset_seconds = 0,
                .scale = 2,
            },
        }
    );

    for (a2b_transformation_tests, 0..)
        |a2b_aff, test_ind|
    {
        errdefer std.debug.print(
            "[erroring test iteration {d}]:\n a2b offset: {d}\n a2b scale: {d} \n",
            .{ test_ind, a2b_aff.offset_seconds, a2b_aff.scale },
        );
        const a2c_result = try b2c_crv.project_affine(
            std.testing.allocator,
            a2b_aff,
            b_bound,
        );
        defer a2c_result.deinit(std.testing.allocator);

        const a2c_result_extents = a2c_result.extents();

        errdefer std.debug.print(
            "a2c_result_extents: [({d}, {d}), ({d}, {d}))\n",
            .{
                a2c_result_extents[0].in, a2c_result_extents[0].out,
                a2c_result_extents[1].in, a2c_result_extents[1].out,
            }
        );

        const b2a_aff = a2b_aff.inverted();
        const a_bound = b2a_aff.applied_to_cti(b_bound);

        errdefer std.debug.print(
            "computed_a_bounds: [{d}, {d})\n",
            .{
                a_bound.start_seconds, 
                a_bound.end_seconds,
            }
        );

        try expectApproxEqAbs(
            a2c_result_extents[0].in,
            a_bound.start_seconds,
            generic_curve.EPSILON,
        );
    }
}

pub fn join_lin_aff(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: Linear,
        b2c: opentime.AffineTransform1D,
    },
) !Linear
{
    const new_knots = try allocator.dupe(
        ControlPoint,
        args.a2b.knots,
    );

    for (new_knots)
        |*knot|
    {
        knot.out = args.b2c.applied_to_seconds(knot.out);
    }

    return .{
        .knots = new_knots,
    };
}

test "Linear: linear through affine"
{
    // given a curve that maps space a -> space b
    // and a transform that maps b->c

    const a2b_crv= try Linear.init(
        std.testing.allocator,
        &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 4, .out = 8, },
        }
    );
    defer a2b_crv.deinit(std.testing.allocator);
    const a2b_extents = a2b_crv.extents();

    errdefer std.debug.print(
        "b2c_crv_b_extents: [{d}, {d})\nb2c_crv_c_extents: [{d}, {d})\n",
        .{
            a2b_extents[0].in,  a2b_extents[1].in,
            a2b_extents[0].out, a2b_extents[1].out,
        }
    );

    const TestThing = struct{
        xform: opentime.AffineTransform1D,
        test_pt: [2]f32,
    };

    const b2c_transformation_tests = (
        [_]TestThing{
            .{
                .xform = opentime.AffineTransform1D{
                    .offset_seconds = 0,
                    .scale = 1,
                },
                .test_pt = .{ 2, 4 },
            },
            .{
                .xform = opentime.AffineTransform1D{
                    .offset_seconds = 10,
                    .scale = 1,
                },
                .test_pt = .{ 2, 14 },
            },
            .{
                .xform = opentime.AffineTransform1D{
                    .offset_seconds = 0,
                    .scale = 2,
                },
                .test_pt = .{ 2, 8 },
            }
        }
    );

    for (b2c_transformation_tests, 0..)
        |t, test_ind|
    {
        const b2c_aff = t.xform;

        errdefer std.debug.print(
            "[erroring test iteration {d}]:\n b2c offset: {d}\n "
            ++ "b2c scale: {d} \n",
            .{ test_ind, b2c_aff.offset_seconds, b2c_aff.scale },
        );

        const a2c = try join_lin_aff(
            std.testing.allocator,
            .{
                .a2b = a2b_crv,
                .b2c = b2c_aff,
            },
        );
        defer a2c.deinit(std.testing.allocator);

        const result = try a2c.output_at_input(t.test_pt[0]);

        errdefer std.debug.print(
            "[test: {d}] input: {d} expected: {d} got: {d}\n",
            .{ test_ind, t.test_pt[0], t.test_pt[1], result }
        );

        try std.testing.expectEqual( t.test_pt[1], result);
    }
}

test "Linear: trimmed_in_input_space"
{
    const crv = try Linear.init(
        std.testing.allocator,
        &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 4, .out = 8, },
        }
    );
    defer crv.deinit(std.testing.allocator);

    const bounds = opentime.ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 2,
    };
    const crv_ext = crv.extents();
    errdefer std.debug.print(
        "bounds: [({d}, {d}), ({d}, {d}))\n",
        .{
            crv_ext[0].in, crv_ext[0].out,
            crv_ext[1].in, crv_ext[1].out,
        }
    );

    const trimmed_crv = try crv.trimmed_in_input_space(
        std.testing.allocator,
        bounds
    );
    defer trimmed_crv.deinit(std.testing.allocator);
    const trimmed_extents = trimmed_crv.extents();
    errdefer std.debug.print(
        "found: [({d}, {d}), ({d}, {d}))\n",
        .{
            trimmed_extents[0].in, trimmed_extents[0].out,
            trimmed_extents[1].in, trimmed_extents[1].out,
        }
    );

    try expectApproxEqAbs(
        bounds.start_seconds,
        trimmed_extents[0].in, 
        generic_curve.EPSILON,
    );

    try expectApproxEqAbs(
        bounds.end_seconds,
        trimmed_extents[1].in, 
        generic_curve.EPSILON,
    );
}

// @TODO CBB XXX HACK is this the kind of interface that is preferable?
// /// if an affine transforms from A to B, and a linear curve transforms from B
// /// to C, compose and build a transformation from A to C
// pub fn compose_transform_linear_curve_affine(
//         allocator: std.mem.Allocator,
//         a2b_crv: opentime.transform.AffineTransform1D,
//         b2c_crv: Linear,
// ) !Linear
// {}
//
// /// if an affine transforms from A to B, and a linear curve transforms from B
// /// to C, compose and build a transformation from A to C
// pub fn compose_transform_linear_curve_affine(
//         allocator: std.mem.Allocator,
//         a2b_aff: opentime.transform.AffineTransform1D,
//         b_bounds:opentime.ContinuousTimeInterval,
//         b2c_crv: Linear,
// ) !Linear
// {
//     _ = allocator;
//     _ = a2b_aff;
//     _ = b_bounds;
//
//     return b2c_crv;
// }
