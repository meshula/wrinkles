//! Linear curves are made of right-met connected line segments

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

const RUN_PERF_TESTS = @import("build_options").run_perf_tests;

const opentime = @import("opentime");

const bezier_curve = @import("bezier_curve.zig");
const bezier_math = @import("bezier_math.zig");
const generic_curve = @import("generic_curve.zig");
const ControlPoint = @import("control_point.zig").ControlPoint;

/// A polyline that is linearly interpolated between knots
pub fn LinearOf(
    comptime ControlPointType: type,
) type
{
    return struct {
        knots: []ControlPointType = &.{},

        const LinearType = LinearOf(ControlPointType);

        /// Immutable Monotonic form of the Linear curve.  Constructed by
        /// splitting a Linear with split_at_critical_points
        pub const Monotonic = struct {
            knots: []const ControlPointType,

            pub fn deinit(
                self: @This(),
                allocator: std.mem.Allocator,
            ) void 
            {
                allocator.free(self.knots);
            }

            pub fn clone(
                self: @This(),
                allocator: std.mem.Allocator
            ) !@This()
            {
                return .{ 
                    .knots = try allocator.dupe(
                        ControlPointType,
                        self.knots
                    ),
                };
            }

            /// compute both the input and output extents for the curve
            /// exhaustively.  [0] is the minimum and [1] is the maximum
            pub fn extents(
                self:@This(),
            ) [2]ControlPointType 
            {
                var min:ControlPointType = self.knots[0];
                var max:ControlPointType = self.knots[0];

                inline for (&.{ self.knots[0], self.knots[self.knots.len-1] }) 
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

            /// compute both the input extents for the curve exhaustively
            pub fn extents_input(
                self:@This(),
            ) opentime.interval.ContinuousTimeInterval
            {
                if (self.knots.len == 0) {
                    return .{ .start_seconds = 0, .end_seconds = 0 };
                }
                const fst = self.knots[0].in;
                const lst = self.knots[self.knots.len-1].in;
                return .{
                    .start_seconds = @min(fst, lst),
                    .end_seconds = @max(fst, lst),
                };
            }

            /// compute both the output extents for the curve exhaustively
            pub fn extents_output(
                self:@This(),
            ) opentime.interval.ContinuousTimeInterval
            {
                if (self.knots.len == 0) {
                    return .{ .start_seconds = 0, .end_seconds = 0 };
                }
                const fst = self.knots[0].out;
                const lst = self.knots[self.knots.len-1].out;
                return .{
                    .start_seconds = @min(fst, lst),
                    .end_seconds = @max(fst, lst),
                };
            }

            pub fn nearest_smaller_knot_index_input(
                self: @This(),
                input_ord: f32, 
            ) ?usize 
            {
                const last_index = self.knots.len-1;

                // out of bounds
                if (
                    self.knots.len == 0 
                    or (input_ord < self.knots[0].in)
                    or input_ord >= self.knots[last_index].in
                )
                {
                    return null;
                }

                // last knot is out of domain
                for (self.knots[0..last_index], self.knots[1..], 0..) 
                    |knot, next_knot, index| 
                {
                    if ( knot.in <= input_ord and input_ord < next_knot.in) 
                    {
                        return index;
                    }
                }

                return null;
            }

            /// find the nearest knot to the output value that is before the 
            /// value in the input space
            pub fn nearest_smaller_knot_index_output(
                self: @This(),
                output_ord: opentime.Ordinate, 
            ) ?usize 
            {
                if (self.knots.len == 0) {
                    return null;
                }

                const last_index = self.knots.len-1;

                const ext_out = self.extents_output();

                // out of bounds
                if (
                    self.knots.len == 0 
                    or ext_out.overlaps_seconds(output_ord) == false
                )
                {
                    return null;
                }

                // last knot is out of domain
                for (self.knots[0..last_index], self.knots[1..], 0..) 
                    |knot, next_knot, index| 
                {
                    if (
                        (knot.out <= output_ord and output_ord < next_knot.out)
                        or (knot.out > output_ord and output_ord >= next_knot.out)
                    ) 
                    {
                        return index;
                    }
                }

                return null;
            }

            pub fn slope_kind(
                self: @This(),
            ) bezier_math.SlopeKind
            {
                return bezier_math.SlopeKind.compute(
                    self.knots[0],
                    self.knots[self.knots.len-1],
                );
            }

            /// compute the output ordinate at the input ordinate
            pub fn output_at_input(
                self: @This(),
                input_ord: opentime.Ordinate,
            ) error{OutOfBounds}!opentime.Ordinate 
            {
                if (self.nearest_smaller_knot_index_input(input_ord)) 
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
                if (input_ord == self.knots[0].in) {
                    return last_knot.out;
                }

                return error.OutOfBounds;
            }

            /// compute the input ordinate at the output ordinate
            pub fn input_at_output(
                self: @This(),
                output_ord: opentime.Ordinate,
            ) error{OutOfBounds}!opentime.Ordinate 
            {
                if (self.knots.len == 0) {
                    return error.OutOfBounds;
                }

                if (self.nearest_smaller_knot_index_output(output_ord)) 
                    |index| 
                {
                    return bezier_math.input_at_output_between(
                        output_ord,
                        self.knots[index],
                        self.knots[index+1],
                    );
                }

                // specially handle the endpoint
                const last_knot = self.knots[self.knots.len - 1];
                if ( output_ord == last_knot.out) {
                    return last_knot.in;
                }

                const first_knot = self.knots[0];
                if ( output_ord == first_knot.out) {
                    return first_knot.in;
                }

                return error.OutOfBounds;
            }

            /// trim the curve to a range in the input space
            pub fn trimmed_input(
                self: @This(),
                allocator: std.mem.Allocator,
                input_bounds: opentime.ContinuousTimeInterval,
            ) !Monotonic
            {
                var result = (
                    std.ArrayList(ControlPointType).init(allocator)
                );
                result.deinit();

                const ext = self.extents_input();

                const first_point = if (
                    input_bounds.start_seconds >= ext.start_seconds
                ) ControlPointType{
                    .in = input_bounds.start_seconds,
                    .out = try self.output_at_input(input_bounds.start_seconds),
                } else self.knots[0];
                try result.append(first_point);


                const last_point = if (
                    input_bounds.end_seconds < ext.end_seconds
                ) ControlPointType{ 
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

                return Monotonic{ 
                    .knots = try result.toOwnedSlice() 
                };
            }

            /// trim the curve to a range in the output space
            pub fn trimmed_output(
                self: @This(),
                allocator: std.mem.Allocator,
                output_bounds: opentime.ContinuousTimeInterval,
            ) !Monotonic
            {            
                var result = (
                    std.ArrayList(ControlPointType).init(allocator)
                );
                defer result.deinit();

                const ext = self.extents_output();

                const first_point = if (
                    output_bounds.start_seconds >= ext.start_seconds
                ) ControlPointType{
                    .in = try self.input_at_output(output_bounds.start_seconds),
                    .out = output_bounds.start_seconds,
                } else self.knots[0];
                try result.append(first_point);

                const last_point = if (
                    output_bounds.end_seconds < ext.end_seconds
                ) ControlPointType{ 
                    .in = try self.input_at_output(output_bounds.end_seconds),
                    .out = output_bounds.end_seconds,
                } else self.extents()[1];

                for (self.knots) 
                    |knot|
                {
                    if (
                        knot.out > first_point.out
                        and knot.out < last_point.out
                    ) {
                        try result.append(knot);
                    }
                }

                try result.append(last_point);

                return Monotonic{ 
                    .knots = try result.toOwnedSlice() 
                };
            }

            pub fn format(
                self: @This(),
                comptime _: []const u8,
                _: std.fmt.FormatOptions,
                writer: anytype,
            ) !void 
            {
                try writer.print("Linear.Monotonic{{\n  .knots: [\n", .{});

                for (self.knots, 0..)
                    |k, ind|
                {
                    if (ind > 0)
                    {
                        try writer.print(",\n", .{});
                    }
                    try writer.print("    {s}", .{ k});
                }

                try writer.print("\n  ]\n}}", .{});
            }

            pub fn split_at_input_ordinates(
                self: @This(),
                allocator: std.mem.Allocator,
                /// a sorted, ascending, list of points in the input space
                input_points: []const opentime.Ordinate,
            ) ![]const Monotonic
            {
                const ib = self.extents_input();

                if (
                    // empty
                    input_points.len == 0
                    // out of range
                    or input_points[0] > ib.end_seconds 
                    or input_points[input_points.len - 1] < ib.start_seconds
                )
                {
                    return &.{ try self.clone(allocator) };
                }

                var new_knot_slices = (
                    std.ArrayList([]ControlPointType).init(allocator)
                );
                defer new_knot_slices.deinit();

                var current_curve = (
                    std.ArrayList(ControlPointType).init(allocator)
                );
                defer current_curve.deinit();

                // search for first point that is in range
                var left_knot_ind:usize = 0;
                var left_knot = self.knots[left_knot_ind];

                // left knot is always in the list
                try current_curve.append(left_knot);

                var right_knot_ind:usize = 1;
                var right_knot = self.knots[right_knot_ind];

                for (input_points)
                    |in_pt|
                {
                    // point is before range, skip
                    if (
                        in_pt < ib.start_seconds 
                        or in_pt <= left_knot.in + generic_curve.EPSILON
                    ) 
                    {
                        continue;
                    }

                    // points are sorted, so once a point is out of range,
                    // split is done
                    if (in_pt > ib.end_seconds) {
                        break;
                    }

                    // move current pt until it is the point on the curve AFTER
                    // the input pt
                    while (
                        right_knot.in < in_pt 
                        and right_knot_ind < self.knots.len
                    ) : ({ right_knot_ind += 1; left_knot_ind += 1; })
                    {
                        left_knot = self.knots[left_knot_ind];
                        right_knot = self.knots[right_knot_ind];
                        try current_curve.append(left_knot);
                    }

                    if (right_knot_ind >= self.knots.len) {
                        break;
                    }

                    const new_knot = ControlPointType{
                        .in = in_pt,
                        .out = try self.output_at_input(in_pt),
                    };

                    try current_curve.append(new_knot);
                    try new_knot_slices.append(
                        try current_curve.toOwnedSlice(),
                    );

                    current_curve.clearRetainingCapacity();
                    try current_curve.append(new_knot);
                }

                try current_curve.appendSlice(self.knots[right_knot_ind..]);
                try new_knot_slices.append(
                    try current_curve.toOwnedSlice(),
                );
                errdefer new_knot_slices.deinit();

                var new_curves = (
                    std.ArrayList(Monotonic).init(allocator)
                );
                defer new_curves.deinit();

                for (new_knot_slices.items)
                    |new_knots|
                {
                    try new_curves.append(
                        .{
                            .knots = new_knots,
                        },
                    );
                }

                return try new_curves.toOwnedSlice();
            }


        };

        /// dupe the provided points into the result
        pub fn init(
            allocator: std.mem.Allocator,
            knots: []const ControlPointType
        ) !LinearType 
        {
            return LinearType{
                .knots = try allocator.dupe(
                    ControlPointType,
                    knots,
                ) 
            };
        }

        /// initialize an identity LinearType with knots at the specified input
        /// ordinates
        pub fn init_identity(
            allocator: std.mem.Allocator,
            knot_input_ords:[]const opentime.Ordinate
        ) !LinearType.Monotonic 
        {
            var result = std.ArrayList(ControlPointType).init(
                allocator,
            );
            for (knot_input_ords) 
                |t| 
            {
                try result.append(.{.in = t, .out = t});
            }

            return LinearType.Monotonic{
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

        pub fn clone(
            self: @This(),
            allocator: std.mem.Allocator
        ) !LinearType
        {
            return .{ 
                .knots = try allocator.dupe(
                    ControlPointType,
                    self.knots
                ),
            };
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

        /// split this curve into monotonic curves over output.  Splits
        /// whenever the slope changes between rising, falling or flat.
        pub fn split_at_critical_points(
            self: @This(),
            allocator: std.mem.Allocator,
        ) ![]const Monotonic
        {

            // @TODO: this doesn't handle curves with vertical segments,
            //        repeated knots, etc.

            var result = std.ArrayList(
                Monotonic
            ).init(allocator);

            // single segment line is monotonic by definition
            if (self.knots.len < 3) {
                try result.append(
                    .{
                        .knots = try allocator.dupe(
                            ControlPoint,
                            self.knots
                        ), 
                    }
                );
                return try result.toOwnedSlice();
            }

            var splits = std.ArrayList(
                []ControlPointType
            ).init(allocator);
            defer splits.deinit();

            var segment_start_index: usize = 0;
            var slope = bezier_math.SlopeKind.compute(
                self.knots[0],
                self.knots[1]
            );

            for (self.knots[1..self.knots.len-1], 2.., self.knots[2..])
                |left, right_ind, right|
            {
                const new_slope = bezier_math.SlopeKind.compute(
                    left,
                    right
                );

                if (new_slope != slope)
                {
                    try splits.append(
                        self.knots[segment_start_index..right_ind]
                    );

                    // because the slope changes between the left and the right
                    // index, the left index is the last knot in the left
                    // segment and the first knot in the right.  Slice indices
                    // are left inclusive and right exclusive, so the slice
                    // ENDS on the right index but starts on the previous index
                    segment_start_index = right_ind-1;
                }
                slope = new_slope;
            }

            try splits.append(self.knots[segment_start_index..]);

            for (splits.items)
                |new_knots|
            {
                try result.append(
                    .{
                        .knots = try allocator.dupe(
                            ControlPointType,
                            new_knots,
                        ) 
                    }
                );
            }

            return try result.toOwnedSlice();
        }
    };
}

pub const Linear = LinearOf(ControlPoint);

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
    const allocator = std.testing.allocator;

    const ident = Linear.Monotonic{
        .knots = &.{ 
            .{ .in = 0, .out = 0, },
            .{ .in = 100, .out = 100, },
        },
    };

    {
        const right_overhang_lin = Linear.Monotonic{
            .knots = &.{
                .{ .in = -10, .out = -10},
                .{ .in = 30, .out = 10},
            },
        };

        const result = try join(
            allocator,
            .{
                .a2b = right_overhang_lin,
                .b2c = ident,
            },
        );
        defer result.deinit(allocator);

        try expectEqual(@as(usize, 2), result.knots.len);

        try expectEqual(@as(f32, 10), result.knots[0].in);
        try expectEqual(@as(f32, 0), result.knots[0].out);

        try expectEqual(@as(f32, 30), result.knots[1].in);
        try expectEqual(@as(f32, 10), result.knots[1].out);
    }

    {
        const left_overhang_lin = Linear.Monotonic{
            .knots = &.{ 
                .{ .in = 90, .out = 90},
                .{ .in = 110, .out = 130},
            },
        };

        const result = try join(
            allocator,
            .{ 
                .a2b = left_overhang_lin,
                .b2c = ident,
            },
        );
        defer result.deinit(allocator); 

        try expectEqual(@as(usize, 2), result.knots.len);

        try expectEqual(@as(f32, 90), result.knots[0].in);
        try expectEqual(@as(f32, 90), result.knots[0].out);

        try expectEqual(@as(f32, 95),  result.knots[1].in);
        try expectEqual(@as(f32, 100), result.knots[1].out);
    }

    // @TODO: add third test case, with right AND left overhang
}

test "Linear: projection_test - compose to identity" 
{
    const allocator = std.testing.allocator;

    const fst= Linear.Monotonic{
        .knots = &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 4, .out = 8, },
        }
    };

    const snd= Linear.Monotonic{
        .knots = &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 8, .out = 4, },
        },
    };

    const result = try join(
        allocator,
        .{
            .a2b = snd,
            .b2c = fst,
        },
    );
    defer result.deinit(allocator); 

    try expectEqual(@as(f32, 8), result.knots[1].in);
    try expectEqual(@as(f32, 8), result.knots[1].out);

    var x:f32 = 0;
    while (x < 1) 
        : (x += 0.1)
    {
        try expectApproxEqAbs(
            x,
            try result.output_at_input(x),
            generic_curve.EPSILON
        );
    }
}

