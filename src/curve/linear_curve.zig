//! Linear curves are made of connected line segments

const bezier_math = @import("bezier_math.zig");
const generic_curve = @import("generic_curve.zig");
const ControlPoint = @import("control_point.zig").ControlPoint;

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

const opentime = @import("opentime");
const ContinuousTimeInterval = opentime.ContinuousTimeInterval;

fn _is_between(
    val: f32,
    fst: f32,
    snd: f32
) bool 
{
    return (
        (fst <= val and val < snd) 
        or (fst >= val and val > snd)
    );
}

/// A polyline that is linearly interpolated between knots
pub const TimeCurveLinear = struct {
    knots: []ControlPoint = &.{},

    // @TODO: remove the allocator from this
    /// dupe the provided points into the result
    pub fn init(
        allocator: std.mem.Allocator,
        knots: []const ControlPoint
    ) !TimeCurveLinear 
    {
        return TimeCurveLinear{
            .knots = try allocator.dupe(
                ControlPoint,
                knots,
            ) 
        };
    }

    /// initialize a TimeCurveLinear where each knot time has the same value
    /// as the time (in other words, an identity curve that passes through t=0).
    pub fn init_identity(
        allocator: std.mem.Allocator,
        knot_times:[]const f32
    ) !TimeCurveLinear 
    {
        var result = std.ArrayList(ControlPoint).init(
            allocator,
        );
        for (knot_times) 
            |t| 
        {
            try result.append(.{.time = t, .value = t});
        }

        return TimeCurveLinear{
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
    ) !TimeCurveLinear
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
    ) !TimeCurveLinear
    {
        // @TODO CBB - obviously not promoting to bezier_curve and then
        //             trimming that way only to linearize back to
        //             TimeCurveLinear would be better than this.
        //             HACK XXX
        const tmp_curve = try bezier_curve.TimeCurve.init_from_linear_curve(
            allocator,
            self,
        );
        defer tmp_curve.deinit(allocator);

        const trimmed_curve = try tmp_curve.trimmed_in_input_space(
            input_bounds,
            allocator,
        );
        defer trimmed_curve.deinit(allocator);

        return try trimmed_curve.linearized(allocator);
    }

    /// project an affine transformation through the curve
    pub fn project_affine(
        self: @This(),
        aff: opentime.transform.AffineTransform1D,
        allocator: std.mem.Allocator,
    ) !TimeCurveLinear 
    {
        const result_knots = try allocator.dupe(
            ControlPoint,
            self.knots
        );

        for (self.knots, result_knots) 
            |pt, *target_knot| 
        {
            target_knot.time = aff.applied_to_seconds(pt.time);
        }

        return .{
            .knots = result_knots,
        };
    }

    /// evaluate the curve at time t in the space of the curve
    pub fn evaluate(
        self: @This(),
        t_arg: f32,
    ) error{OutOfBounds}!f32 
    {
        if (self.nearest_smaller_knot_index(t_arg)) 
           |index| 
        {
            return bezier_math.value_at_time_between(
                t_arg,
                self.knots[index],
                self.knots[index+1],
            );
        }

        return error.OutOfBounds;
    }

    pub fn evaluate_at_value(
        self: @This(),
        value_ord: f32,
    ) !f32
    {
        if (self.nearest_smaller_knot_index_to_value(value_ord)) 
           |index| 
        {
            return bezier_math.time_at_value_between(
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
            or (t_arg < self.knots[0].time)
            or t_arg >= self.knots[last_index].time
        )
        {
            return null;
        }

        // last knot is out of domain
        for (self.knots[0..last_index], self.knots[1..], 0..) 
            |knot, next_knot, index| 
        {
            if ( knot.time <= t_arg and t_arg < next_knot.time) 
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
            or (value_ord < self.knots[0].value)
            or value_ord >= self.knots[last_index].value
        )
        {
            return null;
        }

        // last knot is out of domain
        for (self.knots[0..last_index], self.knots[1..], 0..) 
            |knot, next_knot, index| 
        {
            if ( knot.value <= value_ord and value_ord < next_knot.value) 
            {
                return index;
            }
        }

        return null;
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
        /// curve being projected _through_
        self: @This(),
        allocator: std.mem.Allocator,
        /// curve being projected
        other: TimeCurveLinear
    ) ![]TimeCurveLinear 
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
                    self_knot.time,
                    other_bounds[0].value,
                    other_bounds[1].value
                )
            ) {
                try split_points.append(self_knot.time);
            }
        }

        const other_split_at_self_knots = try other.split_at_each_value(
            allocator,
            split_points.items
        );

        // split other into curves where it goes in and out of the domain of self
        var curves_to_project = std.ArrayList(
            TimeCurveLinear,
        ).init(allocator);

        // gather the curves to project by splitting
        {
            const self_bounds_t = self.extents_time();
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
                    self_bounds_t.start_seconds <= other_knot.value 
                    and other_knot.value <= self_bounds_t.end_seconds
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
                                TimeCurveLinear{
                                    .knots = try current_curve.toOwnedSlice(),
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
                    TimeCurveLinear{
                        .knots = try current_curve.toOwnedSlice(),
                    }
                );
            }
            current_curve.clearAndFree();
        }
        other_split_at_self_knots.deinit(allocator);

        if (curves_to_project.items.len == 0) {
            return &[_]TimeCurveLinear{};
        }

        for (curves_to_project.items) 
            |crv| 
        {
            // project each knot
            for (crv.knots) 
                |*knot| 
            {
                // 2. evaluate grows a parameter to treat endpoint as in bounds
                // 3. check outside of evaluate if it sits on a knot and use
                //    the value rather than computing
                // 4. catch the error and call a different function or do a
                //    check in that case
                const value = self.evaluate(knot.value) catch (
                    if (self.knots[self.knots.len-1].time == knot.value) 
                        self.knots[self.knots.len-1].value 
                    else return error.NotInRangeError
                );

                knot.value  = value;
            }
        }

        // @TODO: we should write a test that exersizes this case
        if (curves_to_project.items.len > 1) {
            return error.MoreThanOneCurveIsNotImplemented;
        }

        return try curves_to_project.toOwnedSlice();
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

    /// return the extents of the time (input) domain of the curve  - O(1)
    /// because curves are monotonic over time by definition.
    pub fn extents_time(
        self:@This()
    ) ContinuousTimeInterval 
    {
        return .{
            .start_seconds = self.knots[0].time,
            .end_seconds = self.knots[self.knots.len - 1].time,
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
                .time = @min(min.time, knot.time),
                .value = @min(min.value, knot.value),
            };
            max = .{
                .time = @max(max.time, knot.time),
                .value = @max(max.value, knot.value),
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
    ) !TimeCurveLinear 
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
                    knot.value < pt_value_space 
                    and pt_value_space < next_knot.value
                )
                {
                    const u = bezier_math.invlerp(
                        pt_value_space,
                        knot.value,
                        next_knot.value
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

        return TimeCurveLinear{
            .knots = try result.toOwnedSlice() 
        };
    }
};

