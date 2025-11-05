//! example app using the app wrapper

const std = @import("std");
const builtin = @import("builtin");

const ziis = @import("zgui_cimgui_implot_sokol");
const zgui = ziis.zgui;
const zplot = zgui.plot;
const sg = ziis.sokol.gfx;
const app_wrapper = ziis.app_wrapper;

const cimgui = ziis.cimgui;

const otio = @import("opentimelineio");
const topology = @import("topology");

/// State container
const STATE = struct {
    // var f: f32 = 0;
    var demo_window_gui = false;
    var demo_window_plot = false;
    // const TEX_DIM : [2]i32 = .{ 256, 256 };
    // const COLOR_CHANNELS:usize = 4;
    // var tex: sg.Image = .{};
    // var view: sg.View = .{};
    // var texid: u64 = 0;
    // var frame_number: usize = 0;
    // var buffer = std.mem.zeroes(
    //     [STATE.TEX_DIM[0]][STATE.TEX_DIM[1]][COLOR_CHANNELS]u8
    // );
    // var image_data = ziis.sokol.gfx.ImageData{};

    var maybe_journal : ?ziis.undo.Journal = null;

    var allocator: std.mem.Allocator = undefined;
    var maybe_debug_allocator: ?std.heap.DebugAllocator(.{}) = null;

    var target_otio_file: []const u8 = undefined;
    var otio_root: otio.ComposedValueRef = undefined;
    var maybe_current_selected_object: ?otio.ComposedValueRef = null;
    var maybe_cached_topology: ?topology.Topology = null;
};

const IS_WASM = builtin.target.cpu.arch.isWasm();

fn label_for_ref(
    buf: []u8,
    ref: otio.ComposedValueRef,
) ![]const u8
{
    return try std.fmt.bufPrintZ(
        buf,
        "{s}.{?s}",
        .{ @tagName(ref), ref.name() }
    );

}

fn child_tree(
    allocator: std.mem.Allocator,
    children: []otio.ComposedValueRef,
) !void
{
    // if (zgui.isItemHovered(.{}))
    // {
    //     zgui.sameLine(.{});
    //     if (zgui.button("Source", .{}))
    //     {
    //     }
    //     zgui.sameLine(.{});
    //     if (zgui.button("Destination", .{}))
    //     {
    //     }
    // }

    if (children.len == 0)
    {
        return;
    }

    for (children, 0..)
        |child,ind|
    {
        var buf:[1024:0]u8 = undefined;

        const label = try std.fmt.bufPrintZ(
            buf[0..512],
            "{d}: {s}",
            .{ ind, try label_for_ref(buf[512..], child) }
        );

        const next_children = try child.children_refs(allocator);
        defer allocator.free(next_children);

        if (
            zgui.treeNodeFlags(
                label,
                .{
                    .bullet = next_children.len == 0,
                }
            )
        )
        {
            defer zgui.treePop();

            try child_tree(allocator, next_children);
        }

        if (zgui.isItemClicked(.left))
        {
            STATE.maybe_current_selected_object = child;

            if (STATE.maybe_cached_topology)
                |topo|
            {
                topo.deinit(allocator);
                STATE.maybe_cached_topology = null;
            }

            STATE.maybe_cached_topology = try child.topology(allocator);
            std.debug.print("clicked on: {s}\n", .{label});
        }
    }
}