test "Linear to Monotonic leak test"
{
    const allocator = std.testing.allocator;

    const src =  try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 5 },
            .{ .in = 10, .out = 5 },
        },
    );
    const monotonics = (
        try src.split_at_critical_points(allocator)
    );

    for (monotonics)
        |m|
    {
        m.deinit(allocator);
    }
    allocator.free(monotonics);
    src.deinit(allocator);
}

test "Linear to Monotonic Test"
{
    const allocator = std.testing.allocator;

    const TestCase = struct {
        name: []const u8,
        curve: Linear,
        monotonic_splits: usize,
    };
    const tests: []const TestCase = &.{
        .{
            .name = "flat",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .{ .in = 0, .out = 5 },
                    .{ .in = 10, .out = 5 },
                },
            ),
            .monotonic_splits = 1,
        },
        .{
            .name = "rising",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .{ .in = 0, .out = 0 },
                    .{ .in = 10, .out = 10 },
                },
            ),
            .monotonic_splits = 1,
        },
        .{
            .name = "rising_falling",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .{ .in = 0, .out = 0 },
                    .{ .in = 10, .out = 10 },
                    .{ .in = 20, .out = 0 },
                },
            ),
            .monotonic_splits = 2,
        },
        .{
            .name = "rising_flat_falling",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .{ .in = 0, .out = 0 },
                    .{ .in = 10, .out = 10 },
                    .{ .in = 20, .out = 10 },
                    .{ .in = 30, .out = 0 },
                },
            ),
            .monotonic_splits = 3,
        },
        .{
            .name = "flat_falling",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .{ .in = 0, .out = 10 },
                    .{ .in = 10, .out = 10 },
                    .{ .in = 20, .out = 0 },
                },
            ),
            .monotonic_splits = 2,
        },
    };
    for (tests)
        |t|
    {
        errdefer std.debug.print(
            "error with test: {s}\n",
            .{ t.name }
        );
        const monotonic_curves = (
            try t.curve.split_at_critical_points(allocator)
        );
        defer {
            for (monotonic_curves)
                |mc|
            {
                mc.deinit(allocator);
            }
            allocator.free(monotonic_curves);
            t.curve.deinit(allocator);
        }

        const measured = monotonic_curves.len;

        try std.testing.expectEqual(
            t.monotonic_splits,
            measured
        );
    }
}

