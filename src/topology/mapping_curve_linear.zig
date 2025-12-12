//! Linear Time Curve Mapping

const std = @import("std");

const mapping_mod = @import("mapping.zig");
const curve = @import("curve");
const opentime = @import("opentime");

/// a linear mapping from input to output
pub const MappingCurveLinearMonotonic = struct {
    input_to_output_curve: curve.Linear.Monotonic,

    pub fn init_knots(
        knots: []const curve.ControlPoint,
    ) MappingCurveLinearMonotonic
    {
        return .{
            .input_to_output_curve = .{
                .knots = knots,
            },
        };
    }

    pub fn init_curve(
        allocator: std.mem.Allocator,
        crv: curve.Linear.Monotonic,
    ) !MappingCurveLinearMonotonic
    {
        return .{
            .input_to_output_curve = try crv.clone(allocator),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        self.input_to_output_curve.deinit(allocator);
    }

    pub fn mapping(
        self: @This(),
    ) mapping_mod.Mapping
    {
        return .{
            .linear = self,
        };
    }

    pub fn input_bounds(
        self: @This(),
    ) ?opentime.ContinuousInterval 
    {
        return self.input_to_output_curve.extents_input();
    }

    pub fn output_bounds(
        self: @This(),
    ) ?opentime.ContinuousInterval 
    {
        return self.input_to_output_curve.extents_output();
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        input_ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult 
    {
        return self.input_to_output_curve.output_at_input(input_ordinate);
    }

    pub const project_instantaneous_cc_assume_in_bounds = (
        project_instantaneous_cc
    );

    pub fn project_instantaneous_cc_inv(
        self: @This(),
        output_ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        return self.input_to_output_curve.input_at_output(output_ordinate);
    }


    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !MappingCurveLinearMonotonic
    {
        return .{
            .input_to_output_curve = (
                try self.input_to_output_curve.clone(allocator)
            ),
        };
    }

    pub fn shrink_to_output_interval(
        self: @This(),
        allocator: std.mem.Allocator,
        target_output_interval: opentime.ContinuousInterval,
    ) !?mapping_mod.Mapping
    {
        return (
            MappingCurveLinearMonotonic{
                .input_to_output_curve = (
                    try self.input_to_output_curve.trimmed_output(
                        allocator,
                        target_output_interval,
                    )
                ),
            }
        ).mapping();
    }

    pub fn shrink_to_input_interval(
        self: @This(),
        allocator: std.mem.Allocator,
        target_intput_interval: opentime.ContinuousInterval,
    ) !?mapping_mod.Mapping
    {
        return (
            MappingCurveLinearMonotonic{
                .input_to_output_curve = (
                    try self.input_to_output_curve.trimmed_input(
                        allocator,
                        target_intput_interval,
                    )
                ),
            }
        ).mapping();
    }

    pub fn split_at_each_input_ord(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) ![]const mapping_mod.Mapping
    {
        // split the curve
        const new_curves = (
            try self.input_to_output_curve.split_at_each_input_ord(
                allocator,
                input_points,
            )
        );
        // free the slice, not the knots
        defer allocator.free(new_curves);

        // wrap it back in a mapping
        const result_mappings = try allocator.alloc(
            mapping_mod.Mapping,
            new_curves.len,
        );

        for (new_curves, result_mappings)
            |src_crv, *dst_mapping|
        {
            dst_mapping.* = MappingCurveLinearMonotonic.init_knots(
                src_crv.knots,
            ).mapping();
        }

        return result_mappings;
    }

    pub fn split_at_input_ord(
        self: @This(),
        allocator: std.mem.Allocator,
        input_ord: opentime.Ordinate,
    ) ![2]mapping_mod.Mapping
    {
        var left_knots: std.ArrayList(curve.ControlPoint) = .empty;
        var right_knots: std.ArrayList(curve.ControlPoint) = .empty;

        const start_knots = self.input_to_output_curve.knots;

        for (start_knots[1..], 1..)
            |k, k_ind|
        {
            if (k.in.eql(input_ord))
            {
                try left_knots.appendSlice(
                    allocator,
                    start_knots[0..k_ind],
                );
                try right_knots.appendSlice(
                    allocator,
                    start_knots[k_ind..],
                );
                break;
            }
            if (k.in.gt(input_ord))
            {
                const new_knot = curve.ControlPoint{
                    .in = input_ord,
                    .out = try self.input_to_output_curve.output_at_input(input_ord).ordinate(),
                };

                try left_knots.appendSlice(
                    allocator,
                    start_knots[0..k_ind],
                );
                try left_knots.append(allocator,new_knot);

                try right_knots.append(allocator,new_knot);
                try right_knots.appendSlice(
                    allocator,start_knots[k_ind..],
                );
                break;
            }
        }

        return .{
            .{
                .linear = .{
                    .input_to_output_curve = .{
                        .knots = try left_knots.toOwnedSlice(allocator),
                    },
                },
            },
            .{
                .linear = .{
                    .input_to_output_curve = .{
                        .knots = try right_knots.toOwnedSlice(allocator),
                    },
                },
            },
        };
    }
};

test "MappingCurveLinearMonotonic: init_knots"
{
    const mcl = MappingCurveLinearMonotonic.init_knots(
        &.{
            .init(.{ .in = 0,  .out = 0  }),
            .init(.{ .in = 10, .out = 10 }),
        },
    ).mapping();

    try opentime.expectOrdinateEqual(
        2,
        mcl.project_instantaneous_cc(2).ordinate(),
    );
}

test "Mapping"
{
    const mcl = (
        MappingCurveLinearMonotonic.init_knots(
            &.{
                .init(.{ .in = 0,  .out = 0  }),
                .init(.{ .in = 10, .out = 10 }),
                .init(.{ .in = 20, .out = 30 }),
                .init(.{ .in = 30, .out = 30 }),
                .init(.{ .in = 40, .out = 0 }),
                .init(.{ .in = 50, .out = -10 }),
            },
        )
    ).mapping();

    const TestThing = struct {
        tp : i32,
        exp : i32,
        err : bool,
    };
    const test_points = [_]TestThing{
        TestThing{ .tp = -1, .exp = 0, .err = true, },
        TestThing{ .tp = 0, .exp = 0, .err = false, },
        TestThing{ .tp = 5, .exp = 5, .err = false, },
        TestThing{ .tp = 15, .exp = 20, .err = false, },
        TestThing{ .tp = 25, .exp = 30, .err = false, },
        TestThing{ .tp = 26, .exp = 30, .err = false, },
        TestThing{ .tp = 45, .exp = -5, .err = false, },
    };

    for (test_points)
        |t|
    {
        if (t.err == false)
        {
            const measured = mcl.project_instantaneous_cc(t.tp);
            try opentime.expectOrdinateEqual(
                t.exp,
                try measured.ordinate(),
            );
        }
        else 
        {
            try std.testing.expectError(
                error.OutOfBounds,
                mcl.project_instantaneous_cc(t.tp).ordinate(),
            );
        }
    }
}

test "Linear.Monotonic: shrink_to_output_interval"
{
    const allocator = std.testing.allocator;

    const mcl = MappingCurveLinearMonotonic.init_knots(
        &.{
            .init(.{ .in = 0,  .out = 0  }),
            .init(.{ .in = 10, .out = 10 }),
            .init(.{ .in = 20, .out = 30 }),
        }
    ).mapping();

    const result = (
        try mcl.shrink_to_output_interval(
            allocator,
            opentime.ContinuousInterval.init(
                .{ 
                    .start = 5,
                    .end = 25,
                }
            ),
        )
    ) orelse return error.InvalidBounds;

    defer result.deinit(allocator);

    const m2 = try mcl.clone(allocator);
    defer m2.deinit(allocator);

    const c = try result.clone(allocator);
    defer c.deinit(allocator);

    const result_extents = (
        result.output_bounds()
        orelse return error.InvalidBounds
    );
    try opentime.expectOrdinateEqual(
        5,
        result_extents.start,
    );
    try opentime.expectOrdinateEqual(
        25,
        result_extents.end,
    );
}

test "MappingCurveLinearMonotonic: split_at_input_points"
{
    const allocator = std.testing.allocator;

    const mcl = (
        MappingCurveLinearMonotonic.init_knots(
            &.{
                .init(.{ .in = 0,  .out = 0  }),
                .init(.{ .in = 10, .out = 10 }),
                .init(.{ .in = 20, .out = 30 }),
            },
        )
    );

    {
        const split_mappings = try mcl.split_at_input_ord(
            allocator,
            .init(1),
        );
        defer split_mappings[0].deinit(allocator);
        defer split_mappings[1].deinit(allocator);

        try opentime.expectOrdinateEqual(
            1, 
            split_mappings[0].input_bounds().?.end
        );
        try opentime.expectOrdinateEqual(
            1, 
            split_mappings[1].input_bounds().?.start
        );
    }

    {
        const io_crv = mcl.input_to_output_curve;
        const split_curves = try io_crv.split_at_each_input_ord(
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
    }

    {
        const split_mappings = try mcl.split_at_each_input_ord(
            allocator,
            &.{
                .init(1),
                .init(11),
            }
        );
        defer {
            for (split_mappings)
                |m|
            {
                m.deinit(allocator);
            }
            allocator.free(split_mappings);
        }

        try std.testing.expectEqual(
            3,
            split_mappings.len,
        );

        try opentime.expectOrdinateEqual(
            1, 
            split_mappings[0].input_bounds().?.end
        );
        try opentime.expectOrdinateEqual(
            1, 
            split_mappings[1].input_bounds().?.start
        );

        try opentime.expectOrdinateEqual(
            11, 
            split_mappings[1].input_bounds().?.end
        );
        try opentime.expectOrdinateEqual(
            11, 
            split_mappings[2].input_bounds().?.start
        );
    }
}
