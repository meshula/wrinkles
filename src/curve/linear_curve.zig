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

// fn _is_between(
//     val: anytype,
//     fst: @TypeOf(val),
//     snd: @TypeOf(val),
// ) bool 
// {
//     return (fst <= val and val < snd) or (fst >= val and val > snd);
// }

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
                if (output_ord == last_knot.out) {
                    return last_knot.out;
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

                std.debug.print(
                    "[split_at_input_ordinates_curve] pts: {any}\n",
                    .{input_points}
                );

                if (
                    // empty
                    input_points.len == 0
                    // out of range
                    or input_points[0] > ib.end_seconds 
                    or input_points[input_points.len - 1] < ib.start_seconds
                )
                {
                    std.debug.print(
                        "[split_at_input_ordinates_curve] empty/out of range\n",
                        .{}
                    );
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
                std.debug.print(
                    "appending: {s}\n",
                    .{
                        left_knot
                    }
                );
                try current_curve.append(left_knot);

                var right_knot_ind:usize = 1;
                var right_knot = self.knots[right_knot_ind];

                for (input_points)
                    |in_pt|
                {
                    std.debug.print(
                        "processing: {d}\n",
                        .{
                            in_pt
                        }
                    );
                    // point is before range, skip
                    if (
                        in_pt < ib.start_seconds 
                        or in_pt <= left_knot.in + generic_curve.EPSILON
                    ) 
                    {
                        std.debug.print(
                            "[split_at_input_ordinates_curve] skipping: {d}\n",
                            .{in_pt}
                        );
                        continue;
                    }

                    // points are sorted, so once a point is out of range,
                    // split is done
                    if (in_pt > ib.end_seconds) {
                        std.debug.print(
                            "break: over range {d} / ib: {s}\n",
                            .{in_pt, ib}
                        );
                        break;
                    }

                    std.debug.print(
                        "check: left {d}/{d} right {d}/{d} in_pt {d}\n",
                        .{
                            left_knot, left_knot_ind,
                            right_knot,right_knot_ind,
                            in_pt
                        }
                    );

                    // move current pt until it is the point on the curve AFTER
                    // the input pt
                    while (
                        right_knot.in < in_pt 
                        and right_knot_ind < self.knots.len
                    ) : ({ right_knot_ind += 1; left_knot_ind += 1; })
                    {
                        std.debug.print(
                            "advance: left {d}/{d} right {d}/{d} in_pt {d}\n",
                            .{
                                left_knot, left_knot_ind,
                                right_knot,right_knot_ind,
                                in_pt
                            }
                        );
                        left_knot = self.knots[left_knot_ind];
                        right_knot = self.knots[right_knot_ind];
                        std.debug.print(
                            "appending {s}\n",
                            .{left_knot}
                        );
                        try current_curve.append(left_knot);
                    }

                    if (right_knot_ind >= self.knots.len) {
                        std.debug.print(
                            "break: over index ({d}/{d})\n",
                            .{in_pt, right_knot_ind}
                        );
                        break;
                    }

                    const new_knot = ControlPointType{
                        .in = in_pt,
                        .out = try self.output_at_input(in_pt),
                    };

                    std.debug.print(
                        "appending {s}\n",
                        .{new_knot}
                    );

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

        /// /// trim this curve via the bounds expressed in the input space of this
        /// /// curve.
        /// ///
        /// /// If the curve isn't trimmed, dupe the curve.
        /// pub fn trimmed_in_input_space(
        ///     self: @This(),
        ///     allocator: std.mem.Allocator,
        ///     input_bounds: opentime.ContinuousTimeInterval,
        /// ) !LinearType
        /// {
        ///     var result = std.ArrayList(ControlPointType).init(
        ///         allocator
        ///     );
        ///     result.deinit();
        ///
        ///     const first_point = ControlPointType{
        ///         .in = input_bounds.start_seconds,
        ///         .out = try self.output_at_input(input_bounds.start_seconds),
        ///     };
        ///     try result.append(first_point);
        ///
        ///
        ///     const last_point = if (
        ///         input_bounds.end_seconds < self.extents()[1].in
        ///     ) ControlPointType{ 
        ///         .in = input_bounds.end_seconds,
        ///         .out = try self.output_at_input(input_bounds.end_seconds),
        ///     } else self.extents()[1];
        ///
        ///     for (self.knots) 
        ///         |knot|
        ///     {
        ///         if (
        ///             knot.in > first_point.in
        ///             and knot.in < last_point.in
        ///         ) {
        ///             try result.append(knot);
        ///         }
        ///     }
        ///
        ///     try result.append(last_point);
        ///
        ///     return LinearType{ .knots = try result.toOwnedSlice() };
        /// }

        /// /// project an affine transformation through the curve, returning a new
        /// /// linear curve.  If self maps B->C, and xform maps A->B, then the
        /// /// result of self.project_affine(xform) will map A->C
        /// pub fn project_affine(
        ///     b2c: @This(),
        ///     allocator: std.mem.Allocator,
        ///     a2b_xform: opentime.transform.AffineTransform1D,
        ///     /// bounds on the input space of the curve (output space of the
        ///     /// affine) ("B" in the comment above)
        ///     a2b_xform_b_bounds: opentime.ContinuousTimeInterval,
        /// ) !LinearType 
        /// {
        ///     // output bounds of the affine are in the input space of the curve
        ///     const clipped_curve = try b2c.trimmed_in_input_space(
        ///         allocator,
        ///         a2b_xform_b_bounds
        ///     );
        ///     defer clipped_curve.deinit(allocator);
        ///
        ///     const result_knots = try allocator.dupe(
        ///         ControlPointType,
        ///         clipped_curve.knots,
        ///     );
        ///
        ///     const input_to_other_xform = a2b_xform.inverted();
        ///
        ///     for (clipped_curve.knots, result_knots) 
        ///         |pt, *target_knot| 
        ///     {
        ///         target_knot.in = input_to_other_xform.applied_to_seconds(pt.in);
        ///     }
        ///
        ///     return .{
        ///         .knots = result_knots,
        ///     };
        /// }

        /// /// compute the output ordinate at the input ordinate
        /// pub fn output_at_input(
        ///     self: @This(),
        ///     input_ord: f32,
        /// ) error{OutOfBounds}!f32 
        /// {
        ///     if (self.nearest_smaller_knot_index(input_ord)) 
        ///         |index| 
        ///     {
        ///         return bezier_math.output_at_input_between(
        ///             input_ord,
        ///             self.knots[index],
        ///             self.knots[index+1],
        ///         );
        ///     }
        ///
        ///     // specially handle the endpoint
        ///     const last_knot = self.knots[self.knots.len - 1];
        ///     if (input_ord == last_knot.in) {
        ///         return last_knot.out;
        ///     }
        ///
        ///     return error.OutOfBounds;
        /// }

        // pub fn output_at_input_at_value(
        //     self: @This(),
        //     value_ord: f32,
        // ) !f32
        // {
        //     if (self.nearest_smaller_knot_index_to_value(value_ord)) 
        //         |index| 
        //     {
        //         return bezier_math.input_at_output_between(
        //             value_ord,
        //             self.knots[index],
        //             self.knots[index+1],
        //         );
        //     }
        //
        //     return error.OutOfBounds;
        // }

        // pub fn nearest_smaller_knot_index(
        //     self: @This(),
        //     t_arg: f32, 
        // ) ?usize 
        // {
        //     const last_index = self.knots.len-1;
        //
        //     // out of bounds
        //     if (
        //         self.knots.len == 0 
        //         or (t_arg < self.knots[0].in)
        //         or t_arg >= self.knots[last_index].in
        //     )
        //     {
        //         return null;
        //     }
        //
        //     // last knot is out of domain
        //     for (self.knots[0..last_index], self.knots[1..], 0..) 
        //         |knot, next_knot, index| 
        //     {
        //         if ( knot.in <= t_arg and t_arg < next_knot.in) 
        //         {
        //             return index;
        //         }
        //     }
        //
        //     return null;
        // }

        // pub fn nearest_smaller_knot_index_to_value(
        //     self: @This(),
        //     value_ord: f32, 
        // ) ?usize 
        // {
        //     const last_index = self.knots.len-1;
        //
        //     // out of bounds
        //     if (
        //         self.knots.len == 0 
        //         or (value_ord < self.knots[0].out)
        //         or value_ord >= self.knots[last_index].out
        //     )
        //     {
        //         return null;
        //     }
        //
        //     // last knot is out of domain
        //     for (self.knots[0..last_index], self.knots[1..], 0..) 
        //         |knot, next_knot, index| 
        //     {
        //         if ( knot.out <= value_ord and value_ord < next_knot.out) 
        //         {
        //             return index;
        //         }
        //     }
        //
        //     return null;
        // }

        /// /// project another curve through this one.  A curve maps 'input' to
        /// /// 'output' parameters.  if curve self is v_self(t_self), and curve other
        /// /// is v_other(t_other) and other is being projected through self, the
        /// /// result function is v_self(v_other(t_other)).  This maps the the v_other
        /// /// value to the t_self parameter.
        /// ///
        /// /// To put it another way, if self maps B->C
        /// /// (B = t_self, C=v_self)
        /// /// and other maps A->B
        /// /// (A = t_other)
        /// /// then self.project_curve(other): A->C
        /// /// t_other -> v_self
        /// /// or if self.input -> self.output
        /// /// and other.input -> other.output
        /// /// self.project_topology(other) :: other.input -> self.output
        /// ///
        /// /// curve self:
        /// /// 
        /// /// v_self
        /// /// |  /
        /// /// | /
        /// /// |/
        /// /// +--- t_self
        /// ///
        /// /// curve other:
        /// ///   
        /// ///  v_other
        /// /// |      ,-'
        /// /// |   ,-'
        /// /// |,-'
        /// /// +---------- t_other
        /// ///
        /// /// @TODO finish this doc
        /// ///
        /// /// to restate: self B->C
        /// ///               input:  B
        /// ///               output: C
        /// ///            other A->B
        /// ///               input:  A
        /// ///               output: B
        /// ///           result A->C
        /// ///               input:  A
        /// ///               output: C
        /// ///            => other.output space is self.input space
        /// ///
        /// pub fn project_curve(
        ///     /// curve being projected _through_
        ///     b2c: @This(),
        ///     allocator: std.mem.Allocator,
        ///     /// curve being projected
        ///     a2b: LinearType,
        /// ) ![]LinearType 
        /// {
        ///     const a2b_extents = a2b.extents();
        ///
        ///     // find all knots in b2c that are within the a2b bounds
        ///     var points_to_split_a2b_in_b = (
        ///         std.ArrayList(opentime.Ordinate).init(allocator)
        ///     );
        ///     defer points_to_split_a2b_in_b.deinit();
        ///
        ///     for (b2c.knots)
        ///         |b2c_knot| 
        ///     {
        ///         if (
        ///             _is_between(
        ///                 b2c_knot.in,
        ///                 a2b_extents[0].out,
        ///                 a2b_extents[1].out,
        ///             )
        ///         ) {
        ///             try points_to_split_a2b_in_b.append(b2c_knot.in);
        ///         }
        ///     }
        ///
        ///     const a2b_split_at_b2c_knots = (
        ///         try a2b.split_at_each_ord_output(
        ///             allocator,
        ///             points_to_split_a2b_in_b.items,
        ///         )
        ///     );
        ///
        ///     // split a2b into curves where it goes in and out of the b-range of
        ///     // b2c -- @TODO: again, this is simpler, if curves are already
        ///     // split on critical points. Then each curve is monotonic both in
        ///     // input and output
        ///     var curves_to_project = std.ArrayList(
        ///         LinearType,
        ///     ).init(allocator);
        ///     defer curves_to_project.deinit();
        ///
        ///     // gather the curves to project by splitting
        ///     {
        ///         const b2c_b_bounds = b2c.extents_input();
        ///         var last_index:?i32 = null;
        ///         var current_curve = (
        ///             std.ArrayList(ControlPointType).init(
        ///                 allocator,
        ///             )
        ///         );
        ///
        ///         for (a2b_split_at_b2c_knots.knots, 0..) 
        ///             |a2b_knot, index| 
        ///         {
        ///             if (
        ///                 b2c_b_bounds.start_seconds <= a2b_knot.out 
        ///                 and a2b_knot.out <= b2c_b_bounds.end_seconds
        ///             ) 
        ///             {
        ///                 if (last_index == null or index != last_index.?+1) 
        ///                 {
        ///                     // curves of less than one point are trimmed,
        ///                     // because they have no duration, and therefore are
        ///                     // not modelled in our system.
        ///                     if (current_curve.items.len > 1) 
        ///                     {
        ///                         try curves_to_project.append(
        ///                             LinearType{
        ///                                 .knots = (
        ///                                     try current_curve.toOwnedSlice()
        ///                                 ),
        ///                             }
        ///                         );
        ///                     }
        ///                     current_curve.clearAndFree();
        ///                 }
        ///
        ///                 try current_curve.append(a2b_knot);
        ///                 last_index = @intCast(index);
        ///             }
        ///         }
        ///         if (current_curve.items.len > 1) {
        ///             try curves_to_project.append(
        ///                 LinearType{
        ///                     .knots = try current_curve.toOwnedSlice(),
        ///                 }
        ///             );
        ///         }
        ///         current_curve.clearAndFree();
        ///     }
        ///     a2b_split_at_b2c_knots.deinit(allocator);
        ///
        ///     if (curves_to_project.items.len == 0) {
        ///         return &[_]LinearType{};
        ///     }
        ///
        ///     for (curves_to_project.items) 
        ///         |crv| 
        ///     {
        ///         // project each knot
        ///         for (crv.knots) 
        ///             |*knot| 
        ///         {
        ///             // 2. output_at_input grows a parameter to treat endpoint as in bounds
        ///             // 3. check outside of output_at_input if it sits on a knot and use
        ///             //    the value rather than computing
        ///             // 4. catch the error and call a different function or do a
        ///             //    check in that case
        ///             const value = b2c.output_at_input(knot.out) catch (
        ///                 if (b2c.knots[b2c.knots.len-1].in == knot.out) 
        ///                 b2c.knots[b2c.knots.len-1].out 
        ///                 else return error.NotInRangeError
        ///             );
        ///
        ///             knot.out  = value;
        ///         }
        ///     }
        ///
        ///     // @TODO: we should write a test that exersizes this case
        ///     if (curves_to_project.items.len > 1) {
        ///         return error.MoreThanOneCurveIsNotImplemented;
        ///     }
        ///
        ///
        ///     return try curves_to_project.toOwnedSlice();
        /// }

        /// /// convienence wrapper around project_curve that assumes a single result
        /// /// and returns handles the cleanup of that.
        /// pub fn project_curve_single_result(
        ///     self: @This(),
        ///     allocator: std.mem.Allocator,
        ///     other: LinearType
        /// ) !LinearType 
        /// {
        ///     const result = try self.project_curve(
        ///         allocator,
        ///         other
        ///     );
        ///
        ///     if (result.len > 1) {
        ///         @panic("Not Implemented");
        ///     }
        ///
        ///     defer { 
        ///         for (result)
        ///             |crv|
        ///         {
        ///             crv.deinit(allocator);
        ///         }
        ///         allocator.free(result);
        ///     }
        ///
        ///     if (result.len < 1)
        ///     {
        ///         std.debug.print(
        ///             "Couldn't project:\n  self: {any}\n  other: {any}\n",
        ///             .{ self.extents(), other.extents(), },
        ///         );
        ///         return error.NoProjectionResultError;
        ///     }
        ///
        ///     return try result[0].clone(allocator);
        /// }

        pub fn debug_json_str(
            self:@This(), 
            allocator: std.mem.Allocator,
        ) ![]const u8
        {
            var str = std.ArrayList(u8).init(allocator);

            try std.json.stringify(self, .{}, str.writer()); 

            return str.toOwnedSlice();
        }

        /// /// return the extents of the input domain of the curve  - O(1) because
        /// /// curves are monotonic over their input spaces by definition.
        /// pub fn extents_input(
        ///     self:@This()
        /// ) opentime.ContinuousTimeInterval 
        /// {
        ///     return .{
        ///         .start_seconds = self.knots[0].in,
        ///         .end_seconds = self.knots[self.knots.len - 1].in,
        ///     };
        /// }

        /// /// compute both the input and output extents for the curve
        /// /// exhaustively.  [0] is the minimum and [1] is the maximum
        /// pub fn extents(
        ///     self:@This(),
        /// ) [2]ControlPointType 
        /// {
        ///     var min:ControlPointType = self.knots[0];
        ///     var max:ControlPointType = self.knots[0];
        ///
        ///     for (self.knots) 
        ///         |knot| 
        ///     {
        ///         min = .{
        ///             .in = @min(min.in, knot.in),
        ///             .out = @min(min.out, knot.out),
        ///         };
        ///         max = .{
        ///             .in = @max(max.in, knot.in),
        ///             .out = @max(max.out, knot.out),
        ///         };
        ///     }
        ///     return .{ min, max };
        /// }

        /// /// insert a knot each location on the curve that crosses the values in
        /// /// split_points
        /// pub fn split_at_each_ord_output(
        ///     self: @This(),
        ///     allocator: std.mem.Allocator,
        ///     split_points: []f32,
        /// ) !LinearType 
        /// {
        ///     var result = (
        ///         std.ArrayList(ControlPointType).init(
        ///             allocator,
        ///         )
        ///     );
        ///     // make room for all points being splits
        ///     try result.ensureTotalCapacity(split_points.len + self.knots.len);
        ///
        ///     const last_minus_one = self.knots.len-1;
        ///
        ///     // @TODO: there is probably a more effecient algorithm here than MxN
        ///     //        if we can guarantee monotonicity, knots are sorted and
        ///     //        this can be considerably more efficient
        ///     for (self.knots[0..last_minus_one], self.knots[1..])
        ///         |knot, next_knot, |
        ///     {
        ///         result.appendAssumeCapacity(knot);
        ///
        ///         for (split_points) 
        ///             |pt_output_space| 
        ///         {
        ///             if (
        ///                 knot.out < pt_output_space 
        ///                 and pt_output_space < next_knot.out
        ///             )
        ///             {
        ///                 const u = bezier_math.invlerp(
        ///                     pt_output_space,
        ///                     knot.out,
        ///                     next_knot.out
        ///                 );
        ///                 result.appendAssumeCapacity(
        ///                     bezier_math.lerp(
        ///                         u,
        ///                         knot,
        ///                         next_knot
        ///                     )
        ///                 );
        ///             }
        ///         }
        ///     }
        ///     result.appendAssumeCapacity(self.knots[last_minus_one]);
        ///
        ///     return LinearType{
        ///         .knots = try result.toOwnedSlice() 
        ///     };
        /// }

        /// split this curve into monotonic curves over output.  Splits
        /// whenever the slope changes between rising, falling or flat.
        pub fn split_at_critical_points(
            self: @This(),
            allocator: std.mem.Allocator,
        ) ![]const Monotonic
        {
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

// test "LinearType: extents" 
// {
//     const crv = try Linear.init_identity(
//         std.testing.allocator,
//         &.{100, 200},
//     );
//     defer crv.deinit(std.testing.allocator);
//
//     const bounds = crv.extents();
//
//     try expectEqual(@as(f32, 100), bounds[0].in);
//     try expectEqual(@as(f32, 200), bounds[1].in);
//
//     const bounds_input = crv.extents_input();
//     try expectEqual(@as(f32, 100), bounds_input.start_seconds);
//     try expectEqual(@as(f32, 200), bounds_input.end_seconds);
// }

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

// test "Linear: project s" 
// {
//     const ident = try Linear.init_identity(
//         std.testing.allocator,
//         &.{0, 100},
//     );
//     defer ident.deinit(std.testing.allocator);
//
//     const simple_s: [4]ControlPoint = .{
//         .{ .in = 0, .out = 0},
//         .{ .in = 30, .out = 10},
//         .{ .in = 60, .out = 90},
//         .{ .in = 100, .out = 100},
//     };
//
//     const simple_s_lin = try Linear.init(
//         std.testing.allocator,
//         &simple_s,
//     );
//     defer simple_s_lin.deinit(std.testing.allocator);
//
//     const result = try simple_s_lin.project_curve(
//         std.testing.allocator,
//         ident,
//     );
//     defer {
//         for (result)
//             |crv|
//         {
//             crv.deinit(std.testing.allocator);
//         }
//         std.testing.allocator.free(result);
//     }
//
//     try expectEqual(@as(usize, 1), result.len);
//     try expectEqual(@as(usize, 4), result[0].knots.len);
// }

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

// test "Linear: Affine through linear"
// {
//     // given a curve that maps space a -> space b
//     // and a transform that maps b->c
//
//     const b2c_crv= try Linear.init(
//         std.testing.allocator,
//         &.{
//             .{ .in = 0, .out = 0, },
//             .{ .in = 4, .out = 8, },
//         }
//     );
//     defer b2c_crv.deinit(std.testing.allocator);
//     const b2c_extents = b2c_crv.extents();
//
//     errdefer std.debug.print(
//         "b2c_crv_b_extents: [{d}, {d})\nb2c_crv_c_extents: [{d}, {d})\n",
//         .{
//             b2c_extents[0].in, b2c_extents[1].in,
//             b2c_extents[0].out, b2c_extents[1].out,
//         }
//     );
//
//     const b_bound = opentime.ContinuousTimeInterval{
//         .start_seconds = 1,
//         .end_seconds = 2,
//     };
//     errdefer std.debug.print(
//         "b_bound: [{d}, {d})\n",
//         .{
//             b_bound.start_seconds, b_bound.end_seconds,
//         }
//     );
//
//     errdefer std.debug.print("INPUTS:\n", .{});
//
//     const a2b_transformation_tests = (
//         [_]opentime.transform.AffineTransform1D{
//             opentime.transform.AffineTransform1D{
//                 .offset_seconds = 0,
//                 .scale = 1,
//             },
//             opentime.transform.AffineTransform1D{
//                 .offset_seconds = 10,
//                 .scale = 1,
//             },
//             opentime.transform.AffineTransform1D{
//                 .offset_seconds = 0,
//                 .scale = 2,
//             },
//         }
//     );
//
//     for (a2b_transformation_tests, 0..)
//         |a2b_aff, test_ind|
//     {
//         errdefer std.debug.print(
//             "[erroring test iteration {d}]:\n a2b offset: {d}\n a2b scale: {d} \n",
//             .{ test_ind, a2b_aff.offset_seconds, a2b_aff.scale },
//         );
//         const a2c_result = try b2c_crv.project_affine(
//             std.testing.allocator,
//             a2b_aff,
//             b_bound,
//         );
//         defer a2c_result.deinit(std.testing.allocator);
//
//         const a2c_result_extents = a2c_result.extents();
//
//         errdefer std.debug.print(
//             "a2c_result_extents: [({d}, {d}), ({d}, {d}))\n",
//             .{
//                 a2c_result_extents[0].in, a2c_result_extents[0].out,
//                 a2c_result_extents[1].in, a2c_result_extents[1].out,
//             }
//         );
//
//         const b2a_aff = a2b_aff.inverted();
//         const a_bound = b2a_aff.applied_to_cti(b_bound);
//
//         errdefer std.debug.print(
//             "computed_a_bounds: [{d}, {d})\n",
//             .{
//                 a_bound.start_seconds, 
//                 a_bound.end_seconds,
//             }
//         );
//
//         try expectApproxEqAbs(
//             a2c_result_extents[0].in,
//             a_bound.start_seconds,
//             generic_curve.EPSILON,
//         );
//     }
// }

// pub fn join_lin_aff(
//     allocator: std.mem.Allocator,
//     args: struct{
//         a2b: Linear,
//         b2c: opentime.AffineTransform1D,
//     },
// ) !Linear
// {
//     const new_knots = try allocator.dupe(
//         ControlPoint,
//         args.a2b.knots,
//     );
//
//     for (new_knots)
//         |*knot|
//     {
//         knot.out = args.b2c.applied_to_seconds(knot.out);
//     }
//
//     return .{
//         .knots = new_knots,
//     };
// }

// test "Linear: linear through affine"
// {
//     // given a curve that maps space a -> space b
//     // and a transform that maps b->c
//
//     const a2b_crv= try Linear.init(
//         std.testing.allocator,
//         &.{
//             .{ .in = 0, .out = 0, },
//             .{ .in = 4, .out = 8, },
//         }
//     );
//     defer a2b_crv.deinit(std.testing.allocator);
//     const a2b_extents = a2b_crv.extents();
//
//     errdefer std.debug.print(
//         "b2c_crv_b_extents: [{d}, {d})\nb2c_crv_c_extents: [{d}, {d})\n",
//         .{
//             a2b_extents[0].in,  a2b_extents[1].in,
//             a2b_extents[0].out, a2b_extents[1].out,
//         }
//     );
//
//     const TestThing = struct{
//         xform: opentime.AffineTransform1D,
//         test_pt: [2]f32,
//     };
//
//     const b2c_transformation_tests = (
//         [_]TestThing{
//             .{
//                 .xform = opentime.AffineTransform1D{
//                     .offset_seconds = 0,
//                     .scale = 1,
//                 },
//                 .test_pt = .{ 2, 4 },
//             },
//             .{
//                 .xform = opentime.AffineTransform1D{
//                     .offset_seconds = 10,
//                     .scale = 1,
//                 },
//                 .test_pt = .{ 2, 14 },
//             },
//             .{
//                 .xform = opentime.AffineTransform1D{
//                     .offset_seconds = 0,
//                     .scale = 2,
//                 },
//                 .test_pt = .{ 2, 8 },
//             }
//         }
//     );
//
//     for (b2c_transformation_tests, 0..)
//         |t, test_ind|
//     {
//         const b2c_aff = t.xform;
//
//         errdefer std.debug.print(
//             "[erroring test iteration {d}]:\n b2c offset: {d}\n "
//             ++ "b2c scale: {d} \n",
//             .{ test_ind, b2c_aff.offset_seconds, b2c_aff.scale },
//         );
//
//         const a2c = try join_lin_aff(
//             std.testing.allocator,
//             .{
//                 .a2b = a2b_crv,
//                 .b2c = b2c_aff,
//             },
//         );
//         defer a2c.deinit(std.testing.allocator);
//
//         const result = try a2c.output_at_input(t.test_pt[0]);
//
//         errdefer std.debug.print(
//             "[test: {d}] input: {d} expected: {d} got: {d}\n",
//             .{ test_ind, t.test_pt[0], t.test_pt[1], result }
//         );
//
//         try std.testing.expectEqual( t.test_pt[1], result);
//     }
// }

// test "Linear: trimmed_in_input_space"
// {
//     const crv = try Linear.init(
//         std.testing.allocator,
//         &.{
//             .{ .in = 0, .out = 0, },
//             .{ .in = 4, .out = 8, },
//         }
//     );
//     defer crv.deinit(std.testing.allocator);
//
//     const bounds = opentime.ContinuousTimeInterval{
//         .start_seconds = 1,
//         .end_seconds = 2,
//     };
//     const crv_ext = crv.extents();
//     errdefer std.debug.print(
//         "bounds: [({d}, {d}), ({d}, {d}))\n",
//         .{
//             crv_ext[0].in, crv_ext[0].out,
//             crv_ext[1].in, crv_ext[1].out,
//         }
//     );
//
//     const trimmed_crv = try crv.trimmed_in_input_space(
//         std.testing.allocator,
//         bounds
//     );
//     defer trimmed_crv.deinit(std.testing.allocator);
//     const trimmed_extents = trimmed_crv.extents();
//     errdefer std.debug.print(
//         "found: [({d}, {d}), ({d}, {d}))\n",
//         .{
//             trimmed_extents[0].in, trimmed_extents[0].out,
//             trimmed_extents[1].in, trimmed_extents[1].out,
//         }
//     );
//
//     try expectApproxEqAbs(
//         bounds.start_seconds,
//         trimmed_extents[0].in, 
//         generic_curve.EPSILON,
//     );
//
//     try expectApproxEqAbs(
//         bounds.end_seconds,
//         trimmed_extents[1].in, 
//         generic_curve.EPSILON,
//     );
// }

// test "Linear perf test"
// {
//     if (RUN_PERF_TESTS == false) {
//         return error.SkipZigTest;
//     }
//
//     // const SIZE = 20000000;
//     const SIZE = 200000000;
//
//     var t_setup = try std.time.Timer.start();
//
//     var rnd_split_points = (
//         std.ArrayList(opentime.Ordinate).init(std.testing.allocator)
//     );
//     try rnd_split_points.ensureTotalCapacity(SIZE);
//     defer rnd_split_points.deinit();
//
//     try rnd_split_points.append(0);
//
//     var rand_impl = std.rand.DefaultPrng.init(42);
//
//     for (0..SIZE)
//         |_|
//     {
//         const num = (
//              rand_impl.random().float(opentime.Ordinate)
//         );
//         rnd_split_points.appendAssumeCapacity(num);
//     }
//     const crv = try Linear.init_identity(
//         std.testing.allocator,
//         &.{ 0.0, 1.0 }
//     );
//     defer crv.deinit(std.testing.allocator);
//     const t_start_v = t_setup.read();
//
//     var t_algo = try std.time.Timer.start();
//     const crv_split = try crv.split_at_each_ord_output(
//         std.testing.allocator,
//         rnd_split_points.items
//     );
//     const t_algo_v = t_algo.read();
//     defer crv_split.deinit(std.testing.allocator);
//
//     std.debug.print(
//         "Startup time: {d:.4}ms\n"
//         ++ "Time to process is: {d:.4}ms\n"
//         ++ "number of splits: {d}\n"
//         ,
//         .{
//             t_start_v/std.time.ns_per_ms,
//             t_algo_v / std.time.ns_per_ms,
//             crv_split.knots.len,
//         },
//     );
// }

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
        b2c_b_extents
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
    var cursor_a2b:usize = 1;
    var cursor_b2c:usize = 1;

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
