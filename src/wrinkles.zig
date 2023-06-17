const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");
const zstbi = @import("zstbi");
const ot = @cImport({
    @cInclude("opentime.h");
});


const assert = std.debug.assert;

const content_dir = @import("build_options").wrinkles_content_dir;
const window_title = "zig-gamedev: wrinkles (wgpu)";

const wgsl_common = @embedFile("wrinkles_common.wgsl");
const wgsl_vs = wgsl_common ++ @embedFile("wrinkles_vs.wgsl");
const wgsl_fs = wgsl_common ++ @embedFile("wrinkles_fs.wgsl");

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

const DemoState = struct {
    gctx: *zgpu.GraphicsContext,

    font_normal: zgui.Font,
    font_large: zgui.Font,

    tartan_pipeline: zgpu.RenderPipelineHandle = .{},
    tartan_bind_group: zgpu.BindGroupHandle,

    tartan_vertex_buffer: zgpu.BufferHandle,
    tartan_index_buffer: zgpu.BufferHandle,

//    texture: zgpu.TextureHandle,
    texture_view: zgpu.TextureViewHandle,
    tartan_sampler: zgpu.SamplerHandle,

    duration: f32 = 1.0,
    clip_frame_rate: i32 = 6,
    frame_rate: i32 = 10,
};

fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !*DemoState {
    ot.ot_test();

    const gctx = try zgpu.GraphicsContext.create(allocator, window);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Create a texture.
    zstbi.init(arena);
    defer zstbi.deinit();
    var image = try zstbi.Image.loadFromFile(content_dir ++ "genart_0025_5.png", 4);
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
    const font_size = 16.0 * scale_factor;
    const roboto_fp = content_dir ++ "Roboto-Medium.ttf";
    const font_large = zgui.io.addFontFromFile(roboto_fp, font_size * 1.1);
    const font_normal = zgui.io.addFontFromFile(roboto_fp, font_size);
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
        .tartan_bind_group = bind_group,
        .tartan_vertex_buffer = vertex_buffer,
        .tartan_index_buffer = index_buffer,
        .tartan_sampler = sampler,
    };

    // (Async) Create the tartan render pipeline.
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
        gctx.createRenderPipelineAsync(allocator,
            pipeline_layout, pipeline_descriptor, &demo.tartan_pipeline);
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

    const viewport = zgui.getMainViewport();
    const vsz = viewport.getWorkSize();

    const center: [2]f32 = .{ vsz[0] * 0.5, vsz[1] * 0.5 };

    const draw_list = zgui.getWindowDrawList();

    // draw_list.pushClipRect(.{ .pmin = .{ 0, 0 }, .pmax = .{ 400, 400 } });
    // draw_list.addLine(.{ .p1 = .{ 0, 0 }, .p2 = .{ 400, 400 }, .col = 0xff_ff_00_ff, .thickness = 5.0 });
    // draw_list.popClipRect();

    draw_list.pushClipRectFullScreen();

    // outline the tartan plot
    draw_list.addPolyline(
        &.{ .{ center[0] - center[1] * 0.9, center[1] - center[1] * 0.9 }, 
            .{ center[0] + center[1] * 0.9, center[1] - center[1] * 0.9 }, 
            .{ center[0] + center[1] * 0.9, center[1] + center[1] * 0.9 }, 
            .{ center[0] - center[1] * 0.9, center[1] + center[1] * 0.9 }, 
            .{ center[0] - center[1] * 0.9, center[1] - center[1] * 0.9 } },
        .{ .col = 0xff_00_aa_aa, .thickness = 7 },
    );

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

    if (zgui.plot.beginPlot("Line Plot", .{ .h = -1.0 })) {
        zgui.plot.setupAxis(.x1, .{ .label = "xaxis" });
        zgui.plot.setupAxisLimits(.x1, .{ .min = 0, .max = 5 });
        zgui.plot.setupLegend(.{ .south = true, .west = true }, .{});
        zgui.plot.setupFinish();
        zgui.plot.plotLineValues("y data", i32, .{ .v = &.{ 0, 1, 0, 1, 0, 1 } });
        zgui.plot.plotLine("xy data", f32, .{
            .xv = &.{ 0.1, 0.2, 0.5, 2.5 },
            .yv = &.{ 0.1, 0.3, 0.5, 0.9 },
        });
        zgui.plot.endPlot();
    }

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
            const vb_info = gctx.lookupResourceInfo(demo.tartan_vertex_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(demo.tartan_index_buffer) orelse break :pass;
            const pipeline = gctx.lookupResource(demo.tartan_pipeline) orelse break :pass;
            const bind_group = gctx.lookupResource(demo.tartan_bind_group) orelse break :pass;

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

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("GLFW did not initialize properly.", .{});
        return;
    };
    defer zglfw.terminate();

    zglfw.WindowHint.set(.cocoa_retina_framebuffer, 1);
    zglfw.WindowHint.set(.client_api, 0);
    const window = zglfw.Window.create(1600, 1000, window_title, null) catch {
        std.log.err("Could not create a window", .{});
        return;
    };
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

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        update(demo);
        draw(demo);
    }
}

