//! Linear curves are made of right-met connected line segments

const std = @import("std");

const opentime = @import("opentime");

const bezier_curve = @import("bezier_curve.zig");
const bezier_math = @import("bezier_math.zig");
const control_point = @import("control_point.zig");

/// A polyline that is linearly interpolated between knots
pub fn LinearOf(
    comptime ControlPointType: type,
) type
{
    return struct {
        /// knots of the curve
        knots: []const ControlPointType,

        const LinearType = LinearOf(ControlPointType);

        /// An empty curve with no knots.
        pub const empty = LinearType {
            .knots = &.{},
        };

        /// Immutable Monotonic form of the Linear curve.  Constructed by
        /// splitting a Linear with split_at_critical_points
        pub const Monotonic = struct {
            /// knots of the curve
            knots: []const ControlPointType,

            /// An empty curve with no knots.
            pub const empty = Monotonic {
                .knots =  &.{} 
            };

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
            ) ?[2]ControlPointType 
            {
                if (self.knots.len == 0)
                {
                    return null;
                }

                var min:ControlPointType = self.knots[0];
                var max:ControlPointType = self.knots[0];

                inline for (&.{ self.knots[0], self.knots[self.knots.len-1] }) 
                    |knot| 
                {
                    min = .{
                        .in = opentime.min(min.in, knot.in),
                        .out = opentime.min(min.out, knot.out),
                    };
                    max = .{
                        .in = opentime.max(max.in, knot.in),
                        .out = opentime.max(max.out, knot.out),
                    };
                }
                return .{ min, max };
            }

            /// compute both the input extents for the curve exhaustively
            pub fn extents_input(
                self:@This(),
            ) ?opentime.ContinuousInterval
            {
                if (self.knots.len < 1) {
                    return null;
                }
                const fst = self.knots[0].in;
                const lst = self.knots[self.knots.len-1].in;
                return .{
                    .start = opentime.min(fst, lst),
                    .end = opentime.max(fst, lst),
                };
            }

            /// compute both the output extents for the curve exhaustively
            pub fn extents_output(
                self:@This(),
            ) ?opentime.ContinuousInterval
            {
                if (self.knots.len == 0) {
                    return null;
                }
                const fst = self.knots[0].out;
                const lst = self.knots[self.knots.len-1].out;
                return .{
                    .start = opentime.min(fst, lst),
                    .end = opentime.max(fst, lst),
                };
            }

            const NearestIndices = struct {
                lt_output: usize,
                gt_output: usize,
            };

            pub fn nearest_knot_indices_output(
                self: @This(),
                output_ord: ControlPointType.OrdinateType, 
            ) ?NearestIndices
            {
                const ob = (
                    self.extents_output() 
                    orelse return null
                );

                // out of bounds
                if (
                    self.knots.len == 0 
                    or opentime.gt(output_ord, ob.end)
                    or opentime.lt(output_ord, ob.start)
                )
                {
                    return null;
                }

                var befre_pts = self.knots[0..self.knots.len-1];
                var after_pts = self.knots[1..];

                const slope = self.slope_kind();

                if (slope == .falling) {
                    after_pts = befre_pts;
                    befre_pts = self.knots[1..];
                }

                // last knot is out of domain
                for (befre_pts, after_pts, 0..) 
                    |before, after, index| 
                {
                    if (
                        opentime.lteq(before.out, output_ord) 
                        and opentime.lteq(output_ord, after.out) 
                    )
                    {
                        if (slope == .rising) 
                        {
                            return .{
                                .lt_output = index,
                                .gt_output = index + 1,
                            };
                        } 
                        else 
                        {
                            return .{
                                .lt_output = index + 1,
                                .gt_output = index,
                            };
                        }
                    }
                }

                return null;
            }

            pub fn nearest_smaller_knot_index_input(
                self: @This(),
                input_ord: ControlPointType.OrdinateType, 
            ) ?usize 
            {
                const last_index = self.knots.len-1;

                // out of bounds
                if (
                    self.knots.len == 0 
                    or (opentime.lt(input_ord, self.knots[0].in))
                    or opentime.gteq(input_ord, self.knots[last_index].in)
                )
                {
                    return null;
                }

                // last knot is out of domain
                for (self.knots[0..last_index], self.knots[1..], 0..) 
                    |knot, next_knot, index| 
                {
                    if (
                        opentime.lteq(knot.in, input_ord) 
                        and opentime.lt(input_ord, next_knot.in)
                    )
                    {
                        return index;
                    }
                }

                return null;
            }

            pub fn slope_kind(
                self: @This(),
            ) SlopeKind
            {
                return SlopeKind.compute(
                    self.knots[0],
                    self.knots[self.knots.len-1],
                );
            }

            /// compute the output ordinate at the input ordinate
            pub fn output_at_input(
                self: @This(),
                input_ord: opentime.Ordinate,
            ) opentime.ProjectionResult
            {
                const slope = self.slope_kind();
                if (
                    slope == .flat 
                    and (
                        self.extents_input() 
                        orelse return .out_of_bounds
                    ).overlaps(input_ord)
                ) 
                {
                    const self_ob = (
                        self.extents_output() 
                        orelse return .out_of_bounds
                    );
                    
                    if (self_ob.is_instant()) {
                        return .{
                            .success_ordinate = self_ob.start,
                        };
                    }

                    return .{
                        .success_interval = self_ob,
                    };
                }

                if (self.nearest_smaller_knot_index_input(input_ord)) 
                    |index| 
                {
                    return .{
                        .success_ordinate = bezier_math.output_at_input_between(
                            input_ord,
                            self.knots[index],
                            self.knots[index+1],
                        ),
                    };
                }

                // specially handle the endpoint
                const last_knot = self.knots[self.knots.len - 1];
                if (opentime.eql(input_ord, last_knot.in)) 
                {
                    return .{
                        .success_ordinate = last_knot.out,
                    };
                }

                if (opentime.eql(input_ord, self.knots[0].in))
                {
                    return .{
                        .success_ordinate = last_knot.out,
                    };
                }

                return .out_of_bounds;
            }

            /// compute the input ordinate at the output ordinate
            pub fn input_at_output(
                self: @This(),
                output_ord: opentime.Ordinate,
            ) opentime.ProjectionResult
            {
                if (self.knots.len == 0) {
                    return .out_of_bounds;
                }

                if (self.nearest_knot_indices_output(output_ord)) 
                    |indices| 
                {
                    return .{
                        .success_ordinate = bezier_math.input_at_output_between(
                            output_ord,
                            self.knots[indices.lt_output],
                            self.knots[indices.gt_output],
                        )
                    };
                }
                
                // specially handle the endpoint
                const last_knot = self.knots[self.knots.len - 1];
                if (opentime.eql(output_ord, last_knot.out)) {
                    return .{ .success_ordinate = last_knot.in };
                }

                const first_knot = self.knots[0];
                if (opentime.eql(output_ord, first_knot.out)) {
                    return .{ .success_ordinate = first_knot.in };
                }

                return .out_of_bounds;
            }

            /// trim the curve to a range in the input space
            pub fn trimmed_input(
                self: @This(),
                allocator: std.mem.Allocator,
                input_bounds: opentime.ContinuousInterval,
            ) !Monotonic
            {
                const current_bounds = (
                    self.extents_input()
                    orelse return .empty
                );

                if (
                    opentime.gteq(current_bounds.start, input_bounds.start)
                    and opentime.lteq(current_bounds.end, input_bounds.end)
                ) {
                    return try self.clone(allocator);
                }

                var result: std.ArrayList(ControlPointType) = .empty;
                defer result.deinit(allocator);

                // cannot have output bounds but not input bounds (previous
                // check on current bounds makes sure that current_bounds
                // exists)
                const ext = self.extents_input().?;

                const first_point = if (
                    opentime.gteq(input_bounds.start, ext.start)
                ) ControlPointType{
                    .in = input_bounds.start,
                    .out = try self.output_at_input(input_bounds.start).ordinate(),
                } else self.knots[0];
                try result.append(allocator,first_point);

                const last_point = if (
                    opentime.lt(input_bounds.end, ext.end)
                ) ControlPointType{ 
                    .in = input_bounds.end,
                    .out = try self.output_at_input(
                        input_bounds.end
                    ).ordinate(),
                } else self.extents().?[1];

                for (self.knots) 
                    |knot|
                {
                    if (
                        opentime.gt(knot.in, first_point.in)
                        and opentime.lt(knot.in, last_point.in)
                    ) {
                        try result.append(allocator,knot);
                    }
                }

                try result.append(allocator,last_point);

                const out = Monotonic{ 
                    .knots = 
                        try result.toOwnedSlice(allocator),
                };

                return out;
            }

            /// trim the curve to a range in the output space
            pub fn trimmed_output(
                self: @This(),
                allocator: std.mem.Allocator,
                output_bounds: opentime.ContinuousInterval,
            ) !Monotonic
            {            
                if (self.knots.len < 2) {
                    return try self.clone(allocator);
                }

                const ext = (
                    self.extents_output()
                    orelse return .empty
                );
                if (
                    opentime.lt(ext.end,output_bounds.end)
                    and opentime.gt(ext.start, output_bounds.start)
                ) {
                    return try self.clone(allocator);
                }

                const segment_slope = SlopeKind.compute(
                    self.knots[0],
                    self.knots[self.knots.len-1],
                );

                if (
                    segment_slope == .flat
                    and (output_bounds.overlaps(self.knots[0].out))
                ) 
                {
                    return try self.clone(allocator);
                }

                var knots: std.ArrayList(ControlPointType) = .empty;
                defer knots.deinit(allocator);

                try knots.appendSlice(allocator, self.knots);

                // always process as if it was rising
                if (segment_slope == .falling) {
                    std.mem.reverse(ControlPointType, knots.items);
                }

                var result: std.ArrayList(ControlPointType) = .empty;
                defer result.deinit(allocator);

                const first_point = if (
                    opentime.gteq(output_bounds.start, ext.start)
                ) ControlPointType{
                    .in = try self.input_at_output(output_bounds.start).ordinate(),
                    .out = output_bounds.start,
                } else knots.items[0];
                try result.append(allocator, first_point);

                const last_point = if (
                    opentime.lt(output_bounds.end, ext.end)
                ) ControlPointType{ 
                    .in = try self.input_at_output(output_bounds.end).ordinate(),
                    .out = output_bounds.end,
                } else knots.items[knots.items.len-1];

                for (knots.items) 
                    |knot|
                {
                    if (
                        opentime.gt(knot.out, first_point.out)
                        and opentime.lt(knot.out, last_point.out)
                    ) {
                        try result.append(allocator,knot);
                    }
                }

                try result.append(allocator,last_point);

                if (segment_slope == .falling) {
                    std.mem.reverse(ControlPointType, result.items);
                }

                const out = Monotonic{ 
                    .knots = 
                        try result.toOwnedSlice(allocator) 
                };

                return out;
            }

            pub fn format(
                self: @This(),
                writer: *std.Io.Writer,
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
                    try writer.print("    {f}", .{ k});
                }

                try writer.print("\n  ]\n}}", .{});
            }

            /// Split this curve on any points' input ordiantes that are
            /// between the boundaries.
            ///
            /// Assumes that th `input_points_to_split_on` are sorted.  
            ///
            /// Caller owns the memory.  Always returns freshly allocated data
            /// even if no splits occured.
            pub fn split_at_each_input_ord(
                self: @This(),
                allocator: std.mem.Allocator,
                /// a sorted, ascending, list of points in the input space
                input_points: []const opentime.Ordinate,
            ) ![]const Monotonic
            {
                const ib = (
                    self.extents_input()
                    orelse return &.{}
                );

                if (
                    // empty
                    input_points.len == 0
                    // out of range
                    or opentime.gt(input_points[0], ib.end)
                    or opentime.lt(input_points[input_points.len - 1], ib.start)
                )
                {
                    // a clone of self (no splits)
                    return &.{ try self.clone(allocator) };
                }

                // slices of knots that will become curves
                var new_knot_slices: std.ArrayList([]ControlPointType) = .empty;
                defer new_knot_slices.deinit(allocator);

                // the current curve being appended to
                var current_curve: std.ArrayList(ControlPointType) = .empty;
                defer current_curve.deinit(allocator,);

                // search for first point that is in range
                var last_appended_index:usize = 0;
                var last_appended_knot = self.knots[last_appended_index];

                // left knot is always in the list
                try current_curve.append(allocator,last_appended_knot);

                var next_knot_index:usize = 1;
                var next_knot = self.knots[next_knot_index];

                for (input_points)
                    |in_pt|
                {
                    // point is before range, skip
                    if (
                        opentime.lt(in_pt, ib.start)
                        or opentime.lteq(in_pt, last_appended_knot.in)
                    )
                    {
                        continue;
                    }

                    // points are sorted, so once a point is out of range,
                    // split is done
                    if (opentime.gt(in_pt, ib.end)) {
                        break;
                    }

                    // move current pt until it is the point on the curve AFTER
                    // the input pt
                    while (
                        opentime.lt(next_knot.in, in_pt)
                        and opentime.lt(next_knot_index, self.knots.len)
                    ) : ({ next_knot_index += 1; last_appended_index += 1; })
                    {
                        last_appended_knot = self.knots[last_appended_index];
                        next_knot = self.knots[next_knot_index];
                        try current_curve.append(
                            allocator,
                            last_appended_knot,
                        );
                    }

                    // insert the new knot
                    const new_knot = ControlPointType{
                        .in = in_pt,
                        .out = try self.output_at_input(in_pt).ordinate(),
                    };

                    try current_curve.append(allocator,new_knot);

                    try new_knot_slices.append(
                        allocator,
                        try current_curve.toOwnedSlice(allocator),
                    );

                    current_curve.clearRetainingCapacity();
                    try current_curve.append(allocator,new_knot);

                    // if the next knot is past or at the end of the knots,
                    // append it and break.  The rest of the input knots are
                    // outside of the range.
                    if (next_knot_index >= self.knots.len) {
                        try current_curve.append(allocator,next_knot);
                        break;
                    }
                }

                next_knot_index+=1;

                if (next_knot_index <= self.knots.len-1) {
                    try current_curve.appendSlice(
                        allocator,
                        self.knots[next_knot_index..],
                    );
                }

                if (current_curve.items.len > 1) {
                    try new_knot_slices.append(
                        allocator,
                        try current_curve.toOwnedSlice(allocator),
                    );
                }

                // build knot slices into curves
                var new_curves: std.ArrayList(Monotonic) = .empty;
                defer new_curves.deinit(allocator);

                for (new_knot_slices.items)
                    |new_knots|
                {
                    try new_curves.append(
                        allocator,
                        .{ .knots = new_knots },
                    );
                }

                return try new_curves.toOwnedSlice(allocator);
            }
        };

        /// dupe the provided points into the result
        pub fn init(
            allocator: std.mem.Allocator,
            knots: []const ControlPointType,
        ) !LinearType 
        {
            return LinearType{
                .knots = try allocator.dupe(
                    ControlPointType,
                    knots,
                ) 
            };
        }

        /// Initialize an identity LinearType with knots at the specified input
        /// ordinates.
        pub fn init_identity(
            allocator: std.mem.Allocator,
            knot_input_ords:[]const opentime.Ordinate.InnerType,
        ) !LinearType.Monotonic 
        {
            const out_knots = try allocator.alloc(
                ControlPointType,
                knot_input_ords.len,
            );

            for (knot_input_ords, out_knots) 
                |src_ord, *dst_knot| 
            {

                dst_knot.* = .{
                    .in = .init(src_ord),
                    .out = .init(src_ord), 
                };
            }

            return LinearType.Monotonic{
                .knots = out_knots,
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
            var result: std.ArrayList(Monotonic) = .empty;

            // single segment line is monotonic by definition
            if (self.knots.len < 3) {
                try result.append(
                    allocator,
                    .{
                        .knots = try allocator.dupe(
                            ControlPointType,
                            self.knots
                        ), 
                    }
                );
                return try result.toOwnedSlice(allocator);
            }

            var splits: std.ArrayList([]const ControlPointType) = .empty;
            defer splits.deinit(allocator);

            var segment_start_index: usize = 0;
            var slope = SlopeKind.compute(
                self.knots[0],
                self.knots[1]
            );

            for (self.knots[1..self.knots.len-1], 2.., self.knots[2..])
                |left, right_ind, right|
            {
                const new_slope = SlopeKind.compute(
                    left,
                    right
                );

                if (new_slope != slope)
                {
                    try splits.append(
                        allocator,
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

            try splits.append(
                allocator,
                self.knots[segment_start_index..],
            );

            for (splits.items)
                |new_knots|
            {
                try result.append(
                    allocator,
                    .{
                        .knots = try allocator.dupe(
                            ControlPointType,
                            new_knots,
                        ) 
                    }
                );
            }

            return try result.toOwnedSlice(allocator);
        }
    };
}

pub const Linear = LinearOf(control_point.ControlPoint);
pub const LinearF = LinearOf(control_point.ControlPoint_InnerType);

test "Linear: extents" 
{
    const crv = try Linear.init_identity(
        std.testing.allocator,
        &.{100, 200},
    );
    defer crv.deinit(std.testing.allocator);

    const bounds = crv.extents().?;

    try opentime.expectOrdinateEqual(
        100,
        bounds[0].in
    );
    try opentime.expectOrdinateEqual(
        200,
        bounds[1].in,
    );

    const bounds_input = crv.extents_input().?;
    try opentime.expectOrdinateEqual(
        100,
        bounds_input.start,
    );
    try opentime.expectOrdinateEqual(
        200,
        bounds_input.end,
    );
}

test "Linear: proj_ident" 
{
    const allocator = std.testing.allocator;

    const ident = Linear.Monotonic{
        .knots = &.{ 
            .init(.{ .in = 0, .out = 0, }),
            .init(.{ .in = 100, .out = 100, }),
        },
    };

    {
        const right_overhang_lin = Linear.Monotonic{
            .knots = &.{
                .init(.{ .in = -10, .out = -10}),
                .init(.{ .in = 30, .out = 10}),
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

        try std.testing.expectEqual(@as(usize, 2), result.knots.len);

        try opentime.expectOrdinateEqual(
            10,
            result.knots[0].in
        );
        try opentime.expectOrdinateEqual(
            0,
            result.knots[0].out
        );

        try opentime.expectOrdinateEqual(
            30,
            result.knots[1].in
        );
        try opentime.expectOrdinateEqual(
            10,
            result.knots[1].out
        );
    }

    {
        const left_overhang_lin = Linear.Monotonic{
            .knots = &.{ 
                .init(.{ .in = 90, .out = 90}),
                .init(.{ .in = 110, .out = 130}),
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

        try std.testing.expectEqual(@as(usize, 2), result.knots.len);

        try opentime.expectOrdinateEqual(
            opentime.Ordinate.init(90),
            result.knots[0].in
        );
        try opentime.expectOrdinateEqual(
            opentime.Ordinate.init(90),
            result.knots[0].out
        );

        try opentime.expectOrdinateEqual(
            opentime.Ordinate.init(95),
            result.knots[1].in
        );
        try opentime.expectOrdinateEqual(
            opentime.Ordinate.init(100),
            result.knots[1].out
        );
    }

    // @TODO: add third test case, with right AND left overhang
}

test "Linear: projection_test - compose to identity" 
{
    const allocator = std.testing.allocator;

    const fst= Linear.Monotonic{
        .knots = &.{
            .init(.{ .in = 0, .out = 0, }),
            .init(.{ .in = 4, .out = 8, }),
        }
    };

    const snd= Linear.Monotonic{
        .knots = &.{
            .init(.{ .in = 0, .out = 0, }),
            .init(.{ .in = 8, .out = 4, }),
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

    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(8),
        result.knots[1].in
    );
    try opentime.expectOrdinateEqual(
        opentime.Ordinate.init(8),
        result.knots[1].out
    );

    var x:opentime.Ordinate.InnerType = 0;
    while (x < 1) 
        : (x += 0.1)
    {
        try opentime.expectOrdinateEqual(
            opentime.Ordinate.init(x),
            try result.output_at_input(
                opentime.Ordinate.init(x)
            ).ordinate(),
        );
    }
}

test "Linear: to Monotonic leak test"
{
    const allocator = std.testing.allocator;

    const src =  try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 5 }),
            .init(.{ .in = 10, .out = 5 }),
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

test "Linear: to Monotonic Test"
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
                    .init(.{ .in = 0, .out = 5 }),
                    .init(.{ .in = 10, .out = 5 }),
                },
            ),
            .monotonic_splits = 1,
        },
        .{
            .name = "rising",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .init(.{ .in = 0, .out = 0 }),
                    .init(.{ .in = 10, .out = 10 }),
                },
            ),
            .monotonic_splits = 1,
        },
        .{
            .name = "rising_falling",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .init(.{ .in = 0, .out = 0 }),
                    .init(.{ .in = 10, .out = 10 }),
                    .init(.{ .in = 20, .out = 0 }),
                },
            ),
            .monotonic_splits = 2,
        },
        .{
            .name = "rising_flat_falling",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .init(.{ .in = 0, .out = 0 }),
                    .init(.{ .in = 10, .out = 10 }),
                    .init(.{ .in = 20, .out = 10 }),
                    .init(.{ .in = 30, .out = 0 }),
                },
            ),
            .monotonic_splits = 3,
        },
        .{
            .name = "flat_falling",  
            .curve = try Linear.init(
                allocator,
                &.{
                    .init(.{ .in = 0, .out = 10 }),
                    .init(.{ .in = 10, .out = 10 }),
                    .init(.{ .in = 20, .out = 0 }),
                },
            ),
            .monotonic_splits = 2,
        },
    };
    for (tests)
        |t|
    {
        errdefer opentime.dbg_print(@src(), 
            "error with test: {s}",
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

/// Given two monotonic curves, one that maps spaces "a"-> space "b" and a
/// second that maps space "b" to space "c", build a new curve that maps space
/// "a" to space "c".
pub fn join(
    allocator: std.mem.Allocator,
    curves: struct{
        a2b: Linear.Monotonic,
        b2c: Linear.Monotonic,
    },
) !Linear.Monotonic
{
    // compute domain of projection
    const a2b_b_extents = (
        curves.a2b.extents_output()
        orelse return .empty
    );
    const b2c_b_extents = (
        curves.b2c.extents_input()
        orelse return .empty
    );

    const b_bounds = opentime.interval.intersect(
        a2b_b_extents,
        b2c_b_extents,
    ) orelse return .empty;

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

    var result_knots: std.ArrayList(control_point.ControlPoint) = .empty;
    defer result_knots.deinit(allocator);

    try result_knots.ensureTotalCapacity(
        allocator,
        total_possible_knots,
    );

    while (
        cursor_a2b < a2b_trimmed.knots.len
        and cursor_b2c < b2c_trimmed.knots.len
    )
    {
        const a2b_k = a2b_trimmed.knots[cursor_a2b];
        const b2c_k = b2c_trimmed.knots[cursor_b2c];

        const a2b_b = a2b_k.out;
        const b2c_b = b2c_k.in;

        if (opentime.eql(a2b_b, b2c_b))
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
        else if (opentime.lt(a2b_b, b2c_b))
        {
            cursor_a2b += 1;

            result_knots.appendAssumeCapacity(
                .{
                    .in = a2b_k.in,
                    .out = try b2c_trimmed.output_at_input(a2b_b).ordinate(),
                }
            );
        }
        else 
        {
            // b2c_b < a2b_b
            cursor_b2c += 1;

            result_knots.appendAssumeCapacity(
                .{
                    .in = try a2b_trimmed.input_at_output(b2c_b).ordinate(),
                    .out = b2c_k.out,
                }
            );
        }
    }

    return .{
        .knots = (
            try result_knots.toOwnedSlice(allocator)
        ),
    };
}

test "Linear: Join ident -> held"
{
    const allocator = std.testing.allocator;

    const ident = try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 0 }),
            .init(.{ .in = 10, .out = 10 }),
        },
    );
    defer ident.deinit(allocator);

    const held = try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 5 }),
            .init(.{ .in = 10, .out = 5 }),
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

        const result_extents = (
            result.extents()
            orelse return error.NoExtents
        );

        try std.testing.expectEqual(
            opentime.Ordinate.init(5),
            result_extents[0].out,
        );
        try std.testing.expectEqual(
            opentime.Ordinate.init(5),
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

        const result_extents = (
            result.extents()
            orelse return error.NoExtents
        );

        try opentime.expectOrdinateEqual(
            5,
            result_extents[0].out,
        );
        try opentime.expectOrdinateEqual(
            5,
            result_extents[1].out,
        );
    }
}

