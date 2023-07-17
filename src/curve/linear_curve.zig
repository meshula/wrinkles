const bezier_math = @import("bezier_math.zig");
const generic_curve = @import("generic_curve.zig");
const control_point = @import("control_point.zig");
const ControlPoint = control_point.ControlPoint;

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

const opentime = @import("opentime");
const ALLOCATOR = @import("otio_allocator").ALLOCATOR;
const ContinuousTimeInterval = opentime.ContinuousTimeInterval;

fn _is_between(val: f32, fst: f32, snd: f32) bool {
    return ((fst <= val and val < snd) or (fst >= val and val > snd));
}

/// A polyline that is linearly interpolated between knots
pub const TimeCurveLinear = struct {
    knots: []ControlPoint = &.{},

    pub fn init(
        knots: []const ControlPoint
    ) error{OutOfMemory}!TimeCurveLinear 
    {
        return TimeCurveLinear{
            .knots = try ALLOCATOR.dupe(ControlPoint, knots) 
        };
    }

    pub fn init_identity(knot_times:[]const f32) !TimeCurveLinear {
        var result = std.ArrayList(ControlPoint).init(ALLOCATOR);
        for (knot_times) 
            |t| 
        {
            try result.append(.{.time = t, .value = t});
        }

        return TimeCurveLinear{ .knots = result.items };
    }

    pub fn project_affine(
        self: @This(),
        aff: opentime.transform.AffineTransform1D,
        allocator: std.mem.Allocator,
    ) !TimeCurveLinear 
    {
        var result_knots = try allocator.dupe(ControlPoint, self.knots);

        for (self.knots, 0..) |pt, pt_index| {
            result_knots[pt_index] = .{ 
                .time = aff.applied_to_seconds(pt.time),
                .value = pt.value,
            };
        }

        return .{ .knots = result_knots };
    }

    // @TODO: write .deinit() to free knots

    /// evaluate the curve at time t in the space of the curve
    pub fn evaluate(self: @This(), t_arg: f32) error{OutOfBounds}!f32 {
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

    pub fn nearest_smaller_knot_index_value(
        self: @This(),
        v_arg: f32
    ) []u32 
    {
        const bounds = self.extents();
        if (
            self.knots.len == 0 
            or v_arg < bounds[0].value 
            or v_arg >= bounds[1].value
        ) {
            return .{};
        }

        var result = std.ArrayList(u32).init(ALLOCATOR) catch unreachable;

        // last knot is out of domain
        for (self.knots[0..self.knots.len-1], 0..) 
            |knot, index| 
        {
            const next_knot = self.knots[index+1];
            if (
                (knot.value <= v_arg and v_arg < next_knot.value)
                or (knot.value >= v_arg and v_arg > next_knot.value)
            )
            {
                result.append(index);
            }
        }

        return result.items;
    }

    pub fn nearest_smaller_knot_index(
        self: @This(),
        t_arg: f32, 
    ) ?usize 
    {
        if (self.knots.len == 0 
            or (t_arg < self.knots[0].time)
            or t_arg >= self.knots[self.knots.len - 1].time)
        {
            return null;
        }

        // last knot is out of domain
        for (self.knots[0..self.knots.len-1], 0..) 
            |knot, index| 
        {
            if ( knot.time <= t_arg and t_arg < self.knots[index+1].time) 
            {
                return index;
            }
        }

        if (self.knots[self.knots.len - 1].time == t_arg) {
            return self.knots.len - 1;
        }

        return null;
    }

    pub fn insert(self: @This(), knot: ControlPoint) void {
        _ = self;
        _ = knot;
        @panic("not implemented");
        //
        // if (knot.time)
        //
        // const conflict = find_segment(seg.p0.time);
        // if (conflict != null)
        //     unreachable;
        //
        // self.segments.append(seg);
        // std.sort(
        //     @TypeOf(seg),
        //     self.segments.to_slice(),
        //     generic_curve.cmpSegmentsByStart
        // );
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
        /// curve being projected
        other: TimeCurveLinear
    ) []TimeCurveLinear 
    {
        @breakpoint();
        // @TODO: if there are preserved derivatives, project and compose them
        //        as well
        //
        const other_bounds = other.extents();
        var other_split_at_self_knots = TimeCurveLinear{};

        // find all knots in self that are within the other bounds
        {
            var split_points = std.ArrayList(f32).init(ALLOCATOR);
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
                    split_points.append(self_knot.time) catch unreachable;
                }
            }

            other_split_at_self_knots = other.split_at_each_value(
                split_points.items
            );
        }

        // split other into curves where it goes in and out of the domain of self
        var curves_to_project = std.ArrayList(TimeCurveLinear).init(ALLOCATOR);
        const self_bounds = self.extents();
        var last_index: i32 = -10;
        var current_curve = std.ArrayList(ControlPoint).init(ALLOCATOR);
        defer current_curve.deinit();

        for (other_split_at_self_knots.knots, 0..) 
            |other_knot, index| 
        {
            if (
                self_bounds[0].time <= other_knot.value 
                and other_knot.value <= self_bounds[1].time
            ) 
            {
                if (index != last_index+1) {
                    // curves of less than one point are trimmed, because they
                    // have no duration, and therefore are not modelled in our
                    // system.
                    if (current_curve.items.len > 1) {
                        curves_to_project.append(
                            TimeCurveLinear.init(
                                current_curve.items
                            ) catch unreachable
                        ) catch unreachable;
                    }
                    current_curve = std.ArrayList(ControlPoint).init(ALLOCATOR);
                }

                current_curve.append(other_knot) catch unreachable;
                last_index = @intCast(i32, index);
            }
        }
        if (current_curve.items.len > 1) {
            curves_to_project.append(
                TimeCurveLinear.init(current_curve.items) catch unreachable
            ) catch unreachable;
        }

        if (curves_to_project.items.len == 0) {
            return &[_]TimeCurveLinear{};
        }

        for (curves_to_project.items) 
            |crv| 
        {
            // project each knot
            for (crv.knots, 0..) 
                |knot, index| 
            {
                // 2. evaluate grows a parameter to treat endpoint as in bounds
                // 3. check outside of evaluate if it sits on a knot and use
                //    the value rathe rthan computing
                // 4. catch the error and call a different function or do a
                //    check in that case
                const value = self.evaluate(knot.value) catch (
                    if (self.knots[self.knots.len-1].time == knot.value) 
                        self.knots[self.knots.len-1].value 
                    else unreachable
                );
                crv.knots[index] = .{
                    .time = knot.time,
                    // this will error out trying to project the last endpoint
                    // .value = self.evaluate(knot.value) catch unreachable
                    .value = value
                };
            }
        }

        // @TODO: we should write a test that exersizes this case
        if (curves_to_project.items.len > 1) {
            @panic("AAAAAH MORe THAN ONE CURVE");
        }

        return curves_to_project.items;
    }

    pub fn debug_json_str(self:@This()) []const u8
    {
        var str = std.ArrayList(u8).init(ALLOCATOR);
        std.json.stringify(self, .{}, str.writer()) catch unreachable; 
        return str.items;
    }

    pub fn extents_time(self:@This()) ContinuousTimeInterval {
        return .{
            .start_seconds = self.segments[0].p0.time,
            .end_seconds = self.segments[self.segments.len - 1].p1.time,
        };
    }

    pub fn extents(self:@This()) [2]ControlPoint {
        var min:ControlPoint = self.knots[0];
        var max:ControlPoint = self.knots[0];

        for (self.knots) |knot| {
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
        split_points: []f32
    ) TimeCurveLinear 
    {
        var result = std.ArrayList(ControlPoint).init(ALLOCATOR);
        for (self.knots[0..self.knots.len-1], 0..)
            |knot, index|
        {
            result.append(knot) catch unreachable;
            const next_knot = self.knots[index+1];

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
                    result.append(
                        bezier_math.lerp_cp(
                            u,
                            knot,
                            next_knot
                        )
                    ) catch unreachable;
                }
            }
        }
        result.append(self.knots[self.knots.len-1]) catch unreachable;

        // @TODO: free the existing slice
        return TimeCurveLinear{ .knots = result.items };
    }
};

