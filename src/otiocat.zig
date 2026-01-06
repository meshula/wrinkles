//! otiocat - Universal timeline format converter
//!
//! Reads .otio (JSON), .ziggy, .tlb (CBOR binary), or .tlfb (FlatBuffers binary)
//! files and writes to .ziggy, .tlb, or .tlfb format based on the output
//! file extension.
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
//!   otiocat timeline.ziggy timeline.tlb     # Ziggy to Binary
//!   otiocat timeline.tlb timeline.ziggy     # Binary to Ziggy
//!   otiocat timeline.tlfb timeline.ziggy    # FlatBuffers to Ziggy

const std = @import("std");
const string = @import("string_stuff");
const otio = @import("opentimelineio");
const serialization = otio.serialization;
const binary_serialization = otio.binary_serialization;
const binary_serialization_flatbufs = otio.binary_serialization_flatbufs;
const ziggy = @import("ziggy");

const builtin = @import("builtin");

const State = struct {
    input_path: []const u8,
    output_path: ?[]const u8,

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

    // Ignore the app name, always first in args
    _ = args.skip();

    var arg_count: usize = 0;

    // Read all the filepaths from the commandline
    while (args.next())
        |nextarg|
    {
        arg_count += 1;
        const fpath: [:0]const u8 = nextarg;

        if (string.eql_latin_s8(fpath, "--help") or
            string.eql_latin_s8(fpath, "-h"))
        {
            usage("");
        }

        switch (arg_count) {
            1 => {
                input_path = try allocator.dupe(u8, fpath);
            },
            2 => {
                output_path = try allocator.dupe(u8, fpath);
            },
            else => {
                usage("Too many arguments.");
            },
        }
    }

    if (arg_count < 1)
    {
        usage("Not enough arguments.");
    }

    return .{
        .input_path = input_path.?,
        .output_path = output_path,
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
        \\
        \\Supported output formats:
        \\  .ziggy  Ziggy text format
        \\  .tlb    Binary CBOR format
        \\  .tlfb   Binary FlatBuffers format
        \\
        \\Usage:
        \\  otiocat <input> [output]
        \\
        \\Arguments:
        \\  <input>   Path to the source timeline file
        \\  [output]  Path for the converted output file (optional)
        \\            If omitted, prints Ziggy format to stdout.
        \\
        \\Options:
        \\  -h, --help  Print this message and exit
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
            std.log.err("Output file must have an extension (.ziggy or .tlb)", .{});
            std.process.exit(1);
        }
    else
        ".ziggy";

    if (!std.mem.eql(u8, output_ext, ".ziggy") and
        !std.mem.eql(u8, output_ext, ".tlb") and
        !std.mem.eql(u8, output_ext, ".tlfb"))
    {
        std.log.err(
            "Unsupported output format: {s}. Use .ziggy, .tlb, or .tlfb",
            .{output_ext}
        );
        std.process.exit(1);
    }

    // Check input extension
    const input_ext = get_extension(state.input_path) orelse {
        std.log.err("Input file must have an extension", .{});
        std.process.exit(1);
    };

    // Read input file
    const file = try std.fs.cwd().openFile(state.input_path, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(u32),
        null,
        .@"1",
        0,
    );
    defer allocator.free(source);

    read_prog.end();

    const convert_prog = parent_prog.start("Converting...", 0);

    // Open output file or use stdout
    const writing_to_stdout = state.output_path == null;
    var out_file = if (state.output_path) |path|
        try std.fs.cwd().createFile(path, .{})
    else
        std.fs.File.stdout();
    defer if (!writing_to_stdout) out_file.close();

    var file_writer_buffer: [16 * 1024]u8 = undefined;
    var file_writer = out_file.writer(&file_writer_buffer);
    const writer = &file_writer.interface;

    // Handle conversion based on input and output formats
    // All conversions go through SerializableTimeline to preserve metadata
    if (std.mem.eql(u8, input_ext, ".otio"))
    {
        // OTIO JSON input - convert directly to output format
        if (std.mem.eql(u8, output_ext, ".ziggy"))
        {
            try serialization.convert_otio_json_to_ziggy(
                allocator,
                source,
                writer,
            );
            _ = try writer.write("\n");
        }
        else if (std.mem.eql(u8, output_ext, ".tlb"))
        {
            // Convert through SerializableTimeline to preserve metadata
            const ser_timeline = try serialization.otio_json_to_serializable_timeline(
                allocator,
                source,
            );

            try binary_serialization.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
        else if (std.mem.eql(u8, output_ext, ".tlfb"))
        {
            // OTIO JSON to FlatBuffers - convert through SerializableTimeline to preserve metadata
            const ser_timeline = try serialization.otio_json_to_serializable_timeline(
                allocator,
                source,
            );
            try binary_serialization_flatbufs.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
    }
    else if (std.mem.eql(u8, input_ext, ".ziggy"))
    {
        // Ziggy input - parse directly to SerializableTimeline to preserve metadata
        const ser_timeline = try ziggy.parseLeaky(
            serialization.SerializableTimeline,
            allocator,
            source,
            .{},
        );

        if (std.mem.eql(u8, output_ext, ".ziggy"))
        {
            // Ziggy to Ziggy (normalize/re-serialize)
            try ziggy.stringify(
                ser_timeline,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
            _ = try writer.write("\n");
        }
        else if (std.mem.eql(u8, output_ext, ".tlb"))
        {
            // Ziggy to Binary - preserves metadata
            try binary_serialization.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
        else if (std.mem.eql(u8, output_ext, ".tlfb"))
        {
            // Ziggy to FlatBuffers - preserves metadata
            try binary_serialization_flatbufs.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
    }
    else if (std.mem.eql(u8, input_ext, ".tlb"))
    {
        // Binary input - deserialize to SerializableTimeline to preserve metadata
        const ser_timeline = try binary_serialization.deserialize_to_serializable_timeline(
            allocator,
            source,
        );

        if (std.mem.eql(u8, output_ext, ".ziggy"))
        {
            // Binary to Ziggy - preserves metadata
            try ziggy.stringify(
                ser_timeline,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
            _ = try writer.write("\n");
        }
        else if (std.mem.eql(u8, output_ext, ".tlb"))
        {
            // Binary to Binary (normalize/re-serialize)
            try binary_serialization.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
        else if (std.mem.eql(u8, output_ext, ".tlfb"))
        {
            // CBOR Binary to FlatBuffers - preserves metadata
            try binary_serialization_flatbufs.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
    }
    else if (std.mem.eql(u8, input_ext, ".tlfb"))
    {
        // FlatBuffers input - deserialize to SerializableTimeline to preserve metadata
        const ser_timeline = try binary_serialization_flatbufs.deserialize_to_serializable_timeline(
            allocator,
            source,
        );

        if (std.mem.eql(u8, output_ext, ".ziggy"))
        {
            // FlatBuffers to Ziggy - preserves metadata
            try ziggy.stringify(
                ser_timeline,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
            _ = try writer.write("\n");
        }
        else if (std.mem.eql(u8, output_ext, ".tlb"))
        {
            // FlatBuffers to CBOR Binary - preserves metadata
            try binary_serialization.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
        else if (std.mem.eql(u8, output_ext, ".tlfb"))
        {
            // FlatBuffers to FlatBuffers (normalize/re-serialize with metadata)
            try binary_serialization_flatbufs.serialize_from_serializable_timeline(
                ser_timeline,
                allocator,
                writer,
            );
        }
    }
    else
    {
        std.log.err(
            "Unsupported input format: {s}. Use .otio, .ziggy, .tlb, or .tlfb",
            .{input_ext}
        );
        std.process.exit(1);
    }

    try writer.flush();

    convert_prog.end();

    if (state.output_path) |path|
    {
        std.log.info("Wrote: {s}", .{path});
    }
}
