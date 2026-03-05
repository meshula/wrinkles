//! Reusable data-driven timeline / Gantt-chart renderer.
//!
//! The consumer provides track and item data each frame; this module
//! draws a scrollable timeline with a ruler, labelled track rows,
//! coloured item rectangles, and an optional cursor line.
//!
//! Only depends on `zgui_cimgui_implot_sokol` — no OTIO or other
//! domain-specific types.

const std = @import("std");
const zgui = @import("zgui_cimgui_implot_sokol").zgui;

// ─── Public types ──────────────────────────────────────────────────

/// A single rectangle on a track row.
pub const Item = struct {
    name: []const u8 = "",
    /// Seconds, relative to timeline start (0).
    start_time: f32,
    /// Seconds.
    duration: f32,
    /// Override fill colour (ABGR). `null` → track / default colour.
    maybe_color: ?u32 = null,
};

/// A horizontal track row.
pub const Track = struct {
    label: []const u8,
    items: []const Item,
    /// Override colour for all items in this track.
    maybe_color: ?u32 = null,
};

/// Mutable per-widget state.  The caller owns and persists this across
/// frames.
pub const State = struct {
    /// Pixels per second.
    scale: f32 = 100.0,
    track_height: f32 = 24.0,
    label_width: f32 = 120.0,
    /// Currently focused (selected) track, or null.
    maybe_focused_track: ?usize = null,
    /// Horizontal scroll offset in pixels (managed internally via
    /// ImGui child-window scrolling).
    scroll_x: f32 = 0.0,
};

/// Immutable per-frame input.
pub const FrameInput = struct {
    tracks: []const Track,
    /// Total time span in seconds.
    total_duration: f32,
    /// Optional cursor time (e.g. synced from another view).
    maybe_cursor_time: ?f32 = null,
};

/// Interaction results returned after drawing.
pub const FrameResult = struct {
    maybe_clicked_track: ?usize = null,
    maybe_clicked_item: ?HoveredItem = null,
    maybe_hovered: ?HoveredItem = null,
    /// Shift+click anywhere on the timeline content area: time in seconds.
    maybe_shift_clicked_time: ?f32 = null,
    /// Right-click on an item (for context menus).
    maybe_right_clicked_item: ?HoveredItem = null,
};

pub const HoveredItem = struct {
    track_idx: usize,
    item_idx: usize,
};

// ─── Colours (ABGR) ───────────────────────────────────────────────

const Colors = struct {
    const background: u32 = 0xFF141414;
    const track_label: u32 = 0xFF2A2A2A;
    const track_label_hover: u32 = 0xFF3A3A3A;
    const track_label_focused: u32 = 0xFF176B42;
    const item_fill: u32 = 0xFF355535;
    const item_hover: u32 = 0xFF456545;
    const item_focused: u32 = 0xFF176B42;
    const label_text: u32 = 0xFFF0F0F0;
    const cursor_line: u32 = 0xFFC8A020;
    const ruler_bg: u32 = 0xFF1A1A1A;
    const tick_major: u32 = 0xFF808080;
    const separator: u32 = 0xFF2A2A2A;
};

// ─── Coordinate helpers ────────────────────────────────────────────

fn time_to_pixel(
    time_s: f32,
    scale: f32,
) f32
{
    return time_s * scale;
}

fn pixel_to_time(
    pixel: f32,
    scale: f32,
) f32
{
    return pixel / scale;
}

// ─── Ruler formatting ──────────────────────────────────────────────

/// Adaptive duration label (seconds → m:ss → h:mm:ss).
fn format_ruler_label(
    buf: []u8,
    time_s: f32,
) []const u8
{
    const total: u32 = @intFromFloat(@max(0, @abs(time_s)));
    const hours = total / 3600;
    const minutes = (total % 3600) / 60;
    const seconds = total % 60;

    if (hours > 0)
    {
        return std.fmt.bufPrint(
            buf,
            "{d}:{d:0>2}:{d:0>2}",
            .{ hours, minutes, seconds },
        ) catch "??";
    }

    return std.fmt.bufPrint(
        buf,
        "{d}:{d:0>2}",
        .{ minutes, seconds },
    ) catch "??";
}

