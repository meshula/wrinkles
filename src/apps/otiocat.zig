//! otiocat - Universal timeline/collection format converter
//!
//! Reads timeline files (.otio, .tla, .tlb, .tlz) and writes to various formats.
//! Also supports collection files (.tlca, .tlcb) for grouped timeline containers.
//!
//! Usage:
//!   otiocat <input> [output]
//!
//! If no output file is specified, prints TLA/TLCA format to stdout.
//!
//! Examples:
//!   # Timeline conversions
//!   otiocat timeline.otio                   # JSON to TLA (stdout)
//!   otiocat timeline.otio timeline.tla      # JSON to TLA (file)
//!   otiocat timeline.otio timeline.tlb      # JSON to Binary (FlatBuffers)
//!   otiocat timeline.tla timeline.tlz       # TLA to TLZ bundle
//!   otiocat timeline.tlz timeline.tla       # TLZ bundle to TLA
//!   otiocat timeline.tla timeline.tlb       # TLA to Binary
//!   otiocat timeline.tlb timeline.tla       # Binary to TLA
//!
//!   # Collection conversions
//!   otiocat collection.tlca collection.tlcb # ASCII to FlatBuffers
//!   otiocat collection.tlcb collection.tlca # FlatBuffers to ASCII

const std = @import("std");
const string = @import("string_stuff");
const otio = @import("opentimelineio");
const serialization = otio.serialization;

const builtin = @import("builtin");

/// Use the new unified WriteOptions.MetadataMode
const MetadataMode = serialization.WriteOptions.MetadataMode;

const TARGET_VERSION_FLAG = "--target-version=";

const State = struct {
    input_path: []const u8,
    output_path: ?[]const u8,
    metadata_mode: MetadataMode = .hash_reference,

    // TLZ bundle options
    bundle_format: serialization.bundle_utils.BundleFormat = .tla,
    media_policy: serialization.bundle_utils.MediaReferencePolicy = .missing_if_not_file,

    /// Schema version to write; null writes the current version.
    maybe_target_version: ?u32 = null,

    /// Print the writable schema versions and exit.
    list_target_versions: bool = false,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.input_path);

        if (self.output_path) 
            |path| 
        {
            allocator.free(path);
        }
    }
};

/// Parse the commandline arguments and setup the state
fn parse_args(
    allocator: std.mem.Allocator,
    args: std.process.Args,
) !State
{
    var arg_iter = args.iterate();

    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var metadata_mode: MetadataMode = .hash_reference;
    var bundle_format: serialization.bundle_utils.BundleFormat = .tla;
    var media_policy: serialization.bundle_utils.MediaReferencePolicy = .missing_if_not_file;
    var maybe_target_version: ?u32 = null;
    var list_target_versions = false;

    // Ignore the app name, always first in args
    _ = arg_iter.skip();

    var positional_count: usize = 0;

    // Read all the arguments from the commandline
    while (arg_iter.next())
        |nextarg|
    {
        const arg: [:0]const u8 = nextarg;

        // Handle options (flags starting with -)
        if (
            string.eql_latin_s8(arg, "--help") 
            or string.eql_latin_s8(arg, "-h"))
        {
            usage("");
        }
        else if (
            string.eql_latin_s8(arg, "--no-metadata") 
            or string.eql_latin_s8(arg, "-M")
            )
        {
            metadata_mode = .no_metadata;
        }
        else if (string.eql_latin_s8(arg, "--inline-metadata") or
            string.eql_latin_s8(arg, "-m"))
        {
            metadata_mode = .inline_metadata;
        }
        // TLZ bundle format options
        else if (string.eql_latin_s8(arg, "--bundle-format=tla"))
        {
            bundle_format = .tla;
        }
        else if (string.eql_latin_s8(arg, "--bundle-format=tlb"))
        {
            bundle_format = .tlb;
        }
        // TLZ media policy options
        else if (string.eql_latin_s8(arg, "--media-policy=error"))
        {
            media_policy = .error_if_not_file;
        }
        else if (string.eql_latin_s8(arg, "--media-policy=missing"))
        {
            media_policy = .missing_if_not_file;
        }
        else if (string.eql_latin_s8(arg, "--media-policy=all-missing"))
        {
            media_policy = .all_missing;
        }
        else if (std.mem.startsWith(u8, arg, TARGET_VERSION_FLAG))
        {
            maybe_target_version = std.fmt.parseInt(
                u32,
                arg[TARGET_VERSION_FLAG.len..],
                10,
            ) catch usage("Invalid --target-version value.");
        }
        else if (string.eql_latin_s8(arg, "--list-target-versions"))
        {
            list_target_versions = true;
        }
        else if (arg.len > 0 and arg[0] == '-')
        {
            // Unknown flag
            usage("Unknown option.");
        }
        else
        {
            // Positional argument (file path)
            positional_count += 1;
            switch (positional_count) {
                1 => {
                    input_path = try allocator.dupe(u8, arg);
                },
                2 => {
                    output_path = try allocator.dupe(u8, arg);
                },
                else => {
                    usage("Too many arguments.");
                },
            }
        }
    }

    if (list_target_versions)
    {
        if (input_path)
            |path|
        {
            allocator.free(path);
        }
        if (output_path)
            |path|
        {
            allocator.free(path);
        }
        return .{
            .input_path = try allocator.dupe(u8, ""),
            .output_path = null,
            .list_target_versions = true,
        };
    }

    if (positional_count < 1)
    {
        usage("Not enough arguments.");
    }

    return .{
        .input_path = input_path.?,
        .output_path = output_path,
        .metadata_mode = metadata_mode,
        .bundle_format = bundle_format,
        .media_policy = media_policy,
        .maybe_target_version = maybe_target_version,
    };
}

