//! MappingCurveLinear / OpenTimelineIO
//!
//! Linear Time Curve Mapping

const std = @import("std");

const mapping_mod = @import("mapping.zig");
const curve = @import("curve");
const opentime = @import("opentime");

/// a linear mapping from input to output
pub const MappingCurveLinear = struct {
    input_to_output_curve: curve.Linear,

    pub fn init_knots(
        allocator: std.mem.Allocator,
        knots: []const curve.ControlPoint,
    ) !MappingCurveLinear
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
        crv: curve.Linear,
    ) !MappingCurveLinear
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
        const extents = self.input_to_output_curve.extents();

        return .{
            .start_seconds = extents[0].in,
            .end_seconds = extents[1].in,
        };
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        const extents = self.input_to_output_curve.extents();

        return .{
            .start_seconds = extents[0].out,
            .end_seconds = extents[1].out,
        };
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        ordinate: opentime.Ordinate,
    ) !opentime.Ordinate 
    {
        return self.input_to_output_curve.output_at_input(ordinate);
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !mapping_mod.Mapping
    {
        return .{
            .linear = .{
                .curve = try self.input_to_output_curve.clone(allocator),
            },
        };
    }
};

test "MappingCurveLinear: init_knots"
{
    const mcl = (
        try MappingCurveLinear.init_knots(
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
        mcl.project_instantaneous_cc(2),
    );
}