// ─── Internal drawing ──────────────────────────────────────────────

fn draw_ruler(
    draw_list: zgui.DrawList,
    origin: [2]f32,
    width: f32,
    height: f32,
    scale: f32,
    total_duration: f32,
) void
{
    // Background
    draw_list.addRectFilled(.{
        .pmin = origin,
        .pmax = .{ origin[0] + width, origin[1] + height },
        .col = Colors.ruler_bg,
    });

    // Adaptive tick interval
    const pps = scale;
    var tick: f32 = 1.0;

    // Scale up for zoomed-out views
    const intervals = [_]f32{ 2, 5, 10, 30, 60, 120, 300, 600, 1800, 3600 };
    const min_tick_px: f32 = 80.0;
    for (intervals)
        |iv|
    {
        if (pps * tick >= min_tick_px) break;
        tick = iv;
    }
    // Scale down for zoomed-in views
    if (pps * tick > min_tick_px * 6) tick = 0.5;
    if (pps * tick > min_tick_px * 6) tick = 0.25;

    var t: f32 = 0;
    while (t <= total_duration + tick) : (t += tick)
    {
        const x = origin[0] + time_to_pixel(t, scale);
        if (x < origin[0] or x > origin[0] + width) continue;

        draw_list.addLine(.{
            .p1 = .{ x, origin[1] + height * 0.6 },
            .p2 = .{ x, origin[1] + height },
            .col = Colors.tick_major,
            .thickness = 1.0,
        });

        var label_buf: [32]u8 = undefined;
        const label = format_ruler_label(&label_buf, t);
        draw_list.addText(
            .{ x + 3, origin[1] + 2 },
            Colors.label_text,
            "{s}",
            .{label},
        );
    }
}

fn draw_item_rect(
    draw_list: zgui.DrawList,
    p0: [2]f32,
    p1: [2]f32,
    fill: u32,
    name: []const u8,
) void
{
    const width = p1[0] - p0[0];
    if (width < 1) return;

    draw_list.addRectFilled(.{
        .pmin = p0,
        .pmax = p1,
        .col = fill,
        .rounding = 4.0,
        .flags = .{
            .round_corners_top_left = true,
            .round_corners_bottom_right = true,
        },
    });

    // Label if there is room
    if (name.len > 0 and width > 24)
    {
        draw_list.addText(
            .{ p0[0] + 4, p0[1] + 4 },
            Colors.label_text,
            "{s}",
            .{name},
        );
    }
}

fn draw_cursor_line(
    draw_list: zgui.DrawList,
    origin: [2]f32,
    height: f32,
    cursor_time: f32,
    scale: f32,
) void
{
    const x = origin[0] + time_to_pixel(cursor_time, scale);

    draw_list.addLine(.{
        .p1 = .{ x, origin[1] },
        .p2 = .{ x, origin[1] + height },
        .col = Colors.cursor_line,
        .thickness = 2.0,
    });

    // Small triangle at top
    const sz: f32 = 6.0;
    draw_list.addTriangleFilled(.{
        .p1 = .{ x - sz, origin[1] },
        .p2 = .{ x + sz, origin[1] },
        .p3 = .{ x, origin[1] + sz },
        .col = Colors.cursor_line,
    });
}

// ─── Main draw entry point ─────────────────────────────────────────

