//! File formats and read/write options.
//!
//! Shared by the adapter and every format codec; depends on nothing else in
//! the serialization package so codecs never need to import adapter.zig.

const std = @import("std");

/// Supported file formats for read/write operations. Format is auto-detected
/// from file extension, or can be specified explicitly.
pub const FileFormat = enum {
    /// Timeline ASCII format (ziggy-based, human-readable)
    tla,
    /// Timeline Binary format (FlatBuffers, high performance)
    tlb,
    /// Timeline Bundle (ZIP archive with embedded media)
    tlz,
    /// Collection ASCII format
    tlca,
    /// Collection Binary format
    tlcb,
    /// Collection Bundle (ZIP archive with embedded media)
    tlcz,
    /// Legacy OpenTimelineIO v1 JSON format (read-only)
    otio,

    /// Detect file format from path extension.
    /// Returns error.NoFileExtension if path has no extension.
    /// Returns error.UnsupportedFileFormat if extension is not recognized.
    pub fn from_path(
        file_path: []const u8,
    ) !FileFormat
    {
        const ext_start = std.mem.lastIndexOfScalar(
            u8,
            file_path,
            '.',
        ) orelse return error.NoFileExtension;

        const extension = file_path[ext_start + 1 ..];

        return std.meta.stringToEnum(FileFormat, extension) orelse
            return error.UnsupportedFileFormat;
    }
};

/// Options for reading timeline/collection files.
pub const ReadOptions = struct {
    /// What content to include in the result.
    content_filter: ContentFilter = .all,

    /// Base directory for resolving relative media paths.
    /// If null, paths are resolved relative to the file being read.
    media_base_dir: ?[]const u8 = null,

    /// For bundles: extract media files to this directory.
    /// If null, media paths point into the bundle.
    extract_to_directory: ?[]const u8 = null,

    pub const ContentFilter = enum {
        /// Read everything including metadata
        all,
        /// Read structure but skip metadata_map (faster for large files)
        all_except_metadata,
        /// Read only metadata, skip timeline structure
        only_metadata,

        pub const default: ContentFilter = .all;
    };
};

/// Options for writing timeline/collection files.
pub const WriteOptions = struct {
    /// Override format detection from file extension.
    /// If null, format is detected from the output file path.
    format: ?FileFormat = null,

    /// How to output metadata (affects TLA/TLCA formats).
    metadata_mode: MetadataMode = .hash_reference,

    /// Bundle-specific options. Ignored for non-bundle formats.
    bundle_options: ?BundleOptions = null,

    /// Controls how metadata is output in TLA format
    pub const MetadataMode = enum {
        /// Default behavior: use hash references with metadata_map
        hash_reference,
        /// Omit all metadata from output
        no_metadata,
        /// Print metadata inline on each clip
        inline_metadata,

        pub const default: MetadataMode = .hash_reference;
    };

    pub const BundleOptions = struct {
        /// Format for the timeline/collection within the bundle
        content_format: enum { tla, tlb } = .tla,
        /// How to handle media file references
        media_policy: MediaPolicy = .MissingIfNotFile,
        /// Base directory for resolving media paths
        media_base_dir: ?[]const u8 = null,

        pub const MediaPolicy = enum {
            /// Error if a referenced file doesn't exist
            ErrorIfNotFile,
            /// Mark as missing if file doesn't exist, continue
            MissingIfNotFile,
            /// Treat all media references as missing (don't copy files)
            AllMissing,
        };
    };

};
