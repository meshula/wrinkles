//! Slim OpenTimelineIO Reimplementation for testing high level API
//! Uses the rest of the wrinkles library to implement high level functions
//! that might eventually get ported to 'real' OTIO.

pub const references = @import("references.zig");
pub const CompositionItemHandle = references.CompositionItemHandle;
pub const TemporalSpace = references.TemporalSpace;

pub const projection = @import("projection.zig");
pub const ProjectionOperator = projection.ProjectionOperator;
pub const TemporalProjectionBuilder = projection.TemporalProjectionBuilder;

pub const temporal_tree = @import("temporal_tree.zig");

pub const schema = @import("schema.zig");
pub const Clip = schema.Clip;
pub const Gap = schema.Gap;
pub const Warp = schema.Warp;
pub const Transition = schema.Transition;
pub const Track = schema.Track;
pub const Stack = schema.Stack;
pub const Timeline = schema.Timeline;

pub const marker = @import("marker.zig");
pub const Marker = marker.Marker;
pub const MarkerColor = marker.MarkerColor;

pub const domain = @import("domain.zig");
pub const Domain = domain.Domain;

pub const serialization = @import("serialization/root.zig");
pub const hierarchy_text_render = @import("hierarchy_text_render.zig");

/// Read timeline from file to CompositionItemHandle (runtime schema).
/// Supports: .otio (JSON), .tla, .tlb (FlatBuffers), .tlz (bundle)
pub const read_from_file = serialization.read_from_file;

/// File format types for serialization operations
pub const FileFormat = serialization.FileFormat;


test {
    const otio_highlevel_tests = @import(
        "opentimelineio_highlevel_test.zig"
    );

    _ = otio_highlevel_tests;
    _ = temporal_tree;
    _ = schema;
    _ = marker;
    _ = references;
    _ = projection;
    _ = domain;
    _ = serialization;
}
