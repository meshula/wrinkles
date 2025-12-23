const std = @import("std");

const string = @import("string_stuff");
const otio = @import("opentimelineio");

const builtin = @import("builtin");


const State = struct {
    input_otio: []const u8,
    output_png: []const u8,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.input_otio);
        allocator.free(self.output_png);
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
    var output_png_fpath:[]const u8 = undefined;

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
                output_png_fpath = try allocator.dupe(u8, fpath);
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
        .output_png = output_png_fpath,
    };
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void 
{
    std.debug.print(
        \\
        \\Render a graph of the temporal spaces in an OpenTimelineIO file.
        \\
        \\usage:
        \\  otio_dump_graph path/to/somefile.otio path/to/output.png
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
        "Dumping Graph",
        3,
    );

    const read_prog = parent_prog.start(
        "Reading file...",
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
    defer tl_ref.deinit(allocator);

    read_prog.end();

    const build_tree = parent_prog.start(
        "Building map",
        0,
    );

    // build the graph
    const tree = (
        try otio.temporal_tree.build_temporal_tree(
            allocator,
            tl_ref.space_node(.presentation),
        )
    );
    defer tree.deinit(allocator);

    build_tree.end();

    const write_dot_graph = parent_prog.start(
        "Writing Dot Graph...",
        0,
    );

    // render the graph to a PNG
    try tree.write_dot_graph(
        allocator,
        state.output_png,
        "OTIO_TemporalHierarchy",
        .{ .render_png = false },
    );

    write_dot_graph.end();

    std.debug.print("TREE NODES:", .{});

    for (tree.nodes.items(.item), tree.nodes.items(.space))
        |item, space|
    {
        std.debug.print("  {f}.{s}\n", .{item, @tagName(space)});
    }

    parent_prog.completeOne();

    std.log.info("Wrote: {s}\n", .{ state.output_png });
}