test "TimeCurveLinear: extents" 
{
    const crv = try TimeCurveLinear.init_identity(
        std.testing.allocator,
        &.{100, 200},
    );
    defer crv.deinit(std.testing.allocator);

    const bounds = crv.extents();

    try expectEqual(@as(f32, 100), bounds[0].time);
    try expectEqual(@as(f32, 200), bounds[1].time);

    const bounds_time = crv.extents_time();
    try expectEqual(@as(f32, 100), bounds_time.start_seconds);
    try expectEqual(@as(f32, 200), bounds_time.end_seconds);
}

test "TimeCurveLinear: proj_ident" 
{
    const ident = try TimeCurveLinear.init_identity(
        std.testing.allocator,
        &.{0, 100},
    );
    defer ident.deinit(std.testing.allocator);

    {
        var right_overhang= [_]ControlPoint{
            .{ .time = -10, .value = -10},
            .{ .time = 30, .value = 10},
        };
        const right_overhang_lin = TimeCurveLinear{
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

        try expectEqual(@as(f32, 10), result[0].knots[0].time);
        try expectEqual(@as(f32, 0), result[0].knots[0].value);

        try expectEqual(@as(f32, 30), result[0].knots[1].time);
        try expectEqual(@as(f32, 10), result[0].knots[1].value);

        // @TODO: check the obviously out of bounds results as well
    }

    {
        const left_overhang = [_]ControlPoint{
            .{ .time = 90, .value = 90},
            .{ .time = 110, .value = 130},
        };
        const left_overhang_lin = try TimeCurveLinear.init(
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

        try expectEqual(@as(f32, 90), result[0].knots[0].time);
        try expectEqual(@as(f32, 90), result[0].knots[0].value);

        try expectEqual(@as(f32, 95),  result[0].knots[1].time);
        try expectEqual(@as(f32, 100), result[0].knots[1].value);
    }

    // @TODO: add third test case, with right AND left overhang
}

test "TimeCurveLinear: project s" 
{
    const ident = try TimeCurveLinear.init_identity(
        std.testing.allocator,
        &.{0, 100},
    );
    defer ident.deinit(std.testing.allocator);

    const simple_s: [4]ControlPoint = .{
        .{ .time = 0, .value = 0},
        .{ .time = 30, .value = 10},
        .{ .time = 60, .value = 90},
        .{ .time = 100, .value = 100},
    };

    const simple_s_lin = try TimeCurveLinear.init(
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

test "TimeCurveLinear: projection_test - compose to identity" 
{
    const fst= try TimeCurveLinear.init(
        std.testing.allocator,
        &.{
            .{ .time = 0, .value = 0, },
            .{ .time = 4, .value = 8, },
        }
    );
    defer fst.deinit(std.testing.allocator);
    const snd= try TimeCurveLinear.init(
        std.testing.allocator,
        &.{
            .{ .time = 0, .value = 0, },
            .{ .time = 8, .value = 4, },
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
    try expectEqual(@as(f32, 8), result[0].knots[1].time);
    try expectEqual(@as(f32, 8), result[0].knots[1].value);

    var x:f32 = 0;
    while (x < 1) 
        : (x += 0.1)
    {
        try expectApproxEqAbs(
            x,
            try result[0].evaluate(x),
            generic_curve.EPSILON
        );
    }
}
test "TimeCurveLinear: trimmed_in_input_space"
{
    const crv = try TimeCurveLinear.init(
        std.testing.allocator,
        &.{
            .{ .time = 0, .value = 0, },
            .{ .time = 4, .value = 8, },
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
            crv_ext[0].time, crv_ext[0].value,
            crv_ext[1].time, crv_ext[1].value,
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
            trimmed_extents[0].time, trimmed_extents[0].value,
            trimmed_extents[1].time, trimmed_extents[1].value,
        }
    );

    try expectApproxEqAbs(
        bounds.start_seconds,
        trimmed_extents[0].time, 
        generic_curve.EPSILON,
    );

    try expectApproxEqAbs(
        bounds.end_seconds,
        trimmed_extents[1].time, 
        generic_curve.EPSILON,
    );
}
