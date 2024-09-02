//! Affine Transform Mapping

const std = @import("std");

const opentime = @import("opentime");
const mapping_mod = @import("mapping.zig");

/// An affine mapping from intput to output
pub const MappingAffine = struct {
    /// defaults to an infinite identity
    input_bounds_val: opentime.ContinuousTimeInterval = opentime.INF_CTI,
    input_to_output_xform: opentime.AffineTransform1D = opentime.IDENTITY_TRANSFORM, 

    pub fn mapping(
        self: @This(),
    ) mapping_mod.Mapping
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
        ordinate: mapping_mod.Ordinate,
    ) !mapping_mod.Ordinate 
    {
        if (
            !self.input_bounds_val.overlaps_seconds(ordinate) 
            // allow projecting the end point
            and ordinate != self.input_bounds_val.end_seconds
        )
        {
            return mapping_mod.Mapping.ProjectionError.OutOfBounds;
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