/// given two monotonic curves, one that maps spaces "a"-> space "b" and a
/// second that maps space "b" to space "c", build a new curve that maps space
/// "a" to space "c"
pub fn join(
    allocator: std.mem.Allocator,
    curves: struct{
        a2b: Linear.Monotonic,
        b2c: Linear.Monotonic,
    },
) !Linear.Monotonic
{
    // compute domain of projection
    const a2b_b_extents = curves.a2b.extents_output();
    const b2c_b_extents = curves.b2c.extents_input();

    const b_bounds = opentime.interval.intersect(
        a2b_b_extents,
        b2c_b_extents,
    ) orelse return .{.knots = &.{} };

    // trim curves to domain
    const a2b_trimmed = (
        try curves.a2b.trimmed_output(
            allocator,
            b_bounds,
        )
    );
    defer a2b_trimmed.deinit(allocator);

    const b2c_trimmed = (
        try curves.b2c.trimmed_input(
            allocator,
            b_bounds,
        )
    );
    defer b2c_trimmed.deinit(allocator);

    // splits
    var cursor_a2b:usize = 0;
    var cursor_b2c:usize = 0;

    const total_possible_knots = (
        a2b_trimmed.knots.len
        + b2c_trimmed.knots.len
    );

    var result_knots = std.ArrayList(
        ControlPoint
    ).init(allocator);
    try result_knots.ensureTotalCapacity(total_possible_knots);

    while (
        cursor_a2b < a2b_trimmed.knots.len
        and cursor_b2c < b2c_trimmed.knots.len
    )
    {
        const a2b_k = a2b_trimmed.knots[cursor_a2b];
        const b2c_k = b2c_trimmed.knots[cursor_b2c];

        const a2b_b = a2b_k.out;
        const b2c_b = b2c_k.in;

        if (a2b_b == b2c_b) 
        {
            cursor_a2b += 1;
            cursor_b2c += 1;

            result_knots.appendAssumeCapacity(
                .{
                    .in = a2b_k.in,
                    .out = b2c_k.out,
                }
            );
        }
        else if (a2b_b < b2c_b) 
        {
            cursor_a2b += 1;

            result_knots.appendAssumeCapacity(
                .{
                    .in = a2b_k.in,
                    .out = try b2c_trimmed.output_at_input(a2b_b),
                }
            );
        }
        else 
        {
            // b2c_b < a2b_b
            cursor_b2c += 1;

            result_knots.appendAssumeCapacity(
                .{
                    .in = try a2b_trimmed.input_at_output(b2c_b),
                    .out = b2c_k.out,
                }
            );
        }
    }

    return .{
        .knots = try result_knots.toOwnedSlice(),
    };
}

