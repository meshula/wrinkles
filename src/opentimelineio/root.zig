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

/// Read timeline from buffer to SerializableTimeline.
/// Supports: .otio (JSON), .tla, .tlb (FlatBuffers)
/// Note: .tlz format requires file access; use read_from_file instead.
/// Useful for sokol_fetch callbacks or network transfers.
pub const read_from_buffer = serialization.read_from_buffer;

/// Write timeline from SerializableTimeline to buffer.
/// Supports: .tla, .tlb (FlatBuffers)
/// Note: .tlz format requires file access; use write_to_file instead.
/// Returns an allocated buffer that the caller must free.
pub const write_to_buffer = serialization.write_to_buffer;

// Collection format support (.tlca, .tlcb)

/// Read collection from file to SerializableCollection.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
pub const read_collection_from_file = serialization.read_collection_from_file;

/// Read collection from buffer to SerializableCollection.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
pub const read_collection_from_buffer = serialization.read_collection_from_buffer;

/// Write collection from SerializableCollection to file.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
pub const write_collection_to_file = serialization.write_collection_to_file;

/// Write collection from SerializableCollection to buffer.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
/// Returns an allocated buffer that the caller must free.
pub const write_collection_to_buffer = serialization.write_collection_to_buffer;

/// Options for writing collection files
pub const CollectionWriteOptions = serialization.CollectionWriteOptions;

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
