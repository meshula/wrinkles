//! Slim OpenTimelineIO Reimplementation for testing high level API
//! Uses the rest of the wrinkles library to implement high level functions
//! that might eventually get ported to 'real' OTIO.

pub const core = @import("opentimelineio/core.zig");
pub const ComposedValueRef = core.ComposedValueRef;
pub const ProjectionOperator = core.ProjectionOperator;
pub const ProjectionOperatorMap = core.ProjectionOperatorMap;
pub const TopologicalMap = core.TopologicalMap;
pub const SpaceLabel = core.SpaceLabel;
pub const build_topological_map = core.build_topological_map;
pub const projection_map_to_media_from = core.projection_map_to_media_from;


pub const schema = @import("opentimelineio/schema.zig");
pub const Clip = schema.Clip;
pub const Gap = schema.Gap;
pub const Warp = schema.Warp;
pub const Track = schema.Track;
pub const Stack = schema.Stack;
pub const Timeline = schema.Timeline;

const otio_json = @import("opentimelineio_json.zig");

pub const read_from_file = otio_json.read_from_file;

test {
    const otio_highlevel_tests = @import(
        "opentimelineio_highlevel_test.zig"
    );

    _ = otio_json;
    _ = otio_highlevel_tests;
}