test "Linear Join ident -> held"
{
    const allocator = std.testing.allocator;

    const ident = try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 0 },
            .{ .in = 10, .out = 10 },
        },
    );
    defer ident.deinit(allocator);

    const held = try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 5 },
            .{ .in = 10, .out = 5 },
        },
    );
    defer held.deinit(allocator);

    const ident_monos = (
        try ident.split_at_critical_points(allocator)
    );
    const held_monos = (
        try held.split_at_critical_points(allocator)
    );
    defer {
        ident_monos[0].deinit(allocator);
        allocator.free(ident_monos);
        held_monos[0].deinit(allocator);
        allocator.free(held_monos);
    }

    {
        const result = try join(
            allocator,
            .{
                .a2b = ident_monos[0],
                .b2c = held_monos[0],
            },
        );
        defer result.deinit(allocator);

        const result_extents = result.extents();

        try std.testing.expectEqual(
            5,
            result_extents[0].out,
        );
        try std.testing.expectEqual(
            5,
            result_extents[1].out,
        );
    }

    {
        const result = try join(
            allocator,
            .{
                .a2b = held_monos[0],
                .b2c = ident_monos[0],
            },
        );
        defer result.deinit(allocator);

        const result_extents = result.extents();

        try std.testing.expectEqual(
            5,
            result_extents[0].out,
        );
        try std.testing.expectEqual(
            5,
            result_extents[1].out,
        );
    }
}

