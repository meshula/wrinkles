//! Topology Library
//!
//! Public interface is the Mapping, a monotonic mapping function, and the
//! Topology, a sequence of Mappings that are used to transform between spaces.
//!
//! Topologys can be "joined" together such that a topology mapping space a to
//! space b can be joined with a topology that maps from space b to space c
//! resulting in a topology that maps from space a to space c.

const topology = @import("topology.zig");
pub const Topology = topology.Topology;
pub const join = topology.join;

pub const mapping = @import("mapping.zig");
pub const Mapping = mapping.Mapping;
pub const MappingAffine = mapping.MappingAffine;
pub const MappingEmpty = mapping.MappingEmpty;
pub const MappingCurveLinearMonotonic = mapping.MappingCurveLinearMonotonic;

test 
{
    _ = topology;
    _ = mapping;
    _ = @import("mapping_affine.zig");
    _ = @import("mapping_curve_bezier.zig");
    _ = @import("mapping_curve_linear.zig");
    _ = @import("mapping_empty.zig");
}
