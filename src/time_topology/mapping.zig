//! Mapping / OpenTimelineIO
//!
//! Functions and structs related to the Mapping component of OTIO.

const std = @import("std");

const opentime = @import("opentime");
const serialization = @import("serialization.zig");

const mapping_empty = @import("mapping_empty.zig");
const mapping_affine = @import("mapping_affine.zig");
const mapping_curve_linear = @import("mapping_curve_linear.zig");
const mapping_curve_bezier = @import("mapping_curve_bezier.zig");

/// A Mapping is a polymorphic container for a function that maps from an
/// "input" space to an "output" space.  Mappings can be joined with other
/// mappings via function composition to build new transformations via common
/// spaces. Mappings can project ordinates and ranges from their input space
/// to their output space.  Some (but not all) mappings are also invertible.
pub const Mapping = union (enum) {
    empty: mapping_empty.MappingEmpty,
    affine: mapping_affine.MappingAffine,
    linear: mapping_curve_linear.MappingCurveLinear,
    bezier: mapping_curve_bezier.MappingCurveBezier,

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
        ord: opentime.Ordinate,
    ) !opentime.Ordinate 
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

/// A Topology binds regions of a one dimensional space to a sequence of right
/// met mappings, separated by a list of end points.  There are implicit
/// "Empty" mappings outside of the end points which map to no values before
/// and after the segments defined by the Topology.
pub const TopologyMapping = struct {
    end_points: []const opentime.Ordinate,
    mappings: []const Mapping,
};

pub fn join_aff_aff(
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_affine.MappingAffine,
    },
) mapping_affine.MappingAffine
{
    return .{
        .input_to_other_xform = (
            args.b2c.input_to_output_xform.applied_to_transform(
                args.a2b.input_to_output_xform,
            )
        ),
    };
}

pub fn join_aff_lin(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_curve_linear.MappingCurveLinear,
    },
) mapping_affine.MappingCurveLinear
{
    return .{
        .input_to_output_curve = args.b2c.input_to_output_curve.project_affine(
            allocator,
            args.a2b.input_to_other_xform,
            args.a2b.input_bounds_val,
        ),
    };
}

pub fn join_lin_aff(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_linear.MappingCurveLinear,
        b2c: mapping_affine.MappingAffine,
    },
) mapping_affine.MappingCurveLinear
{
    return .{
        .input_to_output_curve = args.b2c.input_to_output_curve.project_affine(
            allocator,
            args.a2b.input_to_other_xform,
            args.a2b.input_bounds_val,
        ),
    };
}

pub fn join_aff_bez(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_affine.MappingCurveBezier,
    },
) mapping_affine.MappingCurveBezier
{
    return .{
        .input_to_output_curve = args.b2c.input_to_output_curve.project_affine(
            allocator,
            args.a2b.input_to_other_xform,
            args.a2b.input_bounds_val,
        ),
    };
}

////
///// Given two mappings, one that maps from space a->space b and a second that
///// maps from space b to space c, joins two mappings via their common
///// coordinate system (Referred to in the arguments as "b"), and computes the
///// mapping from space a->space c.
/////
///// Does not transform the mappings prior to joining, and the computation
///// happens over the intersection of their domains within the common coordinate
///// system (b).
/////
///// Handles the type mapping:
/////
/////     .    a2b ->
///// b2c v  | empty | affine | linear | bezier |
///// -------|-------|--------|--------|--------|
///// empty  | empty | empty  | empty  | empty  | 
///// affine | empty | affine | linear | bezier |
///// linear | empty | linear | linear | linear |
///// bezier | empty | bezier | linear | linear |
///// -------|-------|--------|--------|--------|
/////
///// (return value is always a `Mapping`)
/////
//pub fn join(
//    allocator: std.mem.Allocator,
//    args: struct{
//        a2b: Mapping,
//        b2c: Mapping,
//    },
//) Mapping
//{
//    const a2b = args.a2b;
//    const b2c = args.b2c;
//
//    if (a2b == .empty or b2c == .empty) {
//        return mapping_empty.EMPTY;
//    }
//
//    return switch (b2c) {
//        .affine => |b2c_aff| switch (a2b) {
//            .affine => |a2b_aff| join_aff_aff(
//                .{ .a2b = a2b_aff, .b2c = b2c_aff, },
//            ).mapping(),
//            .linear => |a2b_lin| join_lin_aff(
//                .{ .a2b = a2b_lin, .b2c = b2c_aff }
//            ).mapping(),
//            .bezier => |a2b_bez| join_bez_aff(
//                .{ .a2b = a2b_bez, .b2c = b2c_aff }
//            ).mapping(),
//            .empty => mapping_empty.EMPTY,
//        },
//        .linear => |b2c_lin| switch (a2b) {
//            .affine => |a2b_aff| join_aff_lin(
//                .{ .a2b = a2b_aff, .b2c = b2c_lin, },
//            ).mapping(),
//            .linear => |a2b_lin| join_lin_lin(
//                .{ .a2b = a2b_lin, .b2c = b2c_lin }
//            ).mapping(),
//            .bezier => |a2b_bez| join_bez_lin(
//                .{ .a2b = a2b_bez, .b2c = b2c_lin }
//            ).mapping(),
//            .empty => mapping_empty.EMPTY,
//        },
//        .bezier => |b2c_bez| switch (a2b) {
//            .affine => |a2b_aff| join_aff_bez(
//                .{ .a2b = a2b_aff, .b2c = b2c_bez, },
//            ).mapping(),
//            .linear => |a2b_lin| join_lin_bez(
//                .{ .a2b = a2b_lin, .b2c = b2c_bez }
//            ).mapping(),
//            .bezier => |a2b_bez| join_bez_bez(
//                .{ .a2b = a2b_bez, .b2c = b2c_bez }
//            ).mapping(),
//            .empty => mapping_empty.EMPTY,
//        },
//    };
//}