test "Linear: Join held -> non-ident"
{
    const allocator = std.testing.allocator;

    const doubler = try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 0 }),
            .init(.{ .in = 10, .out = 20 }),
            .init(.{ .in = 20, .out = 40 }),
        },
    );
    defer doubler.deinit(allocator);

    const held = try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 5 }),
            .init(.{ .in = 20, .out = 5 }),
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

        const result_extents = (
            result.extents()
            orelse return error.NoExtents
        );

        try std.testing.expectEqual(
            opentime.Ordinate.init(5),
            result_extents[0].out,
        );
        try std.testing.expectEqual(
            opentime.Ordinate.init(5),
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

        const result_extents = (
            result.extents()
            orelse return error.NoExtents
        );

        try opentime.expectOrdinateEqual(
            10,
            result_extents[0].out,
        );
        try opentime.expectOrdinateEqual(
            10,
            result_extents[1].out,
        );
    }
}

test "Linear: Monotonic Trimmed Input"
{
    const allocator = std.testing.allocator;

    const ident = try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 0 }),
            .init(.{ .in = 10, .out = 10 }),
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
        target_range: opentime.interval.ContinuousInterval,
        expected_range: opentime.interval.ContinuousInterval,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target_range = 
                .init(
                    .{
                        .start = -1,
                        .end = 11,
                    }
                ),
            .expected_range = .init(
                .{
                    .start = 0,
                    .end = 10,
                }
            ),
        },
        .{
            .name = "left trim",
            .target_range = .init(
                .{
                .start = 3,
                .end = 11,
            }
            ),
            .expected_range = .init(
                .{
                    .start = 3,
                    .end = 10,
                }
            ),
        },
        .{
            .name = "right trim",
            .target_range = .init(
                .{
                    .start = -1,
                    .end = 8,
                }
            ),
            .expected_range = .init(
                .{
                    .start = 0,
                    .end = 8,
                }
            ),
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

        errdefer opentime.dbg_print(
            @src(), 
            "test: {s}\n result: {f}",
            .{
                t.name,
                result.extents_input(),
            },
        );
        
        try std.testing.expectEqual(
            t.expected_range.start,
            result.extents_input().?.start,
        );
        try std.testing.expectEqual(
            t.expected_range.end,
            result.extents_input().?.end,
        );
    }
}