test "Linear Join held -> non-ident"
{
    const allocator = std.testing.allocator;

    const doubler = try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 0 },
            .{ .in = 10, .out = 20 },
            .{ .in = 20, .out = 40 },
        },
    );
    defer doubler.deinit(allocator);

    const held = try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 5 },
            .{ .in = 20, .out = 5 },
        },
    );
    defer held.deinit(allocator);

    const doubler_monos = (
        try doubler.split_at_critical_points(allocator)
    );
    const held_monos = (
        try held.split_at_critical_points(allocator)
    );
    defer {
        doubler_monos[0].deinit(allocator);
        allocator.free(doubler_monos);
        held_monos[0].deinit(allocator);
        allocator.free(held_monos);
    }

    {
        const result = try join(
            allocator,
            .{
                .a2b = doubler_monos[0],
                .b2c = held_monos[0],
            },
        );
        defer result.deinit(allocator);

        const result_extents = result.extents();

        try std.testing.expectEqual(
            5,
            result_extents[0].out,
        );
        try std.testing.expectEqual(
            5,
            result_extents[1].out,
        );
    }

    {
        const result = try join(
            allocator,
            .{
                .a2b = held_monos[0],
                .b2c = doubler_monos[0],
            },
        );
        defer result.deinit(allocator);

        const result_extents = result.extents();

        try std.testing.expectEqual(
            10,
            result_extents[0].out,
        );
        try std.testing.expectEqual(
            10,
            result_extents[1].out,
        );
    }
}

