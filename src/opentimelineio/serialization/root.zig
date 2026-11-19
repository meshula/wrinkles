//! Serialization module for OpenTimelineIO
//!
//! ## Main API (schema handles)
//!
//! - `read_from_file(allocator, io, path, options)`
//! - `write_to_file(allocator, io, handle, path, options)`
//! - `read_from_reader(allocator, reader, format, options)`
//! - `write_to_writer(allocator, handle, writer, format, options)`
//!
//! File functions detect the format from the extension; set
//! `options.format` to override.  Stream functions take the format
//! explicitly.  Bundles (.tlz/.tlcz) require the file functions.
//!
//! ## Serializable API (intermediate representation)
//!
//! `serializable.{read_from_file, write_to_file, read_from_reader,
//! write_to_writer}` have the same shape but take/return
//! `serializable.Root`, preserving metadata hash maps and other
//! serialization-only detail.
//!
//! ## Memory ownership
//!
//! Every read result owns all of its memory; free it with
//! `deinit(allocator)` using the allocator passed to the read.  See
//! adapter.zig for details.
//!
//! ## Errors
//!
//! `Error` lists the errors the library raises itself.  Functions may also
//! return allocation, I/O and format-specific decoding errors.

const std = @import("std");

pub const adapter = @import("adapter.zig");

// ============================================================================
// Main API
// ============================================================================

/// Read a timeline or collection from a file as a schema handle.
pub const read_from_file = adapter.read_from_file;

/// Write a timeline or collection schema handle to a file.
pub const write_to_file = adapter.write_to_file;

/// Read a timeline or collection from a reader as a schema handle.
pub const read_from_reader = adapter.read_from_reader;

/// Write a timeline or collection schema handle to a writer.
pub const write_to_writer = adapter.write_to_writer;

/// Read/write the serializable intermediate representation directly.
pub const serializable = adapter.serializable;

// ============================================================================
// Types
// ============================================================================

/// Supported file formats
pub const FileFormat = adapter.FileFormat;

/// Static properties of a file format; see `descriptor`.
pub const FormatDescriptor = adapter.FormatDescriptor;

/// Static properties of `format` (root type, bundle, read-only).
pub const descriptor = adapter.descriptor;

/// Options for reading
pub const ReadOptions = adapter.ReadOptions;

/// Options for writing
pub const WriteOptions = adapter.WriteOptions;

/// Errors raised by the serialization library itself
pub const Error = adapter.Error;

/// Handle to schema composition items
pub const CompositionItemHandle = adapter.CompositionItemHandle;

// ============================================================================
// Format-specific modules (advanced use)
// ============================================================================

pub const ascii = @import("ascii.zig");
pub const binary = @import("binary.zig");
pub const bundle = @import("bundle.zig");
pub const bundle_utils = @import("bundle_utils.zig");
pub const legacy_json = @import("legacy_json.zig");
pub const versioning = @import("versioning.zig");

test {
    _ = adapter;
    _ = ascii;
    _ = binary;
    _ = bundle;
    _ = bundle_utils;
    _ = legacy_json;
    _ = versioning;
    _ = @import("format.zig");
    _ = @import("serializable.zig");
}
