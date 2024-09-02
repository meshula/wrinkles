//! Mapping / OpenTimelineIO
//!
//! Functions and structs related to the Mapping component of OTIO.

const std = @import("std");

const opentime = @import("opentime");
const serialization = @import("serialization.zig");
const mapping_empty = @import("mapping_empty.zig");

pub const Ordinate = f32;

/// A Mapping is a polymorphic container for a function that maps from an
/// "input" space to an "output" space.  Mappings can be joined with other
/// mappings via function composition to build new transformations via common
/// spaces. Mappings can project ordinates and ranges from their input space
/// to their output space.  Some (but not all) mappings are also invertible.
pub const Mapping = union (enum) {
    empty: mapping_empty.MappingEmpty,
    affine: MappingAffine,
    // linear: MappingCurveLinear,
    // bezier: MappingCurveBezier,

    // project an instantaneous ordinate from the input space to the output
    // space
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


/// An affine mapping from intput to output
pub const MappingAffine = struct {
    /// defaults to an infinite identity
    input_bounds_val: opentime.ContinuousTimeInterval = opentime.INF_CTI,
    input_to_output_xform: opentime.AffineTransform1D = opentime.IDENTITY_TRANSFORM, 

    pub fn mapping(
        self: @This(),
    ) Mapping
    {
        return .{ .affine = self };
    }

    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        return self.input_bounds_val;
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        return self.input_to_output_xform.applied_to_cti(self.input_bounds_val);
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        ordinate: Ordinate,
    ) !Ordinate 
    {
        if (
            !self.input_bounds_val.overlaps_seconds(ordinate) 
            // allow projecting the end point
            and ordinate != self.input_bounds_val.end_seconds
        )
        {
            return Mapping.ProjectionError.OutOfBounds;
        }

        return self.input_to_output_xform.applied_to_seconds(ordinate);
    }
};
pub const INFINITE_IDENTIY = (
    MappingAffine{
        .input_bounds_val = opentime.INF_CTI,
        .input_to_output_xform = opentime.IDENTITY_TRANSFORM,
    }
).mapping();

test "MappingAffine: instantiate (identity)"
{
    const ma = (MappingAffine{}).mapping();

    try std.testing.expectEqual(
        12, 
        ma.project_instantaneous_cc(12),
    );
}

test "MappingAffine: non-identity"
{
    const ma = (
        MappingAffine{
            .input_bounds_val = .{
                .start_seconds = 3,
                .end_seconds = 6,
            },
            .input_to_output_xform = .{
                .offset_seconds = 2,
                .scale = 4,
            },
        }
    ).mapping();

   try std.testing.expectEqual(
       14,
       ma.project_instantaneous_cc(3),
    );
}

/// a linear mapping from input to output
pub const MappingCurveLinear = struct {
};

/// a Cubic Bezier Mapping from input to output
pub const MappingCurveBezier = struct {
};