/// draw the UI
fn draw(
) !void 
{
    const allocator = STATE.allocator;

    const vp = zgui.getMainViewport();
    const size = vp.getSize();

    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(
        .{ 
            .w = size[0],
            .h = size[1],
        },
    );

    if (
        zgui.begin(
            "###FULLSCREEN",
            .{ 
                .flags = .{
                    .no_resize = true, 
                    .no_scroll_with_mouse  = true, 
                    .always_auto_resize = true, 
                    .no_move = true,
                    .no_collapse = true,
                    .no_title_bar = true,
                },
            },
        )
    )
    {
        defer zgui.end();

        if (
            zgui.beginChild(
                "Object Info",
                .{
                    .w = -1,
                    .h = 180,
                }
            )
        )
        {
            defer zgui.endChild();

            var buf2:[1024]u8 = undefined;

            zgui.text(
                "Current Object: {s}",
                .{
                    if (STATE.maybe_current_selected_object) |obj| (
                        try label_for_ref(&buf2, obj)
                    ) else "[Click in the tree to select an object]"
                },
            );

            if (STATE.maybe_current_selected_object)
                |obj|
            {
                if (
                    zgui.beginTable(
                        "Object Details",
                        .{
                            .column = 2,
                        },
                    )
                )
                {
                    defer zgui.endTable();

                    // header row
                    zgui.tableNextRow(
                        .{ .row_flags = .{ .headers = true } }
                    );

                    _ = zgui.tableSetColumnIndex(0);
                    zgui.text("Key", .{});

                    _ = zgui.tableSetColumnIndex(1);
                    zgui.text("Value", .{});

                    zgui.tableNextRow(.{});

                    var buf3_s: [1024]u8 = undefined;
                    var buf3: []u8 = &buf3_s;

                    const pres_bounds = try std.fmt.bufPrint(
                        buf3,
                        "{f}",
                        .{ 
                            STATE.maybe_cached_topology.?.input_bounds(),
                        },
                    );
                    buf3 = buf3[pres_bounds.len..];

                    const pres_di = try std.fmt.bufPrint(
                        buf3,
                        "{?f}", 
                        .{ obj.discrete_info_for_space(.presentation) },
                    );
                    buf3 = buf3[pres_di.len..];

                    const rows = [_][2][]const u8{
                        .{ "Schema", @tagName(obj) },
                        .{ "Presentation Space Bounds", pres_bounds },
                        .{ "Presentation Space Discrete Info", pres_di },
                        .{ "Coordinate Spaces", "" },
                    };

                    for (&rows)
                        |row|
                    {
                        for (row, 0..)
                            |field, col|
                        {
                            _ = zgui.tableSetColumnIndex(@intCast(col));
                            zgui.text("{s}", .{ field });
                        }
                        zgui.tableNextRow(.{});
                    }

                    for (obj.spaces())
                        |space|
                    {
                        _ = zgui.tableSetColumnIndex(@intCast(0));
                        zgui.text("Space: {s}", .{@tagName(space)});

                        _ = zgui.tableSetColumnIndex(@intCast(1));

                        zgui.pushIntId(@intFromEnum(space));
                        defer zgui.popId();

                        _ = zgui.button("SET SOURCE", .{});
                        zgui.sameLine(.{});
                        _ = zgui.button("SET DEST", .{});

                        zgui.tableNextRow(.{});
                    }
                }
            }
        }

        if (zgui.beginChild("Object Tree", .{}))
        {
            defer zgui.endChild();

            zgui.text("Current File: {s}", .{ STATE.target_otio_file });

            var root = [_]otio.ComposedValueRef{
                STATE.otio_root,
            };

            try child_tree(allocator, &root );
        }




        // var new = STATE.f;
        // if (zgui.dragFloat("texture offset", .{.v = &new})) 
        // {
        //     const cmd = try ziis.undo.SetValue(f32).init(
        //             STATE.allocator,
        //             &STATE.f,
        //             new,
        //             "texture offset"
        //     );
        //     try cmd.do();
        //     try STATE.maybe_journal.?.update_if_new_or_add(cmd);
        // }
        //
        // for (STATE.maybe_journal.?.entries.items, 0..)
        //     |cmd, ind|
        // {
        //     zgui.bulletText("{d}: {s}", .{ ind, cmd.message });
        // }
        //
        // zgui.bulletText(
        //     "Head Entry in Journal: {?d}",
        //     .{ STATE.maybe_journal.?.maybe_head_entry }
        // );
        //
        // if (zgui.beginItemTooltip()) 
        // {
        //     zgui.text("Hi, this is a tooltip", .{});
        //     zgui.endTooltip();
        // }
        //
        // if (zgui.button("undo", .{}))
        // {
        //     try STATE.maybe_journal.?.undo();
        // }
        //
        // zgui.sameLine(.{});
        //
        // if (zgui.button("redo", .{}))
        // {
        //     try STATE.maybe_journal.?.redo();
        // }
        //
        // if (zgui.button("show gui demo", .{}) )
        // { 
        //     STATE.demo_window_gui = ! STATE.demo_window_gui; 
        // }
        // if (zgui.button("show plot demo", .{}))
        // {
        //     STATE.demo_window_gui = ! STATE.demo_window_plot; 
        // }
        //
        // if (STATE.demo_window_gui) 
        // {
        //     zgui.showDemoWindow(&STATE.demo_window_gui);
        // }
        // if (STATE.demo_window_plot) 
        // {
        //     zplot.showDemoWindow(&STATE.demo_window_plot);
        // }
        //
        // if (zgui.beginTabBar("Panes", .{}))
        // {
        //     defer zgui.endTabBar();
        //
        //     if (zgui.beginTabItem("PlotTab", .{}))
        //     {
        //         defer zgui.endTabItem();
        //
        //         if (
        //             zgui.beginChild(
        //                 "Plot", 
        //                 .{ .w = -1, .h = -1, },
        //             )
        //         )
        //         {
        //             defer zgui.endChild();
        //
        //             if (
        //                 zgui.plot.beginPlot(
        //                     "Test ZPlot Plot",
        //                     .{ 
        //                         .w = -1.0,
        //                         .h = -1.0,
        //                         .flags = .{ .equal = true },
        //                     },
        //                 )
        //             ) 
        //             {
        //                 defer zgui.plot.endPlot();
        //
        //                 zgui.plot.setupAxis(
        //                     .x1,
        //                     .{ .label = "input" },
        //                 );
        //                 zgui.plot.setupAxis(
        //                     .y1,
        //                     .{ .label = "output" },
        //                 );
        //                 zgui.plot.setupLegend(
        //                     .{ 
        //                         .south = true,
        //                         .west = true 
        //                     },
        //                     .{},
        //                 );
        //                 zgui.plot.setupFinish();
        //
        //                 const xs= [_]f32{0, 1, 2, 3, 4};
        //                 const ys= [_]f32{0, 1, 2, 3, 6};
        //
        //                 zplot.pushStyleColor4f(
        //                     .{
        //                         .idx = .fill,
        //                         .c = .{ 0.1, 0.1, 0.4, 0.4 },
        //                     },
        //                 );
        //                 zplot.plotShaded(
        //                     "test plot (shaded)",
        //                     f32, 
        //                     .{
        //                         .xv = &xs,
        //                         .yv = &ys,
        //                         .flags = .{
        //                         },
        //                     },
        //                 );
        //                 zplot.popStyleColor(.{.count = 1});
        //
        //                 zplot.plotLine(
        //                     "test plot",
        //                     f32, 
        //                     .{
        //                         .xv = &xs,
        //                         .yv = &ys,
        //                     },
        //                 );
        //             }
        //         }
        //     }
        //
        //     if (zgui.beginTabItem("Texture Example", .{}))
        //     {
        //         defer zgui.endTabItem();
        //
        //         const wsize = zgui.getWindowSize();
        //
        //         ziis.cimgui.igImage(
        //             .{ ._TexID = STATE.texid },
        //             .{ .x = wsize[0], .y = wsize[1]},
        //         );
        //     }
        // }
    }
}

