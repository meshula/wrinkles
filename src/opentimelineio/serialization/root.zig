pub const ascii = @import("ascii.zig");
pub const binary = @import("binary.zig");
pub const bundle = @import("bundle.zig");
pub const bundle_utils = @import("bundle_utils.zig");
pub const legacy_json = @import("legacy_json.zig");
pub const adapter = @import("adapter.zig");

pub const SerializableCollection = ascii.SerializableCollection;
pub const MetadataMode = ascii.MetadataMode;

pub const write_timeline_to_file = adapter.write_timeline_to_file;
pub const read_collection_from_file = ascii.read_collection_from_file;

pub const write_to_file = adapter.write_timeline_to_file;
pub const read_from_file = legacy_json.read_from_file;
