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

    pub fn linearized(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !mapping_mod.MappingCurveLinearMonotonic
    {
        return .{ 
            .input_to_output_curve = (
                try self.input_to_output_curve.linearized(allocator)
            ),
        };
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !MappingCurveBezier
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
    ) !MappingCurveBezier
    {
        const output_to_input_crv = try curve.inverted(
            allocator,
            self.input_to_output_curve
        );
        defer output_to_input_crv.deinit(allocator);

        const target_input_interval_as_crv = try (
            output_to_input_crv.project_affine(
                allocator,
                opentime.transform.IDENTITY_TRANSFORM,
                target_output_interval
            )
        );
        defer target_input_interval_as_crv.deinit(allocator);

        return .{
            .input_to_output_curve = (
                try self.input_to_output_curve.trimmed_in_input_space(
                    allocator,
                    target_input_interval_as_crv.extents_input()
                )
            ),
        };
    }

    pub fn shrink_to_input_interval(
        self: @This(),
        _: std.mem.Allocator,
        target_output_interval: opentime.ContinuousTimeInterval,
    ) !MappingCurveBezier
    {
        _ = self;
        _ = target_output_interval;
        if (true) {
            return error.NotImplementedBezierShringtoInput;
        }

        // return .{
        //     .input_bounds_val = (
        //         opentime.interval.intersect(
        //             self.input_bounds_val,
        //             target_output_interval,
        //         ) orelse return error.NoOverlap
        //     ),
        //     .input_to_output_xform = self.input_to_output_xform,
        // };
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
