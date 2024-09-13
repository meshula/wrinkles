//! MappingCurveBezier / OpenTimelineIO
//!
//! Bezier Curve Mapping wrapper around the curve library

const std = @import("std");

const curve = @import("curve");
const opentime = @import("opentime");
const mapping_mod = @import("mapping.zig");

/// a Cubic Bezier Mapping from input to output
pub const MappingCurveBezier = struct {
    input_to_output_curve: curve.Bezier,

    pub fn init_curve(
        allocator: std.mem.Allocator,
        crv: curve.Bezier,
    ) MappingCurveBezier
    {
        return .{
            .input_to_output_curve = try crv.clone(allocator),
        };
    }

    pub fn init_segments(
        allocator: std.mem.Allocator,
        segments: []const curve.Bezier.Segment,
    ) !MappingCurveBezier
    {
        return .{
            .input_to_output_curve = try curve.Bezier.init(
                allocator,
                segments,
            )
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        self.input_to_output_curve.deinit(allocator);
    }

    /// project an instantaneous ordinate from the input space to the output
    /// space
    pub fn project_instantaneous_cc(
        self: @This(),
        ord: opentime.Ordinate,
    ) !opentime.Ordinate 
    {
        return try self.input_to_output_curve.output_at_input(ord);
    }

    /// fetch (computing if necessary) the input bounds of the mapping
    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return self.input_to_output_curve.extents_input();
    }

    /// fetch (computing if necessary) the output bounds of the mapping
    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return self.input_to_output_curve.extents_output();
    }

    pub fn mapping(
        self: @This(),
    ) mapping_mod.Mapping
    {
        return .{
            .bezier = self,
        };
    }
};

test "MappingCurveBezier: init and project"
{
    const mcb = (
        try MappingCurveBezier.init_segments(
            std.testing.allocator, 
            &.{ 
                curve.Bezier.Segment.init_from_start_end(
                    .{ .in = 0, .out = 0 },
                    .{ .in = 10, .out = 20 },
                ),
            },
            )
    ).mapping();
    defer mcb.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        10,  
        mcb.project_instantaneous_cc(5),
    );
}
