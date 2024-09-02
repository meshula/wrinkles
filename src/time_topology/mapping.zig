//! Mapping / OpenTimelineIO
//!
//! Functions and structs related to the Mapping component of OTIO.

const std = @import("std");
const opentime = @import("opentime");

const serialization = @import("serialization.zig");

pub const Ordinate = f32;

/// A Mapping is a polymorphic container for a function that maps from an
/// "input" space to an "output" space.  Mappings can be joined with other
/// mappings via function composition to build new transformations via common
/// spaces. Mappings can project ordinates and ranges from their input space
/// to their output space.  Some (but not all) mappings are also invertible.
const Mapping = union (enum) {
    empty: MappingEmpty,
    // affine: MappingAffine,
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
};

/// Regardless what the input ordinate is, there is no value mapped to it
const MappingEmpty = struct {
    const OTIO_SCHEMA = "MappingEmpty.1";

    /// build a generic mapping from this empty mapping
    pub fn mapping(
        self:@This(),
    ) Mapping
    {
        return .{
            .empty = self,
        };
    }

    pub fn project_instantaneous_cc(
        _: @This(),
        _: Ordinate,
    ) !Ordinate 
    {
        return error.OutOfBounds;
    }

    pub fn inverted(
        _: @This()
    ) !MappingEmpty 
    {
        return .{};
    }

    pub fn input_bounds(
        _: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        return opentime.interval.INF_CTI;
    }

    pub fn output_bounds(
        _: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        return opentime.interval.INF_CTI;
    }

    pub fn clone(
        _: @This(),
        _: std.mem.Allocator,
    ) !MappingEmpty
    {
        return EMPTY;
    }
};
const EMPTY = MappingEmpty{};

test "MappingEmpty: instantiate and convert"
{
    const me = (MappingEmpty{}).mapping();
    const json_txt =  try serialization.to_string(
        std.testing.allocator,
        me
    );
    defer std.testing.allocator.free(json_txt);
}

test "MappingEmpty: Project"
{
    const me = (MappingEmpty{}).mapping();

    var v : f32 = -10;
    while (v < 10)
        : (v += 0.2)
    {
        try std.testing.expectError(
            error.OutOfBounds,
            me.project_instantaneous_cc(1.0)
        );
    }
}

test "MappingEmpty: Bounds"
{
    const me = (MappingEmpty{}).mapping();

    const i_b = me.input_bounds();
    try std.testing.expect(i_b.is_infinite());
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.start_seconds,
        i_b.start_seconds
    );
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.end_seconds,
        i_b.end_seconds
    );

    const o_b = me.output_bounds();
    try std.testing.expect(o_b.is_infinite());
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.start_seconds,
        o_b.start_seconds
    );
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.end_seconds,
        o_b.end_seconds
    );
}

/// An affine mapping from intput to output
const MappingAffine = struct {
};

/// a linear mapping from input to output
const MappingCurveLinear = struct {
};

/// a Cubic Bezier Mapping from input to output
const MappingCurveBezier = struct {
};


