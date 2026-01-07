//! otiocat - Universal timeline/collection format converter
//!
//! Reads timeline files (.otio, .tla, .tlb, .tlfb, .tlz) and writes to various formats.
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
//!   otiocat timeline.otio timeline.tlb      # JSON to Binary (CBOR)
//!   otiocat timeline.otio timeline.tlfb     # JSON to Binary (FlatBuffers)
//!   otiocat timeline.tla timeline.tlz       # TLA to TLZ bundle
//!   otiocat timeline.tlz timeline.tla       # TLZ bundle to TLA
//!   otiocat timeline.tla timeline.tlb       # TLA to Binary
//!   otiocat timeline.tlb timeline.tla       # Binary to TLA
//!   otiocat timeline.tlfb timeline.tla      # FlatBuffers to TLA
//!
//!   # Collection conversions
//!   otiocat collection.tlca collection.tlcb # ASCII to FlatBuffers
//!   otiocat collection.tlcb collection.tlca # FlatBuffers to ASCII

const std = @import("std");
const string = @import("string_stuff");
const otio = @import("opentimelineio");
const serialization = otio.serialization;
const tlz_bundle_utils = otio.tlz_bundle_utils;

const builtin = @import("builtin");

/// Re-export MetadataMode from serialization for argument parsing
const MetadataMode = serialization.MetadataMode;

const State = struct {
    input_path: []const u8,
    output_path: ?[]const u8,
    metadata_mode: MetadataMode = .hash_reference,

    // TLZ bundle options
    bundle_format: tlz_bundle_utils.BundleFormat = .tla,
    media_policy: tlz_bundle_utils.MediaReferencePolicy = .MissingIfNotFile,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.input_path);
        if (self.output_path) |path| allocator.free(path);
    }
};

