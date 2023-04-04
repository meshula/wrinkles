const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");
const zstbi = @import("zstbi");

// curve library
const opentime = @import("opentime/opentime.zig");
const curve = opentime.curve;
const string = opentime.string;

const assert = std.debug.assert;

const build_options = @import("build_options");
const content_dir = build_options.otvis_content_dir;
const hash = build_options.hash;
const window_title = "zig-gamedev: wrinkles (wgpu)";

const wgsl_common = @embedFile("wrinkles_common.wgsl");
const wgsl_vs = wgsl_common ++ @embedFile("wrinkles_vs.wgsl");
const wgsl_fs = wgsl_common ++ @embedFile("blank_fs.wgsl");

const ALLOCATOR = @import("opentime/allocator.zig").ALLOCATOR;

// constants for indexing into the segment array
const PROJ_S:usize = 0;
const PROJ_THR_S:usize = 1;

fn _rescaledValue(
    t: f32,
    measure_min: f32, measure_max: f32,
    target_min: f32, target_max: f32
) f32
{
    return (
        (
         ((t - measure_min)/(measure_max - measure_min))
         * (target_max - target_min) 
        )
        + target_min
    );
}

fn _rescaledPoint(
    pt:curve.ControlPoint,
    extents: [2]curve.ControlPoint,
    target_range: [2]curve.ControlPoint,
) curve.ControlPoint
{
    return .{
        .time = _rescaledValue(
            pt.time, 
            extents[0].time, extents[1].time,
            target_range[0].time, target_range[1].time
        ),
        .value = _rescaledValue(
            pt.value,
            extents[0].value, extents[1].value,
            target_range[0].value, target_range[1].value
        ),
    };
}

// must match wrinkles_common
const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
};

const Uniforms = extern struct {
    aspect_ratio: f32,
    duration: f32,
    clip_frame_rate: f32,
    frame_rate: f32,
};

const CurveOpts = struct {
    name:string.latin_s8,
    draw_hull:bool = true,
    draw_curve:bool = true,
    draw_imgui_curve:bool = false,
};

fn arrayListInit(comptime T: type) std.ArrayList(T) {
    return std.ArrayList(T).init(ALLOCATOR);
}

fn curveName(state: *DemoState, index: usize) string.latin_s8 {
    return state.curve_options.items[index].name;
}

const DemoState = struct {
    gctx: *zgpu.GraphicsContext,

    font_normal: zgui.Font,
    font_large: zgui.Font,

    otvis_pipeline: zgpu.RenderPipelineHandle = .{},
    otvis_bind_group: zgpu.BindGroupHandle,

    otvis_vertex_buffer: zgpu.BufferHandle,
    otvis_index_buffer: zgpu.BufferHandle,

    // texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,
    otvis_sampler: zgpu.SamplerHandle,

    duration: f32 = 1.0,
    clip_frame_rate: i32 = 6,
    frame_rate: i32 = 10,

    /// original bezier curves read from json
    bezier_curves:std.ArrayList(curve.TimeCurve) = arrayListInit(curve.TimeCurve),
    /// list of curves normalized into the space of the display
    normalized_curves:std.ArrayList(curve.TimeCurve) = arrayListInit(curve.TimeCurve),
    /// list of linearized curves
    linear_curves:std.ArrayList(curve.TimeCurveLinear) = arrayListInit(curve.TimeCurveLinear),
    curve_options:std.ArrayList(CurveOpts) = arrayListInit(CurveOpts),

    options: struct {
        // using i32 because microui check_box expects an int32 not a bool
        animated_splits: i32 = 0, 
        linearize: i32 = 0,
        animated_u: i32 = 0,
        normalize_scale: i32 = 0,
        draw_knots: i32 = 0,
        dumped_segments: i32 = 0,
    } = .{},
};