test "Monotonic Trimmed Input"
{
    const allocator = std.testing.allocator;

    const ident = try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 0 },
            .{ .in = 10, .out = 10 },
        },
    );
    defer ident.deinit(allocator);

    const ident_monos = (
        try ident.split_at_critical_points(allocator)
    );
    defer {
        for (ident_monos)
            |m|
        {
            m.deinit(allocator);
        }
        allocator.free(ident_monos);
    }

    const ident_mono = ident_monos[0];

    const TestCase = struct{
        name: []const u8,
        target_range: opentime.interval.ContinuousTimeInterval,
        expected_range: opentime.interval.ContinuousTimeInterval,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target_range = .{
                .start_seconds = -1,
                .end_seconds = 11,
            },
            .expected_range = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
        },
        .{
            .name = "left trim",
            .target_range = .{
                .start_seconds = 3,
                .end_seconds = 11,
            },
            .expected_range = .{
                .start_seconds = 3,
                .end_seconds = 10,
            },
        },
        .{
            .name = "right trim",
            .target_range = .{
                .start_seconds = -1,
                .end_seconds = 8,
            },
            .expected_range = .{
                .start_seconds = 0,
                .end_seconds = 8,
            },
        },
    };

    for (tests)
        |t|
    {
        const result = try ident_mono.trimmed_input(
            allocator,
            t.target_range
        );
        defer result.deinit(allocator);

        errdefer std.debug.print(
            "test: {s}\n result: {s}\n",
            .{
                t.name,
                result.extents_input(),
            },
        );
        
        try std.testing.expectEqual(
            t.expected_range.start_seconds,
            result.extents_input().start_seconds,
        );
        try std.testing.expectEqual(
            t.expected_range.end_seconds,
            result.extents_input().end_seconds,
        );
    }
}