test "Linear: Monotonic Trimmed Output"
{
    const allocator = std.testing.allocator;

    const ident = try Linear.init(
        allocator,
        &.{
            .init(.{ .in = 0, .out = 0 }),
            .init(.{ .in = 10, .out = 10 }),
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
        target_range: opentime.interval.ContinuousInterval,
        expected_range: opentime.interval.ContinuousInterval,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target_range = opentime.ContinuousInterval.init(
                .{
                    .start = -1,
                    .end = 11,
                }
            ),
            .expected_range = opentime.ContinuousInterval.init(
                .{
                    .start = 0,
                    .end = 10,
                }
            ),
        },
        .{
            .name = "left trim",
            .target_range = opentime.ContinuousInterval.init(
                .{
                    .start = 3,
                    .end = 11,
                }
            ),
            .expected_range = opentime.ContinuousInterval.init(
                .{
                    .start = 3,
                    .end = 10,
                }
            ),
        },
        .{
            .name = "right trim",
            .target_range = opentime.ContinuousInterval.init(
                .{
                    .start = -1,
                    .end = 8,
                }
            ),
            .expected_range = opentime.ContinuousInterval.init(
                .{
                    .start = 0,
                    .end = 8,
                }
            ),
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

        errdefer opentime.dbg_print(@src(), 
            "test: {s}\n result: {f}",
            .{
                t.name,
                result.extents_output(),
            },
        );
        
        try std.testing.expectEqual(
            t.expected_range.start,
            result.extents_output().?.start,
        );
        try std.testing.expectEqual(
            t.expected_range.end,
            result.extents_output().?.end,
        );
    }
}

test "Linear.Monotonic.SplitAtCriticalPoints"
{
    const allocator = std.testing.allocator;

    const crv = bezier_curve.Bezier {
        .segments = &.{
            .{
                .p0 = .init(.{ .in = 1, .out = 0 }),
                .p1 = .init(.{ .in = 1, .out = 5 }),
                .p2 = .init(.{ .in = 5, .out = 5 }),
                .p3 = .init(.{ .in = 5, .out = 1 }),
            }
        },
    };
    
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
        try std.testing.expectEqual(last, range.?.start);
        last = range.?.end;
    }
}

