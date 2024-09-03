//! MappingCurveLinear / OpenTimelineIO
//!
//! Linear Time Curve Mapping

const std = @import("std");

const mapping_mod = @import("mapping");
const curve = @import("curve");
const opentime = @import("opentime");

/// a linear mapping from input to output
pub const MappingCurveLinear = struct {
    input_to_output_curve: curve.TimeCurveLinear,

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
        crv: curve.TimeCurveLinear,
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
            .start_seconds = extents[0].time,
            .end_seconds = extents[1].time,
        };
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        const extents = self.input_to_output_curve.extents();

        return .{
            .start_seconds = extents[0].value,
            .end_seconds = extents[1].value,
        };
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        ordinate: mapping_mod.Ordinate,
    ) !mapping_mod.Ordinate 
    {
        return self.input_to_output_curve.evaluate(ordinate);
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
                .{ .time = 0,  .value = 0  },
                .{ .time = 10, .value = 10 },
            },
        )
    ).mapping();
    defer mcl.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        2,
        mcl.project_instantaneous_cc(2),
    );
}
