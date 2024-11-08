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
        return self.input_to_output_xform.applied_to_interval(self.input_bounds_val);
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        if (
            !self.input_bounds_val.overlaps_seconds(ordinate) 
            // allow projecting the end point
            and ordinate != self.input_bounds_val.end_seconds
        )
        {
            return opentime.OUTOFBOUNDS;
        }

        return .{ 
            .SuccessOrdinate = self.input_to_output_xform.applied_to_ordinate(ordinate),
        };
    }

    /// project from the output space back to the input space
    pub fn project_instantaneous_cc_inv(
        self: @This(),
        output_ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        if (
            !self.output_bounds().overlaps_seconds(output_ordinate) 
            // allow projecting the end point
            and output_ordinate != self.output_bounds().end_seconds
        )
        {
            return opentime.OUTOFBOUNDS;
        }

        return .{
            .SuccessOrdinate = self.input_to_output_xform.inverted(
            ).applied_to_ordinate(output_ordinate)
        };
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
                        .start_ordinate = self.input_bounds_val.start_ordinate,
                        .end_seconds = pt_input,
                    },
                    .input_to_output_xform = self.input_to_output_xform,
                },
            },
            .{ 
                .affine = .{
                    .input_bounds_val = .{
                        .start_ordinate = pt_input,
                        .end_seconds = self.input_bounds_val.end_seconds,
                    },
                    .input_to_output_xform = self.input_to_output_xform,
                },
            },
        };
    }

    /// split at any of the points that are within the bounds of the mapping
    pub fn split_at_input_points(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) ![]const mapping_mod.Mapping
    {
        var result_mappings = (
            std.ArrayList(mapping_mod.Mapping).init(allocator)
        );

        var maybe_first_pt: ?usize = null;
        
        for (input_points, 0..)
            |pt, pt_ind|
        {
            if (
                pt > self.input_bounds_val.start_ordinate
                and pt < self.input_bounds_val.end_seconds
            )
            {
                maybe_first_pt = pt_ind;
                break;
            }
        }

        // none of the points map
        if (maybe_first_pt == null)
        {
            try result_mappings.append(self.mapping());
            return try result_mappings.toOwnedSlice();
        }

        var current_start = self.input_bounds_val.start_ordinate;
        var current_end_ind = maybe_first_pt.?;

        while (current_end_ind < input_points.len)
        {
            var current_end = input_points[current_end_ind];

            if (current_end > self.input_bounds_val.end_seconds)
            {
                current_end = self.input_bounds_val.end_seconds;
                current_end_ind = input_points.len;
            }

            try result_mappings.append(
                .{
                    .affine = .{
                        .input_bounds_val = .{
                            .start_ordinate = current_start,
                            .end_seconds = current_end,
                        },
                        .input_to_output_xform = (
                            self.input_to_output_xform
                        ),
                    },
                },
            );

            current_start = current_end;
            current_end_ind += 1;
        }

        return try result_mappings.toOwnedSlice();
    }
};
pub const INFINITE_IDENTITY = (
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
        ma.project_instantaneous_cc(12).ordinate(),
    );
}

test "MappingAffine: non-identity"
{
    const ma = (
        MappingAffine{
            .input_bounds_val = .{
                .start_ordinate = 3,
                .end_seconds = 6,
            },
            .input_to_output_xform = .{
                .offset = 2,
                .scale = 4,
            },
        }
    ).mapping();

   try std.testing.expectEqual(
       14,
       ma.project_instantaneous_cc(3).ordinate(),
    );
}