fn cleanup (
) void
{
    if (STATE.maybe_journal)
        |*definitely_journal|
    {
        definitely_journal.deinit();
    }

    if (IS_WASM == false and builtin.mode == .Debug)
    {
        const result = STATE.maybe_debug_allocator.?.deinit();
        if (result == .leak) 
        {
            std.log.debug("leak!", .{});
        }
    }
}

pub fn init(
) void
{ 
    // STATE.tex = sg.makeImage(
    //     .{
    //         .width = STATE.TEX_DIM[0],
    //         .height = STATE.TEX_DIM[1],
    //         .usage = .{ .stream_update = true },
    //         .pixel_format = .RGBA8,
    //     },
    // );
    //
    // STATE.view = sg.makeView(
    //     .{
    //         .texture = .{
    //             .image = STATE.tex,
    //         },
    //     },
    // );
    //
    // STATE.texid = ziis.sokol.imgui.imtextureid(STATE.view);
}

pub fn main(
) !void 
{
    const prog = std.Progress.start(.{});
    defer prog.end();

    const parent_prog = prog.start(
        "Initializing",
        3,
    );

    {
        const init_progress = parent_prog.start(
            "Initializing State...",
            0,
        );
        defer init_progress.end();

        STATE.allocator = (
            if (builtin.mode == .Debug) alloc: {
                var da = std.heap.DebugAllocator(.{}){};
                STATE.maybe_debug_allocator = da;
                break :alloc da.allocator();
            } else std.heap.smp_allocator
        );

        STATE.maybe_journal = ziis.undo.Journal.init(
            STATE.allocator,
            5,
        ) catch null;
    }

    {
        const read_prog = parent_prog.start(
            "Reading file...",
            0,
        );
        defer read_prog.end();

        STATE.target_otio_file = (try _parse_args(STATE.allocator)).input_otio;
        var found = true;
        std.fs.cwd().access(
            STATE.target_otio_file,
            .{},
        ) catch |e| switch (e) {
            error.FileNotFound => found = false,
            else => return e,
        };
        if (found == false)
        {
            std.log.err(
                "File: {s} does not exist or is not accessible.",
                .{STATE.target_otio_file},
            );
        }
        STATE.otio_root = try otio.read_from_file(
            STATE.allocator,
            STATE.target_otio_file,
        );
    }

    parent_prog.end();

    app_wrapper.sokol_main(
        .{
            .title = "OTIO Space Visualizer",
            .draw = draw, 
            .maybe_pre_zgui_shutdown_cleanup = cleanup,
            .maybe_post_zgui_init = init,
        },
    );
}

/// Usage message for argument parsing.
pub fn usage(
    msg: []const u8,
) void 
{
    std.debug.print(
        \\
        \\Visualize the temporal spaces in an OpenTimelineIO file.
        \\
        \\usage:
        \\  otio_space_visualizer path/to/somefile.otio
        \\
        \\arguments:
        \\  -h --help: print this message and exit
        \\
        \\{s}
        \\
        , .{msg}
    );
    std.process.exit(1);
}

fn _parse_args(
    allocator: std.mem.Allocator,
) !struct { input_otio: []const u8, }
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
            std.mem.eql(u8, fpath, "--help")
            or std.mem.eql(u8, fpath, "-h")
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

    if (arg_count < 1) {
        usage("Not enough arguments.");
    }

    return .{
        .input_otio = input_otio_fpath,
    };
}