test "Linear.Monotonic.split_at_each_input_ord"
{
    const allocator = std.testing.allocator;

    const crv = Linear.Monotonic{
        .knots = &.{
            .init(.{ .in = 0, .out = 0, }),
            .init(.{ .in = 2, .out = 4, }),
        },
    };

    const input_ords = &[_]opentime.Ordinate{
        .init(-1),
        .init(0),
        .init(1.0),
        .init(1.5),
        .init(2.0),
        .init(2.1),
        .init(4.5),
    };

    const new_curves = try crv.split_at_each_input_ord(
        allocator,
        input_ords,
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
        3,
        new_curves.len,
    );
}

test "Linear.Monotonic: nearest_knot_indices_output"
{
    const crv = Linear.Monotonic{
        .knots = &.{
            .init(.{ .in = 0, .out = 0, }),
            .init(.{ .in = 4, .out = 4, }),
            .init(.{ .in = 6, .out = 8, }),
        },
    };

    const TestCase = struct {
        name: []const u8,
        pt: opentime.Ordinate.InnerType,
        expected: ?Linear.Monotonic.NearestIndices,
    };

    const tests = &[_]TestCase{
        .{
            .name = "between first two points",
            .pt = 3,
            .expected = .{
                .lt_output = 0,
                .gt_output = 1 
            },
        },
        .{
            .name = "between second two points",
            .pt = 4.5,
            .expected = .{
                .lt_output = 1,
                .gt_output = 2 
            },
        },
        .{
            .name = "no overlap before",
            .pt = -8.5,
            .expected = null,
        },
        .{
            .name = "no overlap after",
            .pt = 8.5,
            .expected = null,
        },
    };

    for (tests)
        |t|
    {
        const measured = crv.nearest_knot_indices_output(
            opentime.Ordinate.init(t.pt),
        );

        try std.testing.expectEqual(
            t.expected,
            measured,
        );
    }
}