fn init(allocator: std.mem.Allocator, window: zglfw.Window) !*DemoState {
    const gctx = try zgpu.GraphicsContext.create(allocator, window);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create a texture.
    zstbi.init(arena);
    defer zstbi.deinit();

    const font_path = content_dir ++ "genart_0025_5.png";

    var image = try zstbi.Image.init(font_path, 4);
    defer image.deinit();

    const texture = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{
            .width = image.width,
            .height = image.height,
            .depth_or_array_layers = 1,
        },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
    });
    const texture_view = gctx.createTextureView(texture, .{});

    gctx.queue.writeTexture(
        .{ .texture = gctx.lookupResource(texture).? },
        .{
            .bytes_per_row = image.bytes_per_row,
            .rows_per_image = image.height,
        },
        .{ .width = image.width, .height = image.height },
        u8,
        image.data,
    );

    zgui.init(allocator);
    zgui.plot.init();
    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor math.max(scale[0], scale[1]);
    };

    // const fira_font_path = content_dir ++ "FiraCode-Medium.ttf";
    const robota_font_path = content_dir ++ "Roboto-Medium.ttf";

    const font_size = 16.0 * scale_factor;
    const font_large = zgui.io.addFontFromFile(robota_font_path, font_size * 1.1);
    const font_normal = zgui.io.addFontFromFile(robota_font_path, font_size);
    assert(zgui.io.getFont(0) == font_large);
    assert(zgui.io.getFont(1) == font_normal);

    // This needs to be called *after* adding your custom fonts.
    zgui.backend.init(window, gctx.device, @enumToInt(zgpu.GraphicsContext.swapchain_format));

    // This call is optional. Initially, zgui.io.getFont(0) is a default font.
    zgui.io.setDefaultFont(font_normal);

    // You can directly manipulate zgui.Style *before* `newFrame()` call.
    // Once frame is started (after `newFrame()` call) you have to use
    // zgui.pushStyleColor*()/zgui.pushStyleVar*() functions.
    const style = zgui.getStyle();

    style.window_min_size = .{ 320.0, 240.0 };
    style.window_border_size = 8.0;
    style.scrollbar_size = 6.0;
    {
        var color = style.getColor(.scrollbar_grab);
        color[1] = 0.8;
        style.setColor(.scrollbar_grab, color);
    }
    style.scaleAllSizes(scale_factor);

    // To reset zgui.Style with default values:
    //zgui.getStyle().* = zgui.Style.init();

    {
        zgui.plot.getStyle().line_weight = 3.0;
        const plot_style = zgui.plot.getStyle();
        plot_style.marker = .circle;
        plot_style.marker_size = 5.0;
    }


    // tartan specific:
    // Create a vertex buffer.
    const vertex_data = [_]Vertex{
        .{ .position = [2]f32{ -0.9, 0.9 }, .uv = [2]f32{ 0.0, 0.0 } },
        .{ .position = [2]f32{ 0.9, 0.9 }, .uv = [2]f32{ 1.0, 0.0 } },
        .{ .position = [2]f32{ 0.9, -0.9 }, .uv = [2]f32{ 1.0, 1.0 } },
        .{ .position = [2]f32{ -0.9, -0.9 }, .uv = [2]f32{ 0.0, 1.0 } },
    };
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = vertex_data.len * @sizeOf(Vertex),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

    // Create an index buffer.
    const index_data = [_]u16{ 0, 1, 3, 1, 2, 3 };
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = index_data.len * @sizeOf(u16),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, u16, index_data[0..]);
 
    // Create a sampler.
    const sampler = gctx.createSampler(.{});

   const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
        zgpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
        zgpu.samplerEntry(2, .{ .fragment = true }, .filtering),
    });
    defer gctx.releaseResource(bind_group_layout);
    const bind_group = gctx.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{ .binding = 0, .buffer_handle = gctx.uniforms.buffer, .offset = 0, .size = 256 },
        .{ .binding = 1, .texture_view_handle = texture_view },
        .{ .binding = 2, .sampler_handle = sampler },
    });
    const demo = try allocator.create(DemoState);
    demo.* = .{
        .gctx = gctx,
        .texture_view = texture_view,
        .font_normal = font_normal,
        .font_large = font_large,
        .otvis_bind_group = bind_group,
        .otvis_vertex_buffer = vertex_buffer,
        .otvis_index_buffer = index_buffer,
        .otvis_sampler = sampler,
    };

    // (Async) Create the otvis render pipeline.
    {
        const pipeline_layout = gctx.createPipelineLayout(&.{
            bind_group_layout,
        });
        defer gctx.releaseResource(pipeline_layout);

        const vs_module = zgpu.createWgslShaderModule(gctx.device, wgsl_vs, "vs");
        defer vs_module.release();

        const fs_module = zgpu.createWgslShaderModule(gctx.device, wgsl_fs, "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]wgpu.VertexAttribute{
            .{ .format = .float32x2, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        };
        const vertex_buffers = [_]wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        // Create a render pipeline.
        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .back,
                .topology = .triangle_list,
            },
            .fragment = &wgpu.FragmentState{
                .module = fs_module,
                .entry_point = "main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };
        gctx.createRenderPipelineAsync(
            allocator,
            pipeline_layout,
            pipeline_descriptor,
            &demo.otvis_pipeline
        );
    }

    return demo;
}

