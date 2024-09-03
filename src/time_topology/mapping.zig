//! Mapping / OpenTimelineIO
//!
//! Functions and structs related to the Mapping component of OTIO.

const std = @import("std");

const opentime = @import("opentime");
const serialization = @import("serialization.zig");

const mapping_empty = @import("mapping_empty.zig");
const mapping_affine = @import("mapping_affine.zig");
const mapping_curve_linear = @import("mapping_curve_linear.zig");

pub const Ordinate = f32;

/// A Mapping is a polymorphic container for a function that maps from an
/// "input" space to an "output" space.  Mappings can be joined with other
/// mappings via function composition to build new transformations via common
/// spaces. Mappings can project ordinates and ranges from their input space
/// to their output space.  Some (but not all) mappings are also invertible.
pub const Mapping = union (enum) {
    empty: mapping_empty.MappingEmpty,
    affine: mapping_affine.MappingAffine,
    linear: mapping_curve_linear.MappingCurveLinear,
    bezier: MappingCurveBezier,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        return switch (self) {
            .empty, .affine => {},
            inline else => |m| m.deinit(allocator),
        };
    }

    /// project an instantaneous ordinate from the input space to the output
    /// space
    pub fn project_instantaneous_cc(
        self: @This(),
        ord: Ordinate,
    ) !Ordinate 
    {
        return switch (self) {
            inline else => |m| m.project_instantaneous_cc(ord),
        };
    }

    /// fetch (computing if necessary) the input bounds of the mapping
    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return switch (self) {
            inline else => |contained| contained.input_bounds(),
        };
    }

    /// fetch (computing if necessary) the output bounds of the mapping
    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return switch (self) {
            inline else => |contained| contained.output_bounds(),
        };
    }

    /// Make a copy of this Mapping
    pub fn clone(
        self: @This(),
    ) !Mapping
    {
        return switch (self) {
            inline else => |contained| contained.clone().mapping(),
        };
    }

    // @{ Errors
    pub const ProjectionError = error { OutOfBounds };
    // @}
};

const curve = @import("curve");

/// a Cubic Bezier Mapping from input to output
pub const MappingCurveBezier = struct {
    input_to_output_curve: curve.TimeCurve,

    pub fn init_curve(
        allocator: std.mem.Allocator,
        crv: curve.TimeCurve,
    ) MappingCurveBezier
    {
        return .{
            .input_to_output_curve = try crv.clone(allocator),
        };
    }

    pub fn init_segments(
        allocator: std.mem.Allocator,
        segments: []const curve.Segment,
    ) !MappingCurveBezier
    {
        return .{
            .input_to_output_curve = try curve.TimeCurve.init(
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
        ord: Ordinate,
    ) !Ordinate 
    {
        return try self.input_to_output_curve.evaluate(ord);
    }

    /// fetch (computing if necessary) the input bounds of the mapping
    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return self.input_to_output_curve.extents_time();
    }

    /// fetch (computing if necessary) the output bounds of the mapping
    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return self.input_to_output_curve.extents_value();
    }

    pub fn mapping(
        self: @This(),
    ) Mapping
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
                curve.Segment.init_from_start_end(
                    .{ .time = 0, .value = 0 },
                    .{ .time = 10, .value = 20 },
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