test "TimeCurveLinear: extents" {
    const crv = try TimeCurveLinear.init_identity(&.{100, 200});
    const bounds = crv.extents();

    try expectEqual(@as(f32, 100), bounds[0].time);
    try expectEqual(@as(f32, 200), bounds[1].time);
}

test "TimeCurveLinear: proj_ident" 
{
    const ident = try TimeCurveLinear.init_identity(&.{0, 100});

    {
        const right_overhang= [_]ControlPoint{
            .{ .time = -10, .value = -10},
            .{ .time = 30, .value = 10},
        };
        const right_overhang_lin = try TimeCurveLinear.init(&right_overhang);
        const result = ident.project_curve(right_overhang_lin);
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
        const left_overhang_lin = try TimeCurveLinear.init(&left_overhang);

        const result = ident.project_curve(left_overhang_lin);

        try expectEqual(@as(usize, 1), result.len);
        try expectEqual(@as(usize, 2), result[0].knots.len);

        try expectEqual(@as(f32, 90), result[0].knots[0].time);
        try expectEqual(@as(f32, 90), result[0].knots[0].value);

        try expectEqual(@as(f32, 95),  result[0].knots[1].time);
        try expectEqual(@as(f32, 100), result[0].knots[1].value);
    }

    // @TODO: add third test case, with right AND left overhang
}

test "TimeCurveLinear: project s" {
    // @TODO: the next thing to fix -- START HERE
    const ident = try TimeCurveLinear.init_identity(&.{0, 100});

    const simple_s: [4]ControlPoint = .{
        .{ .time = 0, .value = 0},
        .{ .time = 30, .value = 10},
        .{ .time = 60, .value = 90},
        .{ .time = 100, .value = 100},
    };

    const simple_s_lin = try TimeCurveLinear.init(&simple_s);
    const result = simple_s_lin.project_curve(ident);

    try expectEqual(@as(usize, 1), result.len);
    try expectEqual(@as(usize, 4), result[0].knots.len);
}

test "TimeCurveLinear: projection_test - compose to identity" {
    const fst= try TimeCurveLinear.init(
        &.{
            .{ .time = 0, .value = 0, },
            .{ .time = 4, .value = 8, },
        }
    );
    const snd= try TimeCurveLinear.init(
        &.{
            .{ .time = 0, .value = 0, },
            .{ .time = 8, .value = 4, },
        }
    );

    const result = fst.project_curve(snd);

    try expectEqual(@as(usize, 1), result.len);
    try expectEqual(@as(f32, 8), result[0].knots[1].time);
    try expectEqual(@as(f32, 8), result[0].knots[1].value);

    var x:f32 = 0;
    while (x < 1) {
        // @TODO: fails because evaluating a linear curve
        try expectApproxEqAbs(x, try result[0].evaluate(x), generic_curve.EPSILON);
        x += 0.1;
    }
}