fn deinit(allocator: std.mem.Allocator, demo: *DemoState) void {
    zgui.backend.deinit();
    zgui.plot.deinit();
    zgui.deinit();
    demo.gctx.destroy(allocator);
    allocator.destroy(demo);
}

fn update(demo: *DemoState) void {
    zgui.backend.newFrame(
        demo.gctx.swapchain_descriptor.width,
        demo.gctx.swapchain_descriptor.height,
    );

    zgui.setNextWindowPos(.{ .x = 20.0, .y = 120.0, .cond = .first_use_ever });
    zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

    if (!zgui.begin("Demo Settings", .{})) {
        zgui.end();
        return;
    }

    zgui.bulletText(
        "Average : {d:.3} ms/frame ({d:.1} fps)",
        .{ demo.gctx.stats.average_cpu_time, demo.gctx.stats.fps },
    );
    zgui.spacing();
    zgui.pushItemWidth(zgui.getWindowWidth() - 400);
    _ = zgui.sliderInt("clip framerate", .{
        .v = &demo.clip_frame_rate,
        .min = 1,
        .max = 60,
    });
    _ = zgui.sliderInt("presentation framerate", .{
        .v = &demo.frame_rate,
        .min = 1,
        .max = 60,
    });
    _ = zgui.sliderFloat("Duration", .{
        .v = &demo.duration,
        .min = 1.0 / 24.0,
        .max = 5,
    });
    zgui.popItemWidth();

    var times:std.ArrayList(f32) = (
        std.ArrayList(f32).init(ALLOCATOR)
    );
    defer times.deinit();
    var values:std.ArrayList(f32) = (
        std.ArrayList(f32).init(ALLOCATOR)
    );
    defer values.deinit();


    const viewport = zgui.getMainViewport();
    const vsz = viewport.getWorkSize();
    const center: [2]f32 = .{ vsz[0] * 0.5, vsz[1] * 0.5 };
    const half_width = center[1] * 0.9;
    const min_p = curve.ControlPoint{
        .time=center[0] + half_width,
        .value=center[1] + half_width,
    };
    const max_p = curve.ControlPoint{
        .time=center[0] - half_width,
        .value=center[1] - half_width,
    };

    const t_stops = 100;
    const t_start = min_p.time;
    const t_end = max_p.time;
    const t_inc = (t_end - t_start) / t_stops;
    var points_x = std.mem.zeroes([t_stops]f32);
    var points_y = std.mem.zeroes([t_stops]f32);

    if (zgui.collapsingHeader("Curves", .{})) {
        for (demo.normalized_curves.items) |crv, crv_index| {
            if (
                zgui.collapsingHeader(
                    @ptrCast([:0]const u8, curveName(demo, crv_index)),
                    .{}
                ) 
            )
            {
                var opts = &demo.curve_options.items[crv_index];
                _ = zgui.checkbox("Draw Hull", .{ .v = &opts.draw_hull },);
                _ = zgui.checkbox("Draw Curve", .{ .v = &opts.draw_curve },);
                _ = zgui.checkbox(
                    "Draw Curve With Imgui",
                    .{ .v = &opts.draw_imgui_curve },
                );

                const extents = crv.extents();
                const norm_crv = curve.normalized_to(
                    crv,
                    .{.time=-1, .value=-1},
                    .{.time=1, .value=1}
                );

                if (zgui.collapsingHeader("Points", .{})) {
                    if (zgui.collapsingHeader("Original Points", .{})) {
                        const orig_crv = demo.bezier_curves.items[crv_index];
                        for (orig_crv.segments) |seg| {
                            const pts = seg.points();
                            for (pts) |pt, pt_index| {
                                zgui.bulletText(
                                    "{d}: {{ {d:.6}, {d:.6} }}",
                                    .{ pt_index, pt.time, pt.value }
                                );
                            }
                        }
                    }
                    if (zgui.collapsingHeader("Normalized Hull Points", .{})) {
                        for (norm_crv.segments) |seg| {
                            const pts = seg.points();
                            for (pts) |pt, pt_index| {
                                zgui.bulletText(
                                    "{d}: {{ {d:.6}, {d:.6} }}",
                                    .{ pt_index, pt.time, pt.value }
                                );
                            }
                        }
                    }
                }

                if (zgui.plot.beginPlot("Curve Plot", .{ .h = -1.0 })) {
                    zgui.plot.setupAxis(
                        .x1,
                        .{ .label = "times", .flags = .{ .auto_fit = true } }
                    );
                    zgui.plot.setupAxisLimits(
                        .x1,
                        .{ .min = extents[0].time, .max = extents[1].time  }
                    );
                    zgui.plot.setupAxis(
                        .y1,
                        .{ .label = "values", .flags = .{ .auto_fit = true } }
                    );
                    zgui.plot.setupAxisLimits(
                        .y1,
                        .{ .min = extents[0].value, .max = extents[1].value  }
                    );
                    zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
                    zgui.plot.setupFinish();
                    // zgui.plot.plotLineValues("values", i32, .{ .v = &.{ 0, 1, 0, 1, 0, 1 } });
                    // state.curve_draw_switch.items[crv_index] = zgui.checkbox(
                    //     "enabled",
                    //     Checkbox{ enabled = state.curve_draw_switch.items[crv_index] },
                    // );
                    for (crv.segments) |seg| {
                        zgui.plot.plotLine(
                            "control hull",
                            f32,
                            .{
                                .xv = &.{ seg.p0.time, seg.p1.time, seg.p2.time, seg.p3.time },
                                .yv = &.{ seg.p0.value, seg.p1.value, seg.p2.value, seg.p3.value },
                            }
                        );
                    }
                    for (norm_crv.segments) |seg| {
                        zgui.plot.plotLine(
                            "normalized hull",
                            f32,
                            .{
                                .xv = &.{ seg.p0.time, seg.p1.time, seg.p2.time, seg.p3.time },
                                .yv = &.{ seg.p0.value, seg.p1.value, seg.p2.value, seg.p3.value },
                            }
                        );
                    }

                    const linearized_crv = crv.linearized();

                    times.clearAndFree();
                    values.clearAndFree();
                    for (linearized_crv.knots) |knot| {
                        times.append(knot.time) catch unreachable;
                        values.append(knot.value) catch unreachable;
                    }
                    zgui.plot.plotLine(
                        "linearized curve hull",
                        f32,
                        .{
                            .xv = times.items,
                            .yv = values.items,
                        }
                    );

                    const linearized_inverted_crv = curve.inverted_linear(
                        linearized_crv
                    );

                    times.clearAndFree();
                    values.clearAndFree();
                    for (linearized_inverted_crv.knots) |knot| {
                        times.append(knot.time) catch unreachable;
                        values.append(knot.value) catch unreachable;
                    }
                    zgui.plot.plotLine(
                        "inverted linear curve",
                        f32,
                        .{
                            .xv = times.items,
                            .yv = values.items,
                        }
                    );


                    var t = t_start;
                    var index:usize = 0;
                    while (t < t_end) : ({t += t_inc; index += 1;}) {
                        points_x[index] = t;
                        points_y[index] = crv.evaluate(t) catch unreachable;
                    }
                    zgui.plot.plotLine(
                        "evaluated curve",
                        f32,
                        .{
                            .xv = &points_x,
                            .yv = &points_y,
                        },
                    );

                    zgui.plot.endPlot();
                }
            }
        }
    }


    const draw_list = zgui.getWindowDrawList();

    // draw_list.pushClipRect(.{ .pmin = .{ 0, 0 }, .pmax = .{ 400, 400 } });
    // draw_list.addLine(.{ .p1 = .{ 0, 0 }, .p2 = .{ 400, 400 }, .col = 0xff_ff_00_ff, .thickness = 5.0 });
    // draw_list.popClipRect();

    draw_list.pushClipRectFullScreen();

    // outline the curve plot
    draw_list.addPolyline(
        &.{ 
            .{ center[0] - half_width, center[1] - half_width }, 
            .{ center[0] + half_width, center[1] - half_width }, 
            .{ center[0] + half_width, center[1] + half_width }, 
            .{ center[0] - half_width, center[1] + half_width }, 
            .{ center[0] - half_width, center[1] - half_width } 
        },
        .{ .col = 0xff_00_aa_aa, .thickness = 7 },
    );

    // for a debug origin
    // draw_list.addCircleFilled(.{ .p = .{ min_p.time, min_p.value }, .r = 50, .col = 0xff_00_00_ff });
    // draw_list.addCircleFilled(.{ .p = .{ max_p.time, max_p.value }, .r = 50, .col = 0xff_00_ff_ff });

    // var times:std.ArrayList(f32) = (
    //     std.ArrayList(f32).init(ALLOCATOR)
    // );
    // var values:std.ArrayList(f32) = (
    //     std.ArrayList(f32).init(ALLOCATOR)
    // );
    // for (demo.linear_curves.items) |crv| {
    //     for (linear_crv.knots) |knot| {
    //         times.append(knot.time) catch unreachable;
    //         values.append(knot.value) catch unreachable;
    //     }
    //     draw_list.addPolyline(
    //
    //     );
    // }

    // draw the curves themselves

    var pts:std.ArrayList([2]f32) = arrayListInit([2]f32);
    defer pts.deinit();

    for (demo.bezier_curves.items) |crv, index| {
        const draw_crv = curve.normalized_to(crv, min_p, max_p);
        const opts = &demo.curve_options.items[index];
        
        for (draw_crv.segments) |seg| {
            if (opts.draw_hull) {
                draw_list.addPolyline(
                    &.{ 
                        .{seg.p0.time, seg.p0.value},
                        .{seg.p1.time, seg.p1.value},
                        .{seg.p2.time, seg.p2.value},
                        .{seg.p3.time, seg.p3.value},
                    },
                    .{ .col=0xff_ff_ff_ff, .thickness = 3 },
                );
            }

            if (opts.draw_imgui_curve) {
                draw_list.addBezierCubic(
                    .{ 
                        .p1=.{seg.p0.time, seg.p0.value},
                        .p2=.{seg.p1.time, seg.p1.value},
                        .p3=.{seg.p2.time, seg.p2.value},
                        .p4=.{seg.p3.time, seg.p3.value},
                        .thickness = 6,
                        .col=0xff_ff_ff_ff,
                    }
                );
            }

            pts.clearAndFree();

            // draw curve with opentime evaluator
            if (opts.draw_curve) {
                var t = t_start;
                while (t < t_end) : ({t += t_inc;}) {
                    pts.append(
                        .{t, draw_crv.evaluate(t) catch unreachable}
                    ) catch unreachable;
                }
                draw_list.addPolyline(
                    pts.items,
                    .{ .col=0xff_ff_ff_ff, .thickness = 30 },
                );
            }
        }
    }

    // draw_list.addRectFilled(.{
    //     .pmin = .{ 100, 100 },
    //     .pmax = .{ 300, 200 },
    //     .col = 0xff_ff_ff_ff,
    //     .rounding = 25.0,
    // });
    // draw_list.addRectFilledMultiColor(.{
    //     .pmin = .{ 100, 300 },
    //     .pmax = .{ 200, 400 },
    //     .col_upr_left = 0xff_00_00_ff,
    //     .col_upr_right = 0xff_00_ff_00,
    //     .col_bot_right = 0xff_ff_00_00,
    //     .col_bot_left = 0xff_00_ff_ff,
    // });
    // draw_list.addQuadFilled(.{
    //     .p1 = .{ 150, 400 },
    //     .p2 = .{ 250, 400 },
    //     .p3 = .{ 200, 500 },
    //     .p4 = .{ 100, 500 },
    //     .col = 0xff_ff_ff_ff,
    // });
    // draw_list.addQuad(.{
    //     .p1 = .{ 170, 420 },
    //     .p2 = .{ 270, 420 },
    //     .p3 = .{ 220, 520 },
    //     .p4 = .{ 120, 520 },
    //     .col = 0xff_00_00_ff,
    //     .thickness = 3.0,
    // });
    // draw_list.addText(.{ 130, 130 }, 0xff_00_00_ff, "The number is: {}", .{7});
    // draw_list.addCircleFilled(.{ .p = .{ 200, 600 }, .r = 50, .col = 0xff_ff_ff_ff });
    // draw_list.addCircle(.{ .p = .{ 200, 600 }, .r = 30, .col = 0xff_00_00_ff, .thickness = 11 });

    // _ = draw_list.getClipRectMin();
    // _ = draw_list.getClipRectMax();
    draw_list.popClipRect();

    // if (zgui.plot.beginPlot("Line Plot", .{ .h = -1.0 })) {
    //     zgui.plot.setupAxis(.x1, .{ .label = "xaxis" });
    //     zgui.plot.setupAxisLimits(.x1, .{ .min = 0, .max = 5 });
    //     zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
    //     zgui.plot.setupFinish();
    //     zgui.plot.plotLineValues("y data", i32, .{ .v = &.{ 0, 1, 0, 1, 0, 1 } });
    //     zgui.plot.plotLine("xy data", f32, .{
    //         .xv = &.{ 0.1, 0.2, 0.5, 2.5 },
    //         .yv = &.{ 0.1, 0.3, 0.5, 0.9 },
    //     });
    //     zgui.plot.endPlot();
    // }

    zgui.end();
}