/// Usage message for argument parsing
pub fn usage(
    msg: []const u8,
) noreturn
{
    std.debug.print(
        \\
        \\otiocat - Universal timeline/collection format converter
        \\
        \\Reads timeline and collection files and converts them to other formats.
        \\
        \\Supported timeline formats:
        \\  .otio   OpenTimelineIO JSON format (input only)
        \\  .tla    TLA (Timeline ASCII) text format
        \\  .tlb    Binary FlatBuffers format
        \\  .tlz    TLZ bundle (ZIP archive with timeline + media)
        \\
        \\Supported collection formats:
        \\  .tlca   TLCA (Timeline Collection ASCII) text format
        \\  .tlcb   TLCB (Timeline Collection Binary) FlatBuffers format
        \\
        \\Usage:
        \\  otiocat [options] <input> [output]
        \\
        \\Arguments:
        \\  <input>   Path to the source file
        \\  [output]  Path for the converted output file (optional)
        \\            If omitted, prints TLA/TLCA format to stdout.
        \\
        \\Options:
        \\  -h, --help            Print this message and exit
        \\  -m, --inline-metadata Print metadata inline on each clip instead of
        \\                        using hash references (TLA/TLCA output only)
        \\  -M, --no-metadata     Omit all metadata from output
        \\  --target-version=N    Write schema version N instead of the current
        \\                        version (downgrades a copy of the data)
        \\  --list-target-versions  Print the schema versions that can be
        \\                        written, then exit
        \\
        \\TLZ Bundle Options (for .tlz output):
        \\  --bundle-format=tla     Use TLA text format inside bundle (default)
        \\  --bundle-format=tlb     Use FlatBuffers binary format inside bundle
        \\  --media-policy=error    Error if any media file not found
        \\  --media-policy=missing  Skip missing media files (default)
        \\  --media-policy=all-missing  Don't bundle any media files
        \\
        \\Timeline Examples:
        \\  otiocat timeline.otio                   # JSON to TLA (stdout)
        \\  otiocat timeline.otio timeline.tla      # JSON to TLA (file)
        \\  otiocat timeline.otio timeline.tlb      # JSON to FlatBuffers
        \\  otiocat timeline.tla timeline.tlb       # TLA to Binary
        \\  otiocat timeline.tlb timeline.tla       # Binary to TLA
        \\
        \\Collection Examples:
        \\  otiocat collection.tlca collection.tlcb # ASCII to FlatBuffers
        \\  otiocat collection.tlcb collection.tlca # FlatBuffers to ASCII
        \\
        \\TLZ Bundle Examples:
        \\  otiocat timeline.tla timeline.tlz       # Create TLZ bundle
        \\  otiocat timeline.tlz timeline.tla       # Extract from TLZ bundle
        \\  otiocat timeline.tla timeline.tlz --bundle-format=tlb  # Binary inside
        \\  otiocat timeline.tla timeline.tlz --media-policy=error  # Require media
        \\
        \\Version Examples:
        \\  otiocat --list-target-versions          # Writable schema versions
        \\  otiocat --target-version=1 in.tla out.tla  # Write version 1
        \\
        \\Metadata Options (TLA/TLCA output only):
        \\  otiocat -M timeline.otio              # No metadata in output
        \\  otiocat -m timeline.otio              # Metadata inline on clips
        \\
        \\{s}
        , .{msg}
    );
    std.process.exit(1);
}

