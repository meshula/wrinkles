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
        ordinate: opentime.Ordinate,
    ) !opentime.Ordinate 
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

    /// project from the output space back to the input space
    pub fn project_instantaneous_cc_inv(
        self: @This(),
        output_ordinate: opentime.Ordinate,
    ) !opentime.Ordinate 
    {
        if (
            !self.output_bounds().overlaps_seconds(output_ordinate) 
            // allow projecting the end point
            and output_ordinate != self.output_bounds().end_seconds
        )
        {
            return mapping_mod.Mapping.ProjectionError.OutOfBounds;
        }

        return self.input_to_output_xform.inverted().applied_to_seconds(
            output_ordinate
        );
    }

    pub fn clone(
        self: @This(),
        _: std.mem.Allocator,
    ) !MappingAffine
    {
        return .{
            .input_bounds_val = self.input_bounds_val,
            .input_to_output_xform = self.input_to_output_xform,
        };
    }

    pub fn shrink_to_output_interval(
        self: @This(),
        _: std.mem.Allocator,
        target_output_interval: opentime.ContinuousTimeInterval,
    ) !MappingAffine
    {
        const target_input_interval = (
            self.input_to_output_xform.inverted().applied_to_bounds(
                target_output_interval
            )
        );
        return .{
            .input_bounds_val = opentime.interval.intersect(
                self.input_bounds_val,
                target_input_interval,
            ) orelse .{},
            .input_to_output_xform = self.input_to_output_xform,
        };
    }

    pub fn shrink_to_input_interval(
        self: @This(),
        _: std.mem.Allocator,
        target_output_interval: opentime.ContinuousTimeInterval,
    ) !MappingAffine
    {
        return .{
            .input_bounds_val = (
                opentime.interval.intersect(
                    self.input_bounds_val,
                    target_output_interval,
                ) orelse return error.NoOverlap
            ),
            .input_to_output_xform = self.input_to_output_xform,
        };
    }

    pub fn split_at_input_point(
        self: @This(),
        allocator: std.mem.Allocator,
        pt_input: opentime.Ordinate,
    ) ![2]mapping_mod.Mapping
    {
        _ = allocator;

        return .{
            .{ 
                .affine = .{
                    .input_bounds_val = .{
                        .start_seconds = self.input_bounds_val.start_seconds,
                        .end_seconds = pt_input,
                    },
                    .input_to_output_xform = self.input_to_output_xform,
                },
            },
            .{ 
                .affine = .{
                    .input_bounds_val = .{
                        .start_seconds = pt_input,
                        .end_seconds = self.input_bounds_val.end_seconds,
                    },
                    .input_to_output_xform = self.input_to_output_xform,
                },
            },
        };
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