/// Parse the commandline arguments and setup the state
fn parse_args(
    allocator: std.mem.Allocator,
) !State
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var metadata_mode: MetadataMode = .hash_reference;
    var bundle_format: tlz_bundle_utils.BundleFormat = .tla;
    var media_policy: tlz_bundle_utils.MediaReferencePolicy = .MissingIfNotFile;

    // Ignore the app name, always first in args
    _ = args.skip();

    var positional_count: usize = 0;

    // Read all the arguments from the commandline
    while (args.next())
        |nextarg|
    {
        const arg: [:0]const u8 = nextarg;

        // Handle options (flags starting with -)
        if (string.eql_latin_s8(arg, "--help") or
            string.eql_latin_s8(arg, "-h"))
        {
            usage("");
        }
        else if (string.eql_latin_s8(arg, "--no-metadata") or
            string.eql_latin_s8(arg, "-M"))
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
        else if (string.eql_latin_s8(arg, "--bundle-format=tlfb"))
        {
            bundle_format = .tlfb;
        }
        // TLZ media policy options
        else if (string.eql_latin_s8(arg, "--media-policy=error"))
        {
            media_policy = .ErrorIfNotFile;
        }
        else if (string.eql_latin_s8(arg, "--media-policy=missing"))
        {
            media_policy = .MissingIfNotFile;
        }
        else if (string.eql_latin_s8(arg, "--media-policy=all-missing"))
        {
            media_policy = .AllMissing;
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
        \\  .tlb    Binary CBOR format
        \\  .tlfb   Binary FlatBuffers format
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
        \\
        \\TLZ Bundle Options (for .tlz output):
        \\  --bundle-format=tla     Use TLA text format inside bundle (default)
        \\  --bundle-format=tlfb    Use FlatBuffers binary format inside bundle
        \\  --media-policy=error    Error if any media file not found
        \\  --media-policy=missing  Skip missing media files (default)
        \\  --media-policy=all-missing  Don't bundle any media files
        \\
        \\Timeline Examples:
        \\  otiocat timeline.otio                   # JSON to TLA (stdout)
        \\  otiocat timeline.otio timeline.tla      # JSON to TLA (file)
        \\  otiocat timeline.otio timeline.tlb      # JSON to Binary (CBOR)
        \\  otiocat timeline.otio timeline.tlfb     # JSON to FlatBuffers
        \\  otiocat timeline.tla timeline.tlb       # TLA to Binary
        \\  otiocat timeline.tlb timeline.tla       # Binary to TLA
        \\  otiocat timeline.tlfb timeline.tla      # FlatBuffers to TLA
        \\
        \\Collection Examples:
        \\  otiocat collection.tlca collection.tlcb # ASCII to FlatBuffers
        \\  otiocat collection.tlcb collection.tlca # FlatBuffers to ASCII
        \\
        \\TLZ Bundle Examples:
        \\  otiocat timeline.tla timeline.tlz       # Create TLZ bundle
        \\  otiocat timeline.tlz timeline.tla       # Extract from TLZ bundle
        \\  otiocat timeline.tla timeline.tlz --bundle-format=tlfb  # Binary inside
        \\  otiocat timeline.tla timeline.tlz --media-policy=error  # Require media
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

/// Get file extension from path
fn get_extension(
    path: []const u8,
) ?[]const u8
{
    const ext_start = std.mem.lastIndexOfScalar(u8, path, '.') orelse return null;
    return path[ext_start..];
}


pub fn main() !void
{
    // Use the debug allocator in debug builds, otherwise use smp
    const parent_allocator = if (builtin.mode == .Debug) alloc: {
        var da = std.heap.DebugAllocator(.{}){};
        break :alloc da.allocator();
    } else std.heap.smp_allocator;

    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const state = try parse_args(allocator);
    defer state.deinit(allocator);

    const prog = std.Progress.start(.{});
    defer prog.end();

    const parent_prog = prog.start("Converting timeline", 3);

    // Check input file exists
    const read_prog = parent_prog.start("Reading input file...", 0);

    var found = true;
    std.fs.cwd().access(state.input_path, .{}) catch |e| switch (e) {
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

    // Check input format to determine if this is a collection or timeline
    const input_ext = get_extension(state.input_path) orelse {
        std.log.err("Input file must have an extension", .{});
        std.process.exit(1);
    };

    const input_format = std.meta.stringToEnum(
        serialization.FileFormat,
        input_ext[1..],  // Skip the leading dot
    ) orelse {
        std.log.err(
            "Unsupported input format: {s}",
            .{input_ext}
        );
        std.process.exit(1);
    };

    const is_collection = input_format == .tlca or input_format == .tlcb;

    // Check output extension (default to .tla/.tlca for stdout based on input type)
    const default_output_ext = if (is_collection) ".tlca" else ".tla";
    const output_ext = if (state.output_path) |path|
        get_extension(path) orelse {
            std.log.err("Output file must have an extension", .{});
            std.process.exit(1);
        }
    else
        default_output_ext;

    const output_format = std.meta.stringToEnum(
        serialization.FileFormat,
        output_ext[1..],  // Skip the leading dot
    ) orelse {
        std.log.err(
            "Unsupported output format: {s}",
            .{output_ext}
        );
        std.process.exit(1);
    };

    // Validate format compatibility
    const output_is_collection = output_format == .tlca or output_format == .tlcb;
    if (is_collection != output_is_collection) {
        std.log.err(
            "Cannot convert between timeline and collection formats. " ++
            "Use timeline formats (.tla, .tlb, .tlfb, .tlz) or collection formats (.tlca, .tlcb).",
            .{}
        );
        std.process.exit(1);
    }

    // TLZ output requires an output file (can't write to stdout)
    if (output_format == .tlz and state.output_path == null)
    {
        std.log.err("TLZ output requires an output file path", .{});
        std.process.exit(1);
    }

    if (is_collection) {
        // Handle collection formats
        const ser_collection = try serialization.read_collection_from_file(allocator, state.input_path);

        read_prog.end();

        const convert_prog = parent_prog.start("Converting collection...", 0);

        // Build collection write options from state
        const collection_write_options = serialization.CollectionWriteOptions{
            .metadata_mode = state.metadata_mode,
        };

        // Write collection output
        if (state.output_path) |path|
        {
            try serialization.write_collection_to_file(allocator, ser_collection, path, collection_write_options);
        }
        else
        {
            // Write to stdout
            var out_file = std.fs.File.stdout();
            var file_writer_buffer: [16 * 1024]u8 = undefined;
            var file_writer = out_file.writer(&file_writer_buffer);
            const writer = &file_writer.interface;

            try serialization.write_collection_to_writer(
                allocator,
                ser_collection,
                output_format,
                collection_write_options,
                writer,
            );

            try writer.flush();
        }

        convert_prog.end();
    } else {
        // Handle timeline formats
        // Read input file using centralized reader (supports .otio, .tla, .tlb, .tlfb, .tlz)
        const ser_timeline = try serialization.read_from_file(allocator, state.input_path);

        read_prog.end();

        const convert_prog = parent_prog.start("Converting timeline...", 0);

        // Build write options from state
        const input_dir = std.fs.path.dirname(state.input_path) orelse ".";
        const write_options = serialization.WriteOptions{
            .metadata_mode = state.metadata_mode,
            .bundle_format = state.bundle_format,
            .media_policy = state.media_policy,
            .media_base_dir = input_dir,
        };

        // Write output using centralized writer
        if (state.output_path) |path|
        {
            // Write to file using centralized function
            try serialization.write_to_file(allocator, ser_timeline, path, write_options);
        }
        else
        {
            // Write to stdout
            var out_file = std.fs.File.stdout();
            var file_writer_buffer: [16 * 1024]u8 = undefined;
            var file_writer = out_file.writer(&file_writer_buffer);
            const writer = &file_writer.interface;

            try serialization.write_to_writer(
                allocator,
                ser_timeline,
                output_format,
                write_options,
                writer,
            );

            try writer.flush();
        }

        convert_prog.end();
    }

    if (state.output_path) |path|
    {
        std.log.info("Wrote: {s}", .{path});
    }
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "get_extension returns correct extension" {
    try std.testing.expectEqualStrings(".tla", get_extension("foo.tla").?);
    try std.testing.expectEqualStrings(".tlb", get_extension("path/to/file.tlb").?);
    try std.testing.expectEqualStrings(".tlfb", get_extension("timeline.tlfb").?);
    try std.testing.expectEqualStrings(".tlz", get_extension("/abs/path/bundle.tlz").?);
    try std.testing.expectEqualStrings(".otio", get_extension("test.otio").?);
    try std.testing.expect(get_extension("no_extension") == null);
}

test "FileFormat stringToEnum parses extensions correctly" {
    // Test that we can parse all supported output formats
    try std.testing.expectEqual(
        serialization.FileFormat.tla,
        std.meta.stringToEnum(serialization.FileFormat, "tla").?,
    );
    try std.testing.expectEqual(
        serialization.FileFormat.tlb,
        std.meta.stringToEnum(serialization.FileFormat, "tlb").?,
    );
    try std.testing.expectEqual(
        serialization.FileFormat.tlfb,
        std.meta.stringToEnum(serialization.FileFormat, "tlfb").?,
    );
    try std.testing.expectEqual(
        serialization.FileFormat.tlz,
        std.meta.stringToEnum(serialization.FileFormat, "tlz").?,
    );
    try std.testing.expectEqual(
        serialization.FileFormat.otio,
        std.meta.stringToEnum(serialization.FileFormat, "otio").?,
    );
}

test "roundtrip tla format via read_from_buffer and write_to_buffer" {
    const allocator = std.testing.allocator;

    // Read a test file
    const ser_timeline = try serialization.read_from_file(
        allocator,
        "otio_sample_data/simple_cut.tla",
    );

    // Write to buffer as tla
    const buffer = try serialization.write_to_buffer(
        allocator,
        ser_timeline,
        .tla,
        .{},
    );
    defer allocator.free(buffer);

    // Read back from buffer
    const roundtrip_timeline = try serialization.read_from_buffer(
        allocator,
        buffer,
        .tla,
    );

    // Verify basic structure matches
    try std.testing.expectEqualStrings(
        ser_timeline.name orelse "",
        roundtrip_timeline.name orelse "",
    );
    try std.testing.expectEqual(
        ser_timeline.tracks.children.len,
        roundtrip_timeline.tracks.children.len,
    );
}

test "roundtrip tlb format via read_from_buffer and write_to_buffer" {
    const allocator = std.testing.allocator;

    // Read a test file
    const ser_timeline = try serialization.read_from_file(
        allocator,
        "otio_sample_data/simple_cut.tla",
    );

    // Write to buffer as tlb (CBOR binary)
    const buffer = try serialization.write_to_buffer(
        allocator,
        ser_timeline,
        .tlb,
        .{},
    );
    defer allocator.free(buffer);

    // Read back from buffer
    const roundtrip_timeline = try serialization.read_from_buffer(
        allocator,
        buffer,
        .tlb,
    );

    // Verify basic structure matches
    try std.testing.expectEqualStrings(
        ser_timeline.name orelse "",
        roundtrip_timeline.name orelse "",
    );
    try std.testing.expectEqual(
        ser_timeline.tracks.children.len,
        roundtrip_timeline.tracks.children.len,
    );
}

test "roundtrip tlfb format via read_from_buffer and write_to_buffer" {
    const allocator = std.testing.allocator;

    // Read a test file
    const ser_timeline = try serialization.read_from_file(
        allocator,
        "otio_sample_data/simple_cut.tla",
    );

    // Write to buffer as tlfb (FlatBuffers binary)
    const buffer = try serialization.write_to_buffer(
        allocator,
        ser_timeline,
        .tlfb,
        .{},
    );
    defer allocator.free(buffer);

    // Read back from buffer
    const roundtrip_timeline = try serialization.read_from_buffer(
        allocator,
        buffer,
        .tlfb,
    );

    // Verify basic structure matches
    try std.testing.expectEqualStrings(
        ser_timeline.name orelse "",
        roundtrip_timeline.name orelse "",
    );
    try std.testing.expectEqual(
        ser_timeline.tracks.children.len,
        roundtrip_timeline.tracks.children.len,
    );
}

test "convert otio to tla via buffer" {
    const allocator = std.testing.allocator;

    // Read OTIO JSON file
    const ser_timeline = try serialization.read_from_file(
        allocator,
        "sample_otio_files/simple_cut.otio",
    );

    // Write to buffer as tla
    const buffer = try serialization.write_to_buffer(
        allocator,
        ser_timeline,
        .tla,
        .{},
    );
    defer allocator.free(buffer);

    // Verify we got some output
    try std.testing.expect(buffer.len > 0);

    // Read back and verify
    const roundtrip = try serialization.read_from_buffer(
        allocator,
        buffer,
        .tla,
    );

    try std.testing.expectEqual(
        ser_timeline.tracks.children.len,
        roundtrip.tracks.children.len,
    );
}
