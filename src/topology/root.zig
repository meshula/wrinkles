//! # Topology Library
//!
//! The mathematical underpinning of temporal projection.  `topology.Topology`
//! is a right met set of individually continuous and 1:1 `mapping.Mapping`s.
//! A `topology.Topology` transforms from its input space to its output space
//! and can be joined with other topologies (using the `join` function) to
//! collapse transformations together into a single operation.
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
    _ = @import("mapping_curve_linear.zig");
    _ = @import("mapping_empty.zig");
}
