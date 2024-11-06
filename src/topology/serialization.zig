//! Implements the serialization system for OTIO

const std = @import("std");

// const opentime = @import("øpentime");
//
// const schema_to_type_map = std.StaticStringMap(std.Type);
//
// fn register_type(
//     comptime t: std.Type
// ) void
// {
//     schema_to_type_map.
// }
//
fn schema_of(
    source: anytype,
) ![]const u8
{
    const ti = @typeInfo(source);

    if (std.meta.activeTag(ti) != .Struct) {
        return error.NoSchemaForThing;
    }

    return @field(source, "OTIO_SCHEMA");
}

test "schema_of test"
{
    const t = struct {
        const OTIO_SCHEMA = "TestThing.1";
    };

    try std.testing.expectEqualStrings(
        t.OTIO_SCHEMA,
        try schema_of(t)
    );
}

/// convert the objects into a dictionary for serialization
fn to_map(
    allocator: std.mem.Allocator,
    source: anytype,
) !std.json.Value
{
    var raw_obj = try std.json.Value.jsonParse(
        allocator,
        source,
        .{}
    );

    try raw_obj.object.put("OTIO_SCHEMA", schema_of(source));

    return raw_obj;
}

pub fn to_string(
    allocator: std.mem.Allocator,
    thing: anytype,
) ![]const u8
{
    var str = std.ArrayList(u8).init(allocator);

    try std.json.stringify(
        thing,
        .{ .whitespace = .indent_2 },
        str.writer()
    ); 

    return str.toOwnedSlice();
}