test "Monotonic Trimmed Output"
{
    const allocator = std.testing.allocator;

    const ident = try Linear.init(
        allocator,
        &.{
            .{ .in = 0, .out = 0 },
            .{ .in = 10, .out = 10 },
        },
    );
    defer ident.deinit(allocator);

    const ident_monos = (
        try ident.split_at_critical_points(allocator)
    );
    defer {
        for (ident_monos)
            |m|
        {
            m.deinit(allocator);
        }
        allocator.free(ident_monos);
    }

    const ident_mono = ident_monos[0];

    const TestCase = struct{
        name: []const u8,
        target_range: opentime.interval.ContinuousTimeInterval,
        expected_range: opentime.interval.ContinuousTimeInterval,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target_range = .{
                .start_seconds = -1,
                .end_seconds = 11,
            },
            .expected_range = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
        },
        .{
            .name = "left trim",
            .target_range = .{
                .start_seconds = 3,
                .end_seconds = 11,
            },
            .expected_range = .{
                .start_seconds = 3,
                .end_seconds = 10,
            },
        },
        .{
            .name = "right trim",
            .target_range = .{
                .start_seconds = -1,
                .end_seconds = 8,
            },
            .expected_range = .{
                .start_seconds = 0,
                .end_seconds = 8,
            },
        },
    };

    for (tests)
        |t|
    {
        const result = try ident_mono.trimmed_output(
            allocator,
            t.target_range
        );
        defer result.deinit(allocator);

        errdefer std.debug.print(
            "test: {s}\n result: {s}\n",
            .{
                t.name,
                result.extents_output(),
            },
        );
        
        try std.testing.expectEqual(
            t.expected_range.start_seconds,
            result.extents_output().start_seconds,
        );
        try std.testing.expectEqual(
            t.expected_range.end_seconds,
            result.extents_output().end_seconds,
        );
    }
}

