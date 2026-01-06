//! Marker definition and implementation for OTIO
//!
//! Markers represent marked ranges of time on Items with associated metadata.
//! Compatible with OpenTimelineIO 1.0 marker specification.

const std = @import("std");

const opentime = @import("opentime");
const string = @import("string_stuff");

/// Standard marker colors matching OTIO 1.0
pub const MarkerColor = enum {
    pink,
    red,
    orange,
    yellow,
    green,
    cyan,
    blue,
    purple,
    magenta,
    black,
    white,

    pub fn to_string(
        self: MarkerColor,
    ) []const u8
    {
        return switch (self) {
            .pink => "PINK",
            .red => "RED",
            .orange => "ORANGE",
            .yellow => "YELLOW",
            .green => "GREEN",
            .cyan => "CYAN",
            .blue => "BLUE",
            .purple => "PURPLE",
            .magenta => "MAGENTA",
            .black => "BLACK",
            .white => "WHITE",
        };
    }

    pub fn from_string(
        s: []const u8,
    ) ?MarkerColor
    {
        const map = std.StaticStringMap(MarkerColor).initComptime(.{
            .{ "PINK", .pink },
            .{ "RED", .red },
            .{ "ORANGE", .orange },
            .{ "YELLOW", .yellow },
            .{ "GREEN", .green },
            .{ "CYAN", .cyan },
            .{ "BLUE", .blue },
            .{ "PURPLE", .purple },
            .{ "MAGENTA", .magenta },
            .{ "BLACK", .black },
            .{ "WHITE", .white },
        });
        return map.get(s);
    }
};

/// A marked range of time on an Item with associated metadata.
pub const Marker = struct {
    /// Optional name for the marker.
    maybe_name: ?string.latin_s8 = null,

    /// The time range this marker spans, relative to the owning Item's
    /// presentation coordinate system.
    marked_range: opentime.ContinuousInterval,

    /// Visual color for the marker.
    color: MarkerColor = .red,

    /// Optional comment/note.
    maybe_comment: ?string.latin_s8 = null,

    /// Optional metadata as raw JSON value.
    maybe_metadata_json: ?std.json.Value = null,

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
        }
        if (self.maybe_comment)
            |c|
        {
            allocator.free(c);
        }
    }
};

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "MarkerColor: string conversion round-trip"
{
    const colors = [_]MarkerColor{
        .pink,
        .red,
        .orange,
        .yellow,
        .green,
        .cyan,
        .blue,
        .purple,
        .magenta,
        .black,
        .white,
    };

    for (colors)
        |color|
    {
        const str = color.to_string();
        const parsed = MarkerColor.from_string(str);
        try std.testing.expect(parsed != null);
        try std.testing.expectEqual(color, parsed.?);
    }
}

test "MarkerColor: invalid string returns null"
{
    try std.testing.expectEqual(
        null,
        MarkerColor.from_string("INVALID")
    );
    try std.testing.expectEqual(
        null,
        MarkerColor.from_string("red")
    );
    try std.testing.expectEqual(
        null,
        MarkerColor.from_string("")
    );
}

test "Marker: creation with default color"
{
    const marker = Marker{
        .marked_range = opentime.ContinuousInterval.init(
            .{ .start = 0, .end = 10 }
        ),
    };

    try std.testing.expectEqual(MarkerColor.red, marker.color);
    try std.testing.expectEqual(null, marker.maybe_name);
    try std.testing.expectEqual(null, marker.maybe_comment);
}

test "Marker: creation with custom properties"
{
    const allocator = std.testing.allocator;

    const name = try allocator.dupe(u8, "test marker");
    defer allocator.free(name);

    const comment = try allocator.dupe(u8, "this is a test");
    defer allocator.free(comment);

    var marker = Marker{
        .maybe_name = name,
        .marked_range = opentime.ContinuousInterval.init(
            .{ .start = 5.5, .end = 15.5 }
        ),
        .color = .green,
        .maybe_comment = comment,
    };

    try std.testing.expectEqualStrings("test marker", marker.maybe_name.?);
    try std.testing.expectEqual(MarkerColor.green, marker.color);
    try std.testing.expectEqualStrings("this is a test", marker.maybe_comment.?);
    try std.testing.expectEqual(5.5, marker.marked_range.start.as(f32));
    try std.testing.expectEqual(15.5, marker.marked_range.end.as(f32));

    // Don't call deinit since we're borrowing references that will be freed
    // by the defer statements above
    marker.maybe_name = null;
    marker.maybe_comment = null;
}

test "Marker: zero-duration point marker"
{
    const marker = Marker{
        .marked_range = opentime.ContinuousInterval.init(
            .{ .start = 10, .end = 10 }
        ),
        .color = .yellow,
    };

    try std.testing.expectEqual(MarkerColor.yellow, marker.color);
    try std.testing.expectEqual(10, marker.marked_range.start.as(f32));
    try std.testing.expectEqual(10, marker.marked_range.end.as(f32));

    // Zero-duration check
    const duration = marker.marked_range.duration();
    try std.testing.expectEqual(0, duration.as(f32));
}
