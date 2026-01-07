//! otiocat - Universal timeline format converter
//!
//! Reads .otio (JSON), .ziggy, .tlb (CBOR binary), .tlfb (FlatBuffers binary),
//! or .tlz (ZIP bundle) files and writes to .ziggy, .tlb, .tlfb, or .tlz format
//! based on the output file extension.
//!
//! Usage:
//!   otiocat <input> [output]
//!
//! If no output file is specified, prints Ziggy format to stdout.
//!
//! Examples:
//!   otiocat timeline.otio                   # JSON to Ziggy (stdout)
//!   otiocat timeline.otio timeline.ziggy    # JSON to Ziggy (file)
//!   otiocat timeline.otio timeline.tlb      # JSON to Binary (CBOR)
//!   otiocat timeline.otio timeline.tlfb     # JSON to Binary (FlatBuffers)
//!   otiocat timeline.ziggy timeline.tlz     # Ziggy to TLZ bundle
//!   otiocat timeline.tlz timeline.ziggy     # TLZ bundle to Ziggy
//!   otiocat timeline.ziggy timeline.tlb     # Ziggy to Binary
//!   otiocat timeline.tlb timeline.ziggy     # Binary to Ziggy
//!   otiocat timeline.tlfb timeline.ziggy    # FlatBuffers to Ziggy

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
    bundle_format: tlz_bundle_utils.BundleFormat = .ziggy,
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
    var bundle_format: tlz_bundle_utils.BundleFormat = .ziggy;
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
        else if (string.eql_latin_s8(arg, "--no-metadata"))
        {
            metadata_mode = .no_metadata;
        }
        else if (string.eql_latin_s8(arg, "--inline-metadata"))
        {
            metadata_mode = .inline_metadata;
        }
        // TLZ bundle format options
        else if (string.eql_latin_s8(arg, "--bundle-format=ziggy"))
        {
            bundle_format = .ziggy;
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
        \\otiocat - Universal timeline format converter
        \\
        \\Reads timeline files in various formats and converts them to other formats.
        \\
        \\Supported input formats:
        \\  .otio   OpenTimelineIO JSON format
        \\  .ziggy  Ziggy text format
        \\  .tlb    Binary CBOR format
        \\  .tlfb   Binary FlatBuffers format
        \\  .tlz    TLZ bundle (ZIP archive with timeline + media)
        \\
        \\Supported output formats:
        \\  .ziggy  Ziggy text format
        \\  .tlb    Binary CBOR format
        \\  .tlfb   Binary FlatBuffers format
        \\  .tlz    TLZ bundle (ZIP archive with timeline + media)
        \\
        \\Usage:
        \\  otiocat [options] <input> [output]
        \\
        \\Arguments:
        \\  <input>   Path to the source timeline file
        \\  [output]  Path for the converted output file (optional)
        \\            If omitted, prints Ziggy format to stdout.
        \\
        \\Options:
        \\  -h, --help         Print this message and exit
        \\  --no-metadata      Omit all metadata from Ziggy output
        \\  --inline-metadata  Print metadata inline on each clip instead of
        \\                     using hash references (Ziggy output only)
        \\
        \\TLZ Bundle Options (for .tlz output):
        \\  --bundle-format=ziggy   Use Ziggy text format inside bundle (default)
        \\  --bundle-format=tlfb    Use FlatBuffers binary format inside bundle
        \\  --media-policy=error    Error if any media file not found
        \\  --media-policy=missing  Skip missing media files (default)
        \\  --media-policy=all-missing  Don't bundle any media files
        \\
        \\Examples:
        \\  otiocat timeline.otio                   # JSON to Ziggy (stdout)
        \\  otiocat timeline.otio timeline.ziggy    # JSON to Ziggy (file)
        \\  otiocat timeline.otio timeline.tlb      # JSON to Binary (CBOR)
        \\  otiocat timeline.otio timeline.tlfb     # JSON to FlatBuffers
        \\  otiocat timeline.ziggy timeline.tlb     # Ziggy to Binary
        \\  otiocat timeline.tlb timeline.ziggy     # Binary to Ziggy
        \\  otiocat timeline.tlfb timeline.ziggy    # FlatBuffers to Ziggy
        \\
        \\  # TLZ bundle examples:
        \\  otiocat timeline.ziggy timeline.tlz     # Create TLZ bundle
        \\  otiocat timeline.tlz timeline.ziggy     # Extract from TLZ bundle
        \\  otiocat timeline.ziggy timeline.tlz --bundle-format=tlfb  # Binary inside
        \\  otiocat timeline.ziggy timeline.tlz --media-policy=error  # Require media
        \\
        \\  # Metadata options (Ziggy output only):
        \\  otiocat --no-metadata timeline.otio     # No metadata in output
        \\  otiocat --inline-metadata timeline.otio # Metadata inline on clips
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

    // Check output extension (default to .ziggy for stdout)
    const output_ext = if (state.output_path) |path|
        get_extension(path) orelse {
            std.log.err("Output file must have an extension (.ziggy, .tlb, .tlfb, or .tlz)", .{});
            std.process.exit(1);
        }
    else
        ".ziggy";

    const output_format = std.meta.stringToEnum(
        serialization.FileFormat,
        output_ext[1..],  // Skip the leading dot
    ) orelse {
        std.log.err(
            "Unsupported output format: {s}. Use .ziggy, .tlb, .tlfb, or .tlz",
            .{output_ext}
        );
        std.process.exit(1);
    };

    // TLZ output requires an output file (can't write to stdout)
    if (output_format == .tlz and state.output_path == null)
    {
        std.log.err("TLZ output requires an output file path", .{});
        std.process.exit(1);
    }

    // Read input file using centralized reader (supports .otio, .ziggy, .tlb, .tlfb, .tlz)
    const ser_timeline = try serialization.read_from_file(allocator, state.input_path);

    read_prog.end();

    const convert_prog = parent_prog.start("Converting...", 0);

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
            output_ext,
            write_options,
            writer,
        );

        try writer.flush();
    }

    convert_prog.end();

    if (state.output_path) |path|
    {
        std.log.info("Wrote: {s}", .{path});
    }
}