test "Linear.Monotonic: slope_kind"
{
    {
        const crv_rising = Linear.Monotonic{
            .knots = &.{
                .init(.{ .in = 0, .out = 0, }),
                .init(.{ .in = 2, .out = 4, }),
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
                .init(.{ .in = 0, .out = 2, }),
                .init(.{ .in = 2, .out = 2, }),
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
                .init(.{ .in = 0, .out = 4, }),
                .init(.{ .in = 2, .out = 0, }),
            },
        };

        try std.testing.expectEqual(
            .falling,
            crv_falling.slope_kind(),
        );
    }
}

/// Create a new `linear_curve.Linear.Monotonic` which is the inversion of
/// `crv`.
///
/// Returned curve memory is owned by the caller.
pub fn inverted_linear(
    allocator: std.mem.Allocator,
    /// Curve to invert.
    crv: Linear.Monotonic,
) !Linear.Monotonic 
{
    // require two points to define a line
    if (crv.knots.len < 2) {
        // @TODO: clone the result so that memory is owned by the caller.
        return crv;
    }

    var result: std.ArrayList(control_point.ControlPoint) = .empty;
    try result.appendSlice(allocator, crv.knots);

    for (crv.knots, result.items) 
        |src_knot, *dst_knot| 
    {
        dst_knot.* = .{
            .in = src_knot.out,
            .out = src_knot.in, 
        };
    }

    const slope_kind = SlopeKind.compute(
        crv.knots[0],
        crv.knots[1]
    );
    if (slope_kind == .falling) {
        std.mem.reverse(
            control_point.ControlPoint,
            result.items
        );
    }

    return .{
        .knots = try result.toOwnedSlice(
            allocator,
        ) 
    };
}