/// Print the schema versions this build can write, per root type.
fn print_target_versions(
    io: std.Io,
) !void
{
    var out_file = std.Io.File.stdout();
    var buffer: [1024]u8 = undefined;
    var file_writer = out_file.writer(io, &buffer);
    const w = &file_writer.interface;

    const versioning = serialization.versioning;
    try w.print(
        "Current schema version: {d}\n" ++
        "Writable schema versions (--target-version=N):\n",
        .{versioning.CURRENT_SCHEMA_VERSION},
    );
    inline for (
        .{
            .{ "timelines   (.tla, .tlb, .tlz)", versioning.TIMELINE_WRITE_VERSIONS },
            .{ "collections (.tlca, .tlcb, .tlcz)", versioning.COLLECTION_WRITE_VERSIONS },
        }
    )
        |row|
    {
        try w.print("  {s}:", .{row[0]});
        for (row[1])
            |version|
        {
            try w.print(" {d}", .{version});
        }
        try w.writeByte('\n');
    }
    try w.flush();
}

pub fn main(
    init: std.process.Init,
) !void
{
    const io = init.io;

    // Use the debug allocator in debug builds, otherwise use smp
    const parent_allocator = if (builtin.mode == .debug) alloc: {
        var da = std.heap.DebugAllocator(.{}){};
        break :alloc da.allocator();
    } else std.heap.smp_allocator;

    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const state = try parse_args(allocator, init.minimal.args);
    defer state.deinit(allocator);

    if (state.list_target_versions)
    {
        try print_target_versions(io);
        return;
    }

    const prog = std.Progress.start(io, .{});
    defer prog.end();

    const parent_prog = prog.start("Converting timeline", 3);

    // Check input file exists
    const read_prog = parent_prog.start("Reading input file...", 0);

    var found = true;
    std.Io.Dir.cwd().access(
        io,
        state.input_path,
        .{},
    ) catch |e| switch (e) {
        error.FileNotFound => found = false,
        else => return e,
    };

    if (!found)
    {
        std.log.err(
            "File: {s} does not exist or is not accessible.",
            .{state.input_path}
        );
        std.process.exit(1);
    }

    const input_format = serialization.FileFormat.from_path(
        state.input_path,
    ) catch |err| {
        std.log.err(
            "Unsupported input file {s}: {t}",
            .{ state.input_path, err },
        );
        std.process.exit(1);
    };
    const is_collection = serialization.descriptor(input_format).is_collection;

    // Writing to stdout defaults to the text format for the input's root type
    const output_format: serialization.FileFormat = (
        if (state.output_path)
            |path|
            serialization.FileFormat.from_path(path) catch |err| {
                std.log.err(
                    "Unsupported output file {s}: {t}",
                    .{ path, err },
                );
                std.process.exit(1);
            }
        else if (is_collection) .tlca else .tla
    );
    const output_desc = serialization.descriptor(output_format);

    if (is_collection != output_desc.is_collection) {
        std.log.err(
            "Cannot convert between timeline and collection formats. " ++
            "Use timeline formats (.tla, .tlb, .tlz) or collection formats (.tlca, .tlcb, .tlcz).",
            .{}
        );
        std.process.exit(1);
    }

    if (output_desc.is_read_only)
    {
        std.log.err("Cannot write .{t} files", .{ output_format });
        std.process.exit(1);
    }

    // Bundle output requires an output file (can't write to stdout)
    if (output_desc.is_bundle and state.output_path == null)
    {
        std.log.err("Bundle output requires an output file path", .{});
        std.process.exit(1);
    }

    if (state.maybe_target_version)
        |target|
    {
        const writable = (
            if (is_collection) serialization.versioning.COLLECTION_WRITE_VERSIONS
            else serialization.versioning.TIMELINE_WRITE_VERSIONS
        );
        if (std.mem.indexOfScalar(u32, writable, target) == null)
        {
            std.log.err(
                "Cannot write {s} schema version {d}; writable versions: {any}"
                ++ " (see --list-target-versions)",
                .{
                    if (is_collection) "collection" else "timeline",
                    target,
                    writable,
                },
            );
            std.process.exit(1);
        }
    }

    // Options for every file write.  When bundling, relative media URIs are
    // resolved against the input document's directory.
    const write_options: serialization.WriteOptions = .{
        .metadata_mode = state.metadata_mode,
        .target_version = state.maybe_target_version,
        .bundle_options = .{
            .content_format = state.bundle_format,
            .media_policy = state.media_policy,
            .media_base_dir = std.fs.path.dirname(state.input_path) orelse ".",
        },
    };

    // Every input format reads to the same serializable representation,
    // which preserves metadata hash maps through the conversion.
    var root = try serialization.serializable.read_from_file(
        allocator,
        io,
        state.input_path,
        .{
            .content_filter = (
                if (state.metadata_mode == .no_metadata) .all_except_metadata
                else .all
            ),
        },
    );
    defer root.deinit(allocator);

    read_prog.end();

    const convert_prog = parent_prog.start(
        if (is_collection) "Converting collection..." else "Converting timeline...",
        0,
    );

    if (state.output_path)
        |path|
    {
        try serialization.serializable.write_to_file(
            allocator,
            io,
            root,
            path,
            write_options,
        );
    }
    else
    {
        var out_file = std.Io.File.stdout();
        var file_writer_buffer: [16 * 1024]u8 = undefined;
        var file_writer = out_file.writer(io, &file_writer_buffer);
        const writer = &file_writer.interface;

        try serialization.serializable.write_to_writer(
            allocator,
            root,
            writer,
            output_format,
            write_options,
        );

        try writer.flush();
    }

    convert_prog.end();

    if (state.output_path) 
        |path|
    {
        std.log.info("Wrote: {s}", .{path});
    }
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "FileFormat stringToEnum parses extensions correctly" {
    // Test that we can parse all supported output formats
    try std.testing.expectEqual(
        serialization.FileFormat.tla,
        std.meta.stringToEnum(serialization.FileFormat, "tla"),
    );
    try std.testing.expectEqual(
        serialization.FileFormat.tlb,
        std.meta.stringToEnum(serialization.FileFormat, "tlb"),
    );
    try std.testing.expectEqual(
        serialization.FileFormat.tlz,
        std.meta.stringToEnum(serialization.FileFormat, "tlz"),
    );
    try std.testing.expectEqual(
        serialization.FileFormat.otio,
        std.meta.stringToEnum(serialization.FileFormat, "otio"),
    );
}

/// Test helper: read `path`, write it to memory as `format`, read that back,
/// and check the timeline's name and child count survive.
fn expect_roundtrip_through(
    path: []const u8,
    format: serialization.FileFormat,
) !void
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var original = try serialization.serializable.read_from_file(
        allocator,
        io,
        path,
        .{},
    );
    defer original.deinit(allocator);

    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialization.serializable.write_to_writer(
        allocator,
        original,
        &buffer.writer,
        format,
        .{},
    );
    try std.testing.expect(buffer.written().len > 0);

    var reader: std.Io.Reader = .fixed(buffer.written());
    var roundtrip = try serialization.serializable.read_from_reader(
        allocator,
        &reader,
        format,
        .{},
    );
    defer roundtrip.deinit(allocator);

    try std.testing.expectEqualStrings(
        original.content.timeline.name,
        roundtrip.content.timeline.name,
    );
    try std.testing.expectEqual(
        original.content.timeline.children.len,
        roundtrip.content.timeline.children.len,
    );
}

test "otiocat: roundtrip tla through tla" {
    try expect_roundtrip_through("otio_sample_data/simple_cut.tla", .tla);
}

test "otiocat: roundtrip tla through tlb" {
    try expect_roundtrip_through("otio_sample_data/simple_cut.tla", .tlb);
}

test "otiocat: convert otio through tla" {
    try expect_roundtrip_through("otio_sample_data/simple_cut.otio", .tla);
}
