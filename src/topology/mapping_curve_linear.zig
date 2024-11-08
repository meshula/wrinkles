//! Linear Time Curve Mapping

const std = @import("std");

const mapping_mod = @import("mapping.zig");
const curve = @import("curve");
const opentime = @import("opentime");

/// a linear mapping from input to output
pub const MappingCurveLinearMonotonic = struct {
    input_to_output_curve: curve.Linear.Monotonic,

    pub fn init_knots(
        allocator: std.mem.Allocator,
        knots: []const curve.ControlPoint,
    ) !MappingCurveLinearMonotonic
    {
        return .{
            .input_to_output_curve = .{
                .knots = try allocator.dupe(
                    curve.ControlPoint,
                    knots,
                ),
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
    ) opentime.ContinuousTimeInterval 
    {
        return self.input_to_output_curve.extents_input();
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval 
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
        target_output_interval: opentime.ContinuousTimeInterval,
    ) !MappingCurveLinearMonotonic
    {
        return .{
            .input_to_output_curve = (
                try self.input_to_output_curve.trimmed_output(
                    allocator,
                    target_output_interval,
                )
            ),
        };
    }

    pub fn shrink_to_input_interval(
        self: @This(),
        allocator: std.mem.Allocator,
        target_intput_interval: opentime.ContinuousTimeInterval,
    ) !MappingCurveLinearMonotonic
    {
        return .{
            .input_to_output_curve = (
                try self.input_to_output_curve.trimmed_input(
                    allocator,
                    target_intput_interval,
                )
            ),
        };
    }

    pub fn split_at_input_points(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) ![]const mapping_mod.Mapping
    {
        const new_curves = (
            try self.input_to_output_curve.split_at_input_ordinates(
                allocator,
                input_points,
            )
        );

        var result_mappings = (
            std.ArrayList(mapping_mod.Mapping).init(allocator)
        );

        for (new_curves)
            |crv|
        {
            try result_mappings.append(
                (
                 try MappingCurveLinearMonotonic.init_curve(
                     allocator,
                     crv,
                 )
                ).mapping()
            );
        }

        return result_mappings.toOwnedSlice();
    }

    pub fn split_at_input_point(
        self: @This(),
        allocator: std.mem.Allocator,
        pt_input: opentime.Ordinate,
    ) ![2]mapping_mod.Mapping
    {
        var left_knots = (
            std.ArrayList(curve.ControlPoint).init(allocator)
        );
        var right_knots = (
            std.ArrayList(curve.ControlPoint).init(allocator)
        );

        const start_knots = self.input_to_output_curve.knots;

        for (start_knots[1..], 1..)
            |k, k_ind|
        {
            if (k.in == pt_input)
            {
                try left_knots.appendSlice(start_knots[0..k_ind]);
                try right_knots.appendSlice(start_knots[k_ind..]);
                break;
            }
            if (k.in > pt_input)
            {
                const new_knot = curve.ControlPoint{
                    .in = pt_input,
                    .out = try self.input_to_output_curve.output_at_input(pt_input).ordinate(),
                };

                try left_knots.appendSlice(start_knots[0..k_ind]);
                try left_knots.append(new_knot);

                try right_knots.append(new_knot);
                try right_knots.appendSlice(start_knots[k_ind..]);
                break;
            }
        }

        return .{
            .{
                .linear = .{
                    .input_to_output_curve = .{
                        .knots = try left_knots.toOwnedSlice(),
                    },
                },
            },
            .{
                .linear = .{
                    .input_to_output_curve = .{
                        .knots = try right_knots.toOwnedSlice(),
                    },
                },
            },
        };
    }
};

test "MappingCurveLinearMonotonic: init_knots"
{
    const mcl = (
        try MappingCurveLinearMonotonic.init_knots(
            std.testing.allocator,
            &.{
                .{ .in = 0,  .out = 0  },
                .{ .in = 10, .out = 10 },
            },
        )
    ).mapping();
    defer mcl.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        2,
        mcl.project_instantaneous_cc(2).ordinate(),
    );
}

test "Mapping"
{
    const mcl = (
        try MappingCurveLinearMonotonic.init_knots(
            std.testing.allocator,
            &.{
                .{ .in = 0,  .out = 0  },
                .{ .in = 10, .out = 10 },
                .{ .in = 20, .out = 30 },
                .{ .in = 30, .out = 30 },
                .{ .in = 40, .out = 0 },
                .{ .in = 50, .out = -10 },
            },
        )
    ).mapping();
    defer mcl.deinit(std.testing.allocator);

    const TestThing = struct {
        tp : opentime.Ordinate,
        exp : opentime.Ordinate,
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
            try std.testing.expectEqual(
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

    const mcl = (
        try MappingCurveLinearMonotonic.init_curve(
            allocator,
            .{
                .knots = &.{
                    .{ .in = 0,  .out = 0  },
                    .{ .in = 10, .out = 10 },
                    .{ .in = 20, .out = 30 },
                },
            },
        )
    ).mapping();
    defer mcl.deinit(allocator);

    const result = try mcl.shrink_to_output_interval(
        allocator,
        .{ 
            .start = 5,
            .end_ordinate = 25,
        },
    );

    defer result.deinit(allocator);

    const m2 = try mcl.clone(allocator);
    defer m2.deinit(allocator);

    const c = try result.clone(allocator);
    defer c.deinit(allocator);

    const result_extents = result.output_bounds();
    try std.testing.expectEqual(
        5,
        result_extents.start,
    );
    try std.testing.expectEqual(
        25,
        result_extents.end_ordinate,
    );
}
