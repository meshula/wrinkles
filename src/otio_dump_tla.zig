const std = @import("std");

const ziggy = @import("ziggy");

const string = @import("string_stuff");
const otio = @import("opentimelineio");
const serialization = otio.serialization;

const builtin = @import("builtin");


const State = struct {
    input_otio: []const u8,
    output_ziggy: []const u8,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.input_otio);
        allocator.free(self.output_ziggy);
    }
};

/// parse the commandline arguments and setup the state
fn _parse_args(
    allocator: std.mem.Allocator,
) !State 
{
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var input_otio_fpath:[]const u8 = undefined;
    var output_ziggy_fpath:[]const u8 = undefined;

    // ignore the app name, always first in args
    _ = args.skip();

    var arg_count: usize = 0;

    // read all the filepaths from the commandline
    while (args.next()) 
        |nextarg| 
    {
        arg_count += 1;
        const fpath: [:0]const u8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        ) {
            usage("");
        }
        
        switch (arg_count) {
            1 => {
                input_otio_fpath = try allocator.dupe(u8, fpath);
            },
            2 => {
                output_ziggy_fpath = try allocator.dupe(u8, fpath);
            },
            else => {
                usage("Too many arguments.");
            },
        }
    }

    if (arg_count < 2) {
        usage("Not enough arguments.");
    }

    return .{
        .input_otio = input_otio_fpath,
        .output_ziggy = output_ziggy_fpath,
    };
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void
{
    std.debug.print(
        \\
        \\otio_dump_tla - Convert OTIO JSON files to TLA format
        \\
        \\Converts OpenTimelineIO files from the original JSON format (.otio)
        \\to wrinkles' native TLA serialization format (.tla).
        \\
        \\Usage:
        \\  otio_dump_tla <input.otio> <output.tla>
        \\
        \\Arguments:
        \\  <input.otio>    Path to the source OTIO JSON file
        \\  <output.tla>    Path for the converted TLA output file
        \\
        \\Options:
        \\  -h, --help      Print this message and exit
        \\
        \\{s}
        , .{msg}
    );
    std.process.exit(1);
}

pub fn main(
) !void
{
    // use the debug allocator in debug builds, otherwise use smp
    const parent_allocator = (
        if (builtin.mode == .Debug) alloc: {
            var da = std.heap.DebugAllocator(.{}){};
            break :alloc da.allocator();
        } else std.heap.smp_allocator
    );

    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const state = try _parse_args(allocator);
    defer state.deinit(allocator);

    const prog = std.Progress.start(.{});
    defer prog.end();

    const parent_prog = prog.start(
        "Converting to Ziggy",
        3,
    );

    const read_prog = parent_prog.start(
        "Reading input file...",
        0,
    );

    var found = true;
    std.fs.cwd().access(
        state.input_otio,
        .{},
    ) catch |e| switch (e) {
        error.FileNotFound => found = false,
        else => return e,
    };
    if (found == false)
    {
        std.log.err(
            "File: {s} does not exist or is not accessible.",
            .{ state.input_otio }
        );
    }

    // Read the file content
    const file = try std.fs.cwd().openFile(state.input_otio, .{});
    defer file.close();

    const json_source = try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(u32),
        null,
        .@"1",
        0,
    );
    defer allocator.free(json_source);

    read_prog.end();

    const build_tree = parent_prog.start(
        "Converting to ziggy...",
        0,
    );

    var out_file = try std.fs.cwd().createFile(
        state.output_ziggy,
        .{},
    );
    defer out_file.close();

    var file_writer_buffer: [16*1024]u8 = undefined;
    var file_writer = out_file.writer(&file_writer_buffer);
    const writer = &file_writer.interface;

    // Convert OTIO JSON directly to Ziggy, preserving metadata
    try serialization.convert_otio_json_to_ziggy(
        allocator,
        json_source,
        writer,
    );

    _ = try writer.write("\n");

    try writer.flush();

    build_tree.end();

    std.log.info("Wrote: {s}\n", .{ state.output_ziggy });
}