test "Linear.Monotonic.nearest_smaller_knot_index_output"
{
    const falling = Linear.Monotonic{
        .knots = &.{
            .{ .in = 10, .out = 10 },
            .{ .in = 20, .out = 0 },
            .{ .in = 30, .out = -10 },
        },
    };

    {
        const measured = (
            falling.nearest_smaller_knot_index_output(-3) 
            orelse return error.OutOfBounds
        );

        try std.testing.expectEqual(1, measured);
    }

    {
        const measured = (
            falling.nearest_smaller_knot_index_input(23) 
            orelse return error.OutOfBounds
        );

        try std.testing.expectEqual(1, measured);
    }

    const rising = Linear.Monotonic{
        .knots = &.{
            .{ .in = 10, .out = 0 },
            .{ .in = 20, .out = 10 },
            .{ .in = 30, .out = 20 },
        },
    };

    {
        const measured = (
            rising.nearest_smaller_knot_index_output(3) 
            orelse return error.OutOfBounds
        );

        try std.testing.expectEqual(0, measured);
    }

    {
        const measured = (
            rising.nearest_smaller_knot_index_input(23) 
            orelse return error.OutOfBounds
        );

        try std.testing.expectEqual(1, measured);
    }
}

test "Linear.Monotonic.SplitAtCriticalPoints"
{
    const allocator = std.testing.allocator;

    const crv = try bezier_curve.Bezier.init(
        allocator,
        &.{
            .{
                .p0 = .{ .in = 1, .out = 0 },
                .p1 = .{ .in = 1, .out = 5 },
                .p2 = .{ .in = 5, .out = 5 },
                .p3 = .{ .in = 5, .out = 1 },
            }
        },
    );
    defer crv.deinit(allocator);
    
    const lin = try crv.linearized(allocator);
    defer lin.deinit(allocator);

    const lin_split = try lin.split_at_critical_points(
        allocator
    );
    defer allocator.free(lin_split);

    var last = lin_split[0].knots[0].in;
    for (lin_split)
        |lin_crv|
    {
        // also clean up the curves
        defer lin_crv.deinit(allocator);
        const range = lin_crv.extents_input();
        try std.testing.expectEqual(last, range.start_seconds);
        last = range.end_seconds;
    }
}

test "Linear.Monotonic.split_at_input_ordinates"
{
    const allocator = std.testing.allocator;

    const crv = Linear.Monotonic{
        .knots = &.{
            .{ .in = 0, .out = 0, },
            .{ .in = 2, .out = 4, },
        },
    };

    const new_curves = try crv.split_at_input_ordinates(
        allocator,
        &.{ -1, 0, 1.0, 1.5, 2.0, 2.1, 4.5 },
    );
    defer {
        for (new_curves)
            |m|
        {
            m.deinit(allocator);
        }
        allocator.free(new_curves);
    }

    try std.testing.expectEqual(
        4,
        new_curves.len,
    );
}
test "Linear.Monotonic: slope_kind"
{
    {
        const crv_rising = Linear.Monotonic{
            .knots = &.{
                .{ .in = 0, .out = 0, },
                .{ .in = 2, .out = 4, },
            },
        };

        try std.testing.expectEqual(
            .rising,
            crv_rising.slope_kind(),
        );
    }

    {
        const crv_flat = Linear.Monotonic{
            .knots = &.{
                .{ .in = 0, .out = 2, },
                .{ .in = 2, .out = 2, },
            },
        };

        try std.testing.expectEqual(
            .flat,
            crv_flat.slope_kind(),
        );
    }

    {
        const crv_falling = Linear.Monotonic{
            .knots = &.{
                .{ .in = 0, .out = 4, },
                .{ .in = 2, .out = 0, },
            },
        };

        try std.testing.expectEqual(
            .falling,
            crv_falling.slope_kind(),
        );
    }
}