/// Draw the full timeline widget.
///
/// Call once per frame inside an ImGui window.  Manages its own
/// child window for horizontal scrolling.
pub fn draw(
    state: *State,
    input: FrameInput,
) FrameResult
{
    var result: FrameResult = .{};

    const track_count = input.tracks.len;
    if (track_count == 0) return result;

    const scale = state.scale;
    const th = state.track_height;
    const lw = state.label_width;
    const ruler_height = th;

    const avail = zgui.getContentRegionAvail();

    // Total pixel width of timeline content
    const content_px = @max(
        avail[0] - lw - 20,
        time_to_pixel(input.total_duration, scale),
    );

    // Total height: ruler + tracks
    const total_height = ruler_height +
        @as(f32, @floatFromInt(track_count)) * th;

    // Scrollable child window
    if (zgui.beginChild(
        "##tl_widget_scroll",
        .{
            .w = avail[0],
            .h = @min(total_height + 30, avail[1] - 30),
            .window_flags = .{ .horizontal_scrollbar = true },
        },
    ))
    {
        defer zgui.endChild();

        const win_pos = zgui.getCursorScreenPos();
        const draw_list = zgui.getWindowDrawList();

        // Background
        draw_list.addRectFilled(.{
            .pmin = win_pos,
            .pmax = .{
                win_pos[0] + lw + content_px,
                win_pos[1] + total_height,
            },
            .col = Colors.background,
        });

        // ── Ruler ──
        const ruler_origin: [2]f32 = .{
            win_pos[0] + lw,
            win_pos[1],
        };

        // Ruler label cell
        draw_list.addRectFilled(.{
            .pmin = win_pos,
            .pmax = .{
                win_pos[0] + lw,
                win_pos[1] + ruler_height,
            },
            .col = Colors.track_label,
        });

        draw_ruler(
            draw_list,
            ruler_origin,
            content_px,
            ruler_height,
            scale,
            input.total_duration,
        );

        // ── Track rows ──
        for (input.tracks, 0..)
            |track, track_idx|
        {
            const row_y = win_pos[1] + ruler_height +
                @as(f32, @floatFromInt(track_idx)) * th;

            // Label background
            const is_focused = (
                if (state.maybe_focused_track)
                    |fi|
                    fi == track_idx
                else
                    false
            );

            const label_p0: [2]f32 = .{ win_pos[0], row_y };
            const label_p1: [2]f32 = .{
                win_pos[0] + lw,
                row_y + th,
            };

            // Hit-test the label area
            const mouse = zgui.getMousePos();
            const label_hovered = (
                mouse[0] >= label_p0[0] and mouse[0] < label_p1[0] and
                mouse[1] >= label_p0[1] and mouse[1] < label_p1[1]
            );

            const label_bg = (
                if (is_focused) Colors.track_label_focused
                else if (label_hovered) Colors.track_label_hover
                else Colors.track_label
            );

            draw_list.addRectFilled(.{
                .pmin = label_p0,
                .pmax = label_p1,
                .col = label_bg,
            });

            draw_list.addText(
                .{ label_p0[0] + 5, label_p0[1] + 5 },
                Colors.label_text,
                "{s}",
                .{track.label},
            );

            // Label click → track focus toggle
            if (label_hovered and zgui.isMouseClicked(.left))
            {
                result.maybe_clicked_track = track_idx;
            }

            // Separator line under each track
            draw_list.addLine(.{
                .p1 = .{ win_pos[0], row_y + th },
                .p2 = .{ win_pos[0] + lw + content_px, row_y + th },
                .col = Colors.separator,
                .thickness = 1.0,
            });

            // ── Items ──
            const default_fill = track.maybe_color orelse Colors.item_fill;

            for (track.items, 0..)
                |item, item_idx|
            {
                if (item.duration <= 0) continue;

                const ix = win_pos[0] + lw +
                    time_to_pixel(item.start_time, scale);
                const iw = item.duration * scale;
                if (iw < 1) continue;

                const ip0: [2]f32 = .{ ix, row_y + 2 };
                const ip1: [2]f32 = .{ ix + iw, row_y + th - 2 };

                // Hit-test the item
                const item_hovered = (
                    mouse[0] >= ip0[0] and mouse[0] < ip1[0] and
                    mouse[1] >= ip0[1] and mouse[1] < ip1[1]
                );

                var fill = item.maybe_color orelse default_fill;
                if (item_hovered)
                {
                    fill = Colors.item_hover;
                    result.maybe_hovered = .{
                        .track_idx = track_idx,
                        .item_idx = item_idx,
                    };
                    if (zgui.isMouseClicked(.left))
                    {
                        result.maybe_clicked_item = .{
                            .track_idx = track_idx,
                            .item_idx = item_idx,
                        };
                    }
                    if (zgui.isMouseClicked(.right))
                    {
                        result.maybe_right_clicked_item = .{
                            .track_idx = track_idx,
                            .item_idx = item_idx,
                        };
                    }
                }
                if (is_focused)
                {
                    fill = item.maybe_color orelse
                        track.maybe_color orelse
                        Colors.item_focused;
                }

                draw_item_rect(draw_list, ip0, ip1, fill, item.name);

                // Tooltip
                if (item_hovered)
                {
                    zgui.setNextWindowPos(.{
                        .x = mouse[0] + 15,
                        .y = mouse[1] + 15,
                    });
                    if (zgui.beginTooltip())
                    {
                        defer zgui.endTooltip();
                        zgui.text("{s}", .{item.name});

                        var dur_buf: [32]u8 = undefined;
                        const dur_str = format_ruler_label(
                            &dur_buf,
                            item.duration,
                        );
                        zgui.text("Duration: {s}", .{dur_str});
                    }
                }
            }
        }

        // ── Shift+click anywhere on content area → report time ──
        {
            const mouse = zgui.getMousePos();
            const content_x0 = win_pos[0] + lw;
            const content_y0 = win_pos[1] + ruler_height;
            const content_y1 = win_pos[1] + total_height;
            const in_content = (
                mouse[0] >= content_x0
                and mouse[1] >= content_y0
                and mouse[1] < content_y1
            );
            if (
                in_content
                and zgui.isMouseClicked(.left)
                and (zgui.isKeyDown(.left_shift) or zgui.isKeyDown(.right_shift))
            )
            {
                const px = mouse[0] - content_x0;
                result.maybe_shift_clicked_time = pixel_to_time(px, scale);
            }
        }

        // ── Cursor line ──
        if (input.maybe_cursor_time)
            |ct|
        {
            draw_cursor_line(
                draw_list,
                ruler_origin,
                total_height,
                ct,
                scale,
            );
        }

        // Set dummy to enforce scroll region
        zgui.setCursorScreenPos(.{
            win_pos[0] + lw + content_px,
            win_pos[1] + total_height,
        });
        zgui.dummy(.{ .w = 1, .h = 1 });
    }

    // ── Zoom slider ──
    {
        zgui.setNextItemWidth(140);
        _ = zgui.sliderFloat(
            "##tl_zoom",
            .{
                .v = &state.scale,
                .min = 0.1,
                .max = 500.0,
                .cfmt = "Zoom: %.1f",
                .flags = .{ .logarithmic = true },
            },
        );

        zgui.sameLine(.{});
        if (zgui.button("Fit", .{}))
        {
            const vis_width = zgui.getContentRegionAvail()[0] - lw - 20;
            if (input.total_duration > 0)
            {
                state.scale = vis_width / input.total_duration;
            }
        }
    }

    return result;
}

// ─── Tests ─────────────────────────────────────────────────────────

test "timeline_widget: format_ruler_label seconds"
{
    var buf: [32]u8 = undefined;
    const label = format_ruler_label(&buf, 5.0);
    try std.testing.expectEqualStrings("0:05", label);
}

test "timeline_widget: format_ruler_label minutes"
{
    var buf: [32]u8 = undefined;
    const label = format_ruler_label(&buf, 125.0);
    try std.testing.expectEqualStrings("2:05", label);
}

test "timeline_widget: format_ruler_label hours"
{
    var buf: [32]u8 = undefined;
    const label = format_ruler_label(&buf, 3661.0);
    try std.testing.expectEqualStrings("1:01:01", label);
}

test "timeline_widget: time_to_pixel"
{
    try std.testing.expectApproxEqAbs(
        @as(f32, 200.0),
        time_to_pixel(2.0, 100.0),
        0.001,
    );
}

test "timeline_widget: pixel_to_time"
{
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0),
        pixel_to_time(200.0, 100.0),
        0.001,
    );
}