/// Encodes and computes the slope of a segment between two ControlPoints
pub const SlopeKind = enum {
    flat,
    rising,
    falling,

    /// compute the slope kind between the two control points
    pub fn compute(
        start: control_point.ControlPoint,
        end: control_point.ControlPoint,
    ) SlopeKind
    {
        if (
            opentime.eql(start.in, end.in) 
            or opentime.eql(start.out, end.out)
        )
        {
            return .flat;
        }

        const s = slope_between(start, end);

        if (opentime.gt(s, opentime.Ordinate.zero))
        {
            return .rising;
        }
        else 
        {
            return .falling;
        }
    }
};

test "bezier_math: SlopeKind"
{
    const TestCase = struct {
        name: []const u8,
        points: [2]control_point.ControlPoint,
        expected: SlopeKind,
    };
    const tests: []const TestCase = &.{
        .{
            .name = "flat",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 5 }),
                control_point.ControlPoint.init(.{ .in = 10, .out = 5 }),
            },
            .expected = .flat,
        },
        .{
            .name = "rising",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 0 }),
                control_point.ControlPoint.init(.{ .in = 10, .out = 15 }),
            },
            .expected = .rising,
        },
        .{
            .name = "falling",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 10 }),
                control_point.ControlPoint.init(.{ .in = 10, .out = 0 }),
            },
            .expected = .falling,
        },
        .{
            .name = "column",  
            .points = .{
                control_point.ControlPoint.init(.{ .in = 0, .out = 10 }),
                control_point.ControlPoint.init(.{ .in = 0, .out = 0 }),
            },
            .expected = .flat,
        },
    };

    for (tests)
        |t|
    {
        const measured = SlopeKind.compute(
            t.points[0],
            t.points[1]
        );
        try std.testing.expectEqual(
            t.expected,
            measured,
        );
    }
}

