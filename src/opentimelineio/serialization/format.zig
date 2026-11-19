//! File formats and read/write options.
//!
//! Shared by the adapter and every format codec.  Depends only on
//! bundle_utils.zig, so codecs never need to import adapter.zig.

const std = @import("std");

const bundle_utils = @import("bundle_utils.zig");

/// Errors raised by format detection and dispatch.  The public `Error` set
/// (adapter.zig) combines these with the versioning and bundle errors.
pub const FormatError = error{
    /// The path has no file extension to detect a format from.
    NoFileExtension,
    /// The file extension is not a supported format.
    UnsupportedFileFormat,
    /// The format can be read but not written (e.g. .otio).
    FormatIsReadOnly,
    /// The format stores a collection, but a timeline was given or expected.
    NotATimelineFormat,
    /// The format stores a timeline, but a collection was given or expected.
    NotACollectionFormat,
    /// Bundles (.tlz/.tlcz) can only be read from or written to files.
    BundleRequiresFileAccess,
    /// A schema handle that is not a timeline or collection was given.
    ExpectedTimelineOrCollection,
    /// The document's root object cannot be represented (e.g. an OTIO
    /// SerializableCollection read as a timeline).
    UnsupportedRootObject,
};

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

    /// Detect file format from path extension (case-insensitive).
    /// Returns error.NoFileExtension if path has no extension.
    /// Returns error.UnsupportedFileFormat if extension is not recognized.
    pub fn from_path(
        file_path: []const u8,
    ) !FileFormat
    {
        // Includes the leading '.'; empty if the basename has none.
        const dotted = std.fs.path.extension(file_path);
        if (dotted.len <= 1)
        {
            return error.NoFileExtension;
        }
        const extension = dotted[1..];

        var lower_buf: [8]u8 = undefined;
        if (extension.len > lower_buf.len)
        {
            return error.UnsupportedFileFormat;
        }
        const lower = std.ascii.lowerString(&lower_buf, extension);

        return std.meta.stringToEnum(FileFormat, lower) orelse
            return error.UnsupportedFileFormat;
    }
};

/// Options for reading timeline/collection files.
pub const ReadOptions = struct {
    /// Override format detection from file extension.
    /// If null, format is detected from the input file path.
    format: ?FileFormat = null,

    /// What content to include in the result.
    content_filter: ContentFilter = .all,

    /// For bundles: also extract every entry (content, version, media/) to
    /// this existing directory.
    ///
    /// Reads never rewrite media URIs: they are returned exactly as stored,
    /// relative to the document (for bundles, `media/...` relative to the
    /// bundle root).
    extract_to_directory: ?[]const u8 = null,

    pub const ContentFilter = enum {
        /// Read everything including metadata
        all,
        /// Read structure but skip metadata_map (faster for large files)
        all_except_metadata,

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

    /// Schema version to write (see versioning.zig).  Null writes
    /// `CURRENT_SCHEMA_VERSION`.  Older versions are produced by the root
    /// type's downgrade table from a copy of the data; the input is never
    /// modified.  `error.DowngradeNotSupported` if a step is missing,
    /// `error.DowngradeTargetIsNewer` if the target is newer than the data.
    target_version: ?u32 = null,

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
        /// Encoding of the timeline/collection inside the bundle
        content_format: bundle_utils.BundleFormat = .tla,
        /// How to handle media file references
        media_policy: bundle_utils.MediaReferencePolicy = .missing_if_not_file,
        /// Directory that relative media URIs are resolved against when
        /// locating files to copy into the bundle; usually the directory of
        /// the source document.  Null means the current working directory.
        media_base_dir: ?[]const u8 = null,
        /// Encode the bundle but do not write the file
        dryrun: bool = false,
    };

};
