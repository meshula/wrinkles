const std = @import("std");

const ziggy = @import("ziggy");

const string = @import("string_stuff");
const otio = @import("opentimelineio");

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
        \\Parse the .otio file into the wrinkles and serialize it as ziggy
        \\
        \\usage:
        \\  otio_dump_ziggy path/to/somefile.otio path/to/output.ziggy
        \\
        \\arguments:
        \\  -h --help: print this message and exit
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

    // read the file
    var tl_ref = try otio.read_from_file(
        allocator,
        state.input_otio,
    );
    defer tl_ref.recursively_deinit(allocator);

    read_prog.end();

    const build_tree = parent_prog.start(
        "Converting to ziggy...",
        0,
    );

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var file = try std.fs.createFileAbsolute(
        state.output_ziggy,
        .{},
    );
    defer file.close();

    var file_writer_buffer: [16*1024]u8 = undefined;
    var file_writer = file.writer(&file_writer_buffer);
    const writer = &file_writer.interface;

    try ziggy.stringify(
        tl_ref,
        .{.whitespace = .space_4},
        writer,
    );

    _ = try writer.write("\n");

    try writer.flush();

    build_tree.end();

    std.log.info("Wrote: {s}\n", .{ state.output_ziggy });
}
