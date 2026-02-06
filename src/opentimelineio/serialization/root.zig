//! Serialization module for OpenTimelineIO
//!
//! ## Main API
//!
//! Use the top-level functions for simple read/write operations:
//! - `read_from_file()` - Read timeline/collection, returns schema handle
//! - `write_to_file()` - Write timeline/collection to file
//! - `read_from_reader()` - Read from stream with explicit format
//! - `write_to_writer()` - Write to stream with explicit format
//!
//! ## Serializable API
//!
//! For advanced use cases where you need the intermediate representation:
//! - `serializable.read_from_file()` - Returns SerializableRoot
//! - `serializable.write_to_file()` - Accepts SerializableRoot

pub const adapter = @import("adapter.zig");

// ============================================================================
// Primary Public API - Returns schema types (CompositionItemHandle)
// ============================================================================

/// Read timeline or collection from file, returning a schema handle.
/// Format is auto-detected from the file extension.
pub const read_from_file = adapter.read_from_file;

/// Write timeline or collection to file.
/// Format is auto-detected from extension, or use options.format to override.
pub const write_to_file = adapter.write_to_file;

/// Read from a reader with explicit format.
pub const read_from_reader = adapter.read_from_reader;

/// Write to a writer with explicit format.
pub const write_to_writer = adapter.write_to_writer;

// ============================================================================
// Types
// ============================================================================

/// Supported file formats
pub const FileFormat = adapter.FileFormat;

/// Options for reading files
pub const ReadOptions = adapter.ReadOptions;

/// Options for writing files
pub const WriteOptions = adapter.WriteOptions;

/// Union of timeline or collection (serializable form)
pub const SerializableRoot = adapter.SerializableRoot;

/// Handle to schema composition items
pub const CompositionItemHandle = adapter.CompositionItemHandle;

// ============================================================================
// Serializable Submodule - Returns serializable types
// ============================================================================

/// Submodule for working with SerializableRoot directly.
/// Use this when you need to preserve/manipulate the intermediate representation.
pub const serializable = adapter.serializable;

// ============================================================================
// Format-specific modules (for advanced use)
// ============================================================================

pub const ascii = @import("ascii.zig");
pub const binary = @import("binary.zig");
pub const bundle = @import("bundle.zig");
pub const bundle_utils = @import("bundle_utils.zig");
pub const legacy_json = @import("legacy_json.zig");

// ============================================================================
// Legacy API (deprecated - use new unified API above)
// ============================================================================

/// Deprecated: Use WriteOptions.MetadataMode instead
pub const MetadataMode = adapter.MetadataOptions.Write;

/// Deprecated: Use write_to_file() instead
pub const write_timeline_to_file = adapter.write_timeline_to_file;

/// Deprecated: Use serializable.read_from_file() for collections
pub const read_collection_from_file = ascii.read_collection_from_file;

/// Deprecated: Use read_from_file() or serializable types
pub const SerializableCollection = ascii.SerializableCollection;

/// Deprecated: Use buffer-based operations via serializable submodule
pub const read_from_buffer = ascii.read_from_buffer;

/// Deprecated: Use buffer-based operations via serializable submodule
pub const write_to_buffer = ascii.write_to_buffer;

/// Deprecated: Use buffer-based operations via serializable submodule
pub const read_collection_from_buffer = ascii.read_collection_from_buffer;