/// Compute the slope of the line segment from start to end.
pub fn slope_between(
    start: control_point.ControlPoint,
    end: control_point.ControlPoint,
) opentime.Ordinate 
{
    return opentime.eval(
        "((end_out - start_out) / (end_in - start_in))",
        .{
            .end_in = end.in,
            .end_out = end.out,
            .start_in = start.in,
            .start_out = start.out,
        },
    );
}

test "bezier_math: slope"
{
    const start = control_point.ControlPoint.init(
        .{ .in = 0, .out = 0, }
    );
    const end = control_point.ControlPoint.init(
        .{ .in = 2, .out = 4, }
    );

    try opentime.expectOrdinateEqual(
        2,
        slope_between(start, end)
    );
}

test "split: bug"
{
    const allocator = std.testing.allocator;

    const test_crv = Linear.Monotonic {
        .knots = &.{
            .init(.{ .in = 0,  .out = 0  }),
            .init(.{ .in = 10, .out = 10 }),
            .init(.{ .in = 20, .out = 30 }),
        },
    };

    const split_curves = try test_crv.split_at_each_input_ord(
        allocator,
        &.{
            .init(1),
            .init(11),
        },
    );
    defer {
        for (split_curves) |crv| crv.deinit(allocator);
        allocator.free(split_curves);
    }

    try opentime.expectOrdinateEqual(
        1,
        split_curves[0].knots[split_curves[0].knots.len - 1].in,
    );
    try opentime.expectOrdinateEqual(
        1,
        split_curves[1].knots[0].in,
    );

    try std.testing.expectEqual(
        3,
        split_curves.len,
    );
}