fn draw(demo: *DemoState) void {
    const gctx = demo.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        // Main pass.
        pass: {
            const vb_info = gctx.lookupResourceInfo(demo.otvis_vertex_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(demo.otvis_index_buffer) orelse break :pass;
            const pipeline = gctx.lookupResource(demo.otvis_pipeline) orelse break :pass;
            const bind_group = gctx.lookupResource(demo.otvis_bind_group) orelse break :pass;

            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
            pass.setIndexBuffer(ib_info.gpuobj.?, .uint16, 0, ib_info.size);

            pass.setPipeline(pipeline);

            const mem = gctx.uniformsAllocate(Uniforms, 1);
            mem.slice[0] = .{
                .aspect_ratio = @intToFloat(f32, fb_width) / @intToFloat(f32, fb_height),
                .duration = demo.duration,
                .clip_frame_rate = @intToFloat(f32, demo.clip_frame_rate),
                .frame_rate = @intToFloat(f32, demo.frame_rate),
            };
            pass.setBindGroup(0, bind_group, &.{mem.offset});
            pass.drawIndexed(6, 1, 0, 0, 0);
        }

        // Gui pass.
        {
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});
    _ = gctx.present();
}

fn _parse_args(state:*DemoState) !void {
    var args = try std.process.argsWithAllocator(ALLOCATOR);

    // ignore the app name, always first in args
    _ = args.skip();

    // inline for (std.meta.fields(@TypeOf(state))) |field| {
    //     std.debug.print("{s}: {}\n", .{ field.name, @field(state, field.name) });
    // }

    var project = false;
    var project_curves = false;

    // read all the filepaths from the commandline
    while (args.next()) |nextarg| 
    {
        var fpath: string.latin_s8 = nextarg;

        if (
            string.eql_latin_s8(fpath, "--help")
            or (string.eql_latin_s8(fpath, "-h"))
        ) {
            usage();
        }

        if (string.eql_latin_s8(fpath, "--project"))
        {
            if (project) {
                std.debug.print(
                    "Error: only one of {{--project, --project-bezier-curves}} is "
                    ++ "allowed\n",
                    .{}
                );
                usage();
            }

            project = true;
            continue;
        }

        if (string.eql_latin_s8(fpath, "--project-bezier-curves"))
        {
            if (project) {
                std.debug.print(
                    "Error: only one of {{--project, --project-bezier-curves}} is "
                    ++ "allowed\n",
                    .{}
                );
                usage();
            }

            project = true;
            project_curves = true;
            continue;
        }

        if (string.eql_latin_s8(fpath, "--split"))
        {
            state.options.animated_splits = 1;
            continue;
        }

        if (string.eql_latin_s8(fpath, "--hide-knots"))
        {
            state.options.draw_knots = 0;
            continue;
        }

        if (string.eql_latin_s8(fpath, "--normalize-scale"))
        {
            state.options.normalize_scale = 1;
            continue;
        }


        if (string.eql_latin_s8(fpath, "--animu"))
        {
            state.options.animated_u = 1;
            continue;
        }

        if (string.eql_latin_s8(fpath, "--linearize"))
        {
            state.options.linearize = 1;
            continue;
        }

        std.debug.print("reading curve: {s}\n", .{ fpath });
        try state.curve_options.append(.{.name=fpath});

        var buf: [1024]u8 = undefined;
        const lower_fpath = std.ascii.lowerString(&buf, fpath);
        if (std.mem.endsWith(u8, lower_fpath, ".curve.json")) {
            var crv = curve.read_curve_json(fpath) catch |err| {
                std.debug.print(
                    "Something went wrong reading: '{s}'\n",
                    .{ fpath }
                );
                return err;
            };

            try state.bezier_curves.append(crv);

            try state.normalized_curves.append(
                curve.normalized_to(
                    crv,
                    .{.time=0, .value=0}, 
                    .{.time=400, .value=400}
                )
            );
        } 
        else 
        {
            // pack into a curve
            try state.normalized_curves.append(
                curve.TimeCurve{ 
                    .segments = &[1]curve.Segment{
                        try curve.read_segment_json(fpath) 
                    }
                }
            );
        }
    }

    if (state.options.normalize_scale == 1) {
        const target_range: [2]curve.ControlPoint = .{
            .{ .time = -0.5, .value = -0.5 },
            .{ .time = 0.5, .value = 0.5 },
        };


        var extents: [2]curve.ControlPoint = .{
            // min
            .{ .time = std.math.inf(f32), .value = std.math.inf(f32) },
            // max
            .{ .time = -std.math.inf(f32), .value = -std.math.inf(f32) }
        };
        
        for (state.normalized_curves.items) |crv| {
            const crv_extents = crv.extents();
            extents = .{
                .{ 
                    .time = std.math.min(extents[0].time, crv_extents[0].time),
                    .value = std.math.min(extents[0].value, crv_extents[0].value),
                },
                .{ 
                    .time = std.math.max(extents[1].time, crv_extents[1].time),
                    .value = std.math.max(extents[1].value, crv_extents[1].value),
                },
            };
        }

        var rescaled_curves = std.ArrayList(curve.TimeCurve).init(ALLOCATOR);

        for (state.normalized_curves.items) |crv| {
            var segments = std.ArrayList(curve.Segment).init(ALLOCATOR);

            for (crv.segments) |seg| {
                const pts = seg.points();

                var new_pts:[4]curve.ControlPoint = pts;

                for (pts) |pt, index| {
                    new_pts[index] = _rescaledPoint(
                        pt,
                        extents,
                        target_range
                    );
                }

                var new_seg = curve.Segment.from_pt_array(new_pts);

                try segments.append(new_seg);
            }

            try rescaled_curves.append(.{ .segments = segments.items });
        }

        // empty and replace state.normalized_curves with rescaled segments
        state.normalized_curves.clearAndFree();
        try state.normalized_curves.appendSlice(rescaled_curves.items);
    }

    if (state.normalized_curves.items.len == 0) {
        usage();
    }

    if (project) {
        if (state.normalized_curves.items.len != 2) {
            std.debug.print(
                "Error: --project require exactly two "
                ++ "normalized_curves, got {}.",
                .{ state.normalized_curves.items.len }
            );
            usage();
        } else {
            std.debug.print(
                "Projecting {s} through {s} as normalized_curves\n",
                .{ curveName(state, PROJ_S), curveName(state, PROJ_THR_S) } 
            );

            const fst = state.normalized_curves.items[PROJ_THR_S];
            const snd = state.normalized_curves.items[PROJ_S];

            const result = fst.project_curve(snd);

            std.debug.print(
                "Final projected segments: {d}\n",
                .{result.len}
            );


            for (result) |crv, index| {
                const outpath = try std.fmt.allocPrint(
                    ALLOCATOR,
                    "/var/tmp/debug.projected.{}.curve.json",
                    .{ index },
                );
                std.debug.print(
                    "Writing debug json for projected result curve to: {s}\n",
                    .{ outpath }
                );
                curve.write_json_file_curve(crv, outpath) catch {
                    std.debug.print("Couldn't write to {s}\n", .{ outpath });
                };
            }

            try state.linear_curves.appendSlice(result);
        }
    }

    const title = "OTIO Bezier Curve Visualizer [" ++ hash[0..6] ++ "]";
    _ = title;
}

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("GLFW did not initialize properly.", .{});
        return;
    };
    defer zglfw.terminate();

    // zgpu.checkSystem(content_dir) catch {
    //     // In case of error zgpu.checkSystem() will print error message.
    //     return;
    // };

    zglfw.defaultWindowHints();
    zglfw.windowHint(.cocoa_retina_framebuffer, 1);
    zglfw.windowHint(.client_api, 0);
    const window = (
        zglfw.createWindow(1600, 1000, window_title, null, null) 
        catch {
            std.log.err("Could not create a window", .{});
            return;
        }
    );
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const demo = init(allocator, window) catch {
        std.log.err("Could not initialize resources", .{});
        return;
    };
    defer deinit(allocator, demo);

    try _parse_args(demo);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        update(demo);
        draw(demo);
    }
}

pub fn usage() void {
    std.debug.print(
        \\
        \\usage:
        \\  visualizer path/to/seg1.json [path/to/seg2.json] [...] [args]
        \\
        \\arguments:
        \\  --project: if two segments are provided, project the second through the first
        \\  --project-bezier-curves: if two segments are provided, promote both to TimeCurves and project the first through the second
        \\  --split: animate splitting the segment
        \\  --linearize: show the linearized segment
        \\  --animu: animate the u parameter for each spline
        \\  --normalize-scale: scale the segments so that they fit into [-0.5,0.5)
        \\  --hide-knots: don't draw curve knots
        \\  -h --help: print this message and exit
        \\
        \\
        , .{}
    );
    std.os.exit(1);
}
