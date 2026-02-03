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

    pub fn from_string(
        str: []const u8,
    ) ?MarkerColor
    {
        return std.meta.stringToEnum(MarkerColor, str);
    }
};

/// A marked range of time on an Item with associated metadata.
pub const Marker = struct {
    /// Name for the marker.
    name: string.latin_s8 = "",

    /// The time range this marker spans, relative to the owning Item's
    /// presentation coordinate system.
    marked_range: opentime.ContinuousInterval,

    /// Visual color for the marker.
    color: MarkerColor = .red,

    /// Comment/note.
    comment: string.latin_s8 = "",

    /// Optional metadata as raw JSON value.
    maybe_metadata_json: ?std.json.Value = null,

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        allocator.free(self.comment);
    }
};

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "MarkerColor: string conversion round-trip"
{
    inline for (std.meta.fields(MarkerColor))
        |color_field|
    {
        const str = color_field.name;
        const parsed = MarkerColor.from_string(str);
        try std.testing.expect(parsed != null);
        try std.testing.expectEqual(@field(MarkerColor, color_field.name), parsed.?);
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
        MarkerColor.from_string("asdfasdf")
    );
    try std.testing.expectEqual(
        null,
        MarkerColor.from_string("")
    );
}

test "Marker: creation with default color"
{
    const marker = Marker{
        .marked_range = .init(
            .{ .start = 0, .end = 10 }
        ),
    };

    try std.testing.expectEqual(.red, marker.color);
    try std.testing.expectEqualStrings("", marker.name);
    try std.testing.expectEqualStrings("", marker.comment);
}

test "Marker: zero-duration point marker"
{
    const marker = Marker{
        .marked_range = .init(
            .{ .start = 10, .end = 10 }
        ),
        .color = .yellow,
    };

    try std.testing.expectEqual(.yellow, marker.color);
    try std.testing.expectEqual(10, marker.marked_range.start.as(f32));
    try std.testing.expectEqual(10, marker.marked_range.end.as(f32));

    // Zero-duration check
    const duration = marker.marked_range.duration();
    try std.testing.expectEqual(0, duration.as(f32));
}
