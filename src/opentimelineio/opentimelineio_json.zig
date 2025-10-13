const std = @import("std");
const expectEqual = std.testing.expectEqual;

const otio  = @import("root.zig");
const opentime = @import("opentime");
const interval = opentime.interval;
const string = @import("string_stuff");

pub const SerializableObjectTypes = enum {
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
};

pub fn read_float(
    obj:std.json.Value
) opentime.Ordinate.BaseType 
{
    return switch (obj) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => 0,
    };
}

pub fn read_ordinate(
    obj:std.json.Value
) opentime.Ordinate 
{
    return switch (obj) {
        .integer => |i| opentime.Ordinate.init(i),
        .float => |f| opentime.Ordinate.init(f),
        else => opentime.Ordinate.ZERO,
    };
}

pub fn read_ordinate_from_rt(
    obj:?std.json.ObjectMap
) ?opentime.Ordinate 
{
    if (obj) 
        |o| 
        {
            const value = read_float(o.get("value").?);
            const rate = read_float(o.get("rate").?);

            return opentime.Ordinate.init(value / rate);
        } 
    else 
    {
        return null;
    }
}

fn read_rate(
    maybe_obj:?std.json.ObjectMap
) ?u32
{
    if (maybe_obj)
        |o|
        {
            if (o.get("rate")) |r| return @intFromFloat(read_float(r));
        }

    return null;
}

pub fn read_time_range(
    maybe_obj:?std.json.ObjectMap
) ?interval.ContinuousInterval 
{
    if (maybe_obj) 
        |o| 
        {
            const start_time = read_ordinate_from_rt(o.get("start_time").?.object).?;
            const duration = read_ordinate_from_rt(o.get("duration").?.object).?;
            return .{ 
                .start = start_time, 
                .end = start_time.add(duration)
            };
        } else {
            return null;
        }
}

pub fn _read_range(
    maybe_obj: ?std.json.ObjectMap
) ?interval.ContinuousInterval
{
    if (maybe_obj == null) {
        return null;
    }

    const obj = maybe_obj.?;

    // prefer source range
    if (obj.get("source_range")) 
        |sr| 
        {
            switch (sr) {
                .object => |o| return read_time_range(o),
                else => {},
            }
        }

    // otherwise, fetch the media reference and try available range
    if (obj.get("media_reference"))
        |mr|
        {
            switch (mr) {
                .object => |mr_o| 
                    if (mr_o.get("available_range")) 
                        |ar| 
                        {
                            switch (ar) {
                                .object => |o| return read_time_range(o),
                                else => return null,
                            }
                        },
                        else => return null,
            }
        }

    return null;
}

pub fn _read_rate(
    maybe_obj: ?std.json.ObjectMap
) ?u32
{
    if (maybe_obj == null) {
        return null;
    }

    const obj = maybe_obj.?;

    if (obj.get("source_range")) |sr| {
        switch (sr) {
            .object => |o| {
                if (o.get("start_time")) |st| {
                    switch (st){
                        .object => |sto| return read_rate(sto),
                        else => {},
                    }
                }
            },
            else => {},
        }
    } else if (obj.get("media_reference")) |mrv| 
    {
        switch (mrv) {
            .object => |mr| {
                if (mr.get("available_range")) |ar| {
                    switch (ar) {
                        .object => |o| {
                            if (o.get("start_time")) |st| {
                                switch (st){
                                    .object => |sto| return read_rate(sto),
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
            else =>{},
        }
    }

    return null;
}

inline fn read_children(
    allocator: std.mem.Allocator,
    children: std.json.Value,
) error{
    OutOfMemory,
    NotAnOtioSchemaObject,
    NoSuchSchema,
    MalformedSchemaString,
    NotImplemented,
}![]otio.ComposedValueRef
{
    const child_count = children.array.items.len;

    if (child_count == 0)
    {
        return &.{};
    }

    const new_children = try allocator.alloc(
        otio.ComposedValueRef,
        child_count,
    );

    for (children.array.items, new_children) 
        |track, *cvr| 
    {
        cvr.* = try read_otio_object(
            allocator,
            track.object,
        );
    }

    return new_children;
}

pub fn read_otio_object(
    allocator: std.mem.Allocator,
    obj:std.json.ObjectMap
) error{
    OutOfMemory,
    NoSuchSchema,
    NotAnOtioSchemaObject,
    MalformedSchemaString,
    NotImplemented,
} !otio.ComposedValueRef 
{
    const maybe_schema_and_version_str = obj.get("OTIO_SCHEMA");

    if (maybe_schema_and_version_str == null) {
        return error.NotAnOtioSchemaObject;
    }

    const full_string = maybe_schema_and_version_str.?.string;

    var split_schema_string = std.mem.splitSequence(
        u8,
        full_string,
        "."
    );

    const maybe_schema_str = split_schema_string.next();
    if (maybe_schema_str == null) {
        return error.MalformedSchemaString;
    }
    const schema_str = maybe_schema_str.?;

    const maybe_schema_enum = std.meta.stringToEnum(
        SerializableObjectTypes,
        schema_str
    );
    if (maybe_schema_enum == null) {
        errdefer std.log.err("No schema: {s}\n", .{schema_str});
        return error.NoSuchSchema;
    }

    const schema_enum = maybe_schema_enum.?;

    const maybe_name = if (obj.get("name")) |n| 
        switch (n) 
    {
        .string => |s| try allocator.dupe(u8, s),
        else => null
    } else null;

    switch (schema_enum) {
        .Timeline => { 
            const so_stack = (
                try read_otio_object(
                    allocator,
                    obj.get("tracks").?.object
                )
            );
            const st = otio.Stack{
                .name = so_stack.stack.name,
                .children = so_stack.stack.children,
            };
            const tl = try allocator.create(otio.Timeline);
            tl.* = .{
                .name = maybe_name,
                .tracks = st,
                .discrete_info = .{
                    .presentation = null,
                },
            };
            allocator.destroy(so_stack.stack);
            return .{ .timeline = tl };
        },
        .Stack => {
            // @TODO: add stack init that takes a name string and copies it in 
            var st = try allocator.create(otio.Stack);
            st.name = maybe_name;

            if (obj.get("children"))
                |children|
            {
                st.children = try read_children(
                    allocator,
                    children,
                );
            }

            return .{ .stack = st };
        },
        .Track => {
            var tr = try allocator.create(otio.Track);
            tr.name = maybe_name;

            if (obj.get("children"))
                |children|
            {
                const child_len = children.array.items.len;
                if (child_len > 0)
                {
                    tr.children = try read_children(
                        allocator,
                        children,
                    );
                }
            }

            return .{ .track = tr };
        },
        .Clip => {
            const range = _read_range(obj);

            const maybe_rate = _read_rate(obj);

            var cl = try allocator.create(otio.Clip);
            cl.* = .{
                .name = maybe_name,
                .bounds_s  = range,
            };

            // @TODO: read more of the media reference
            // @TODO: read metadata

            if (maybe_rate)
                |rate|
            {
                cl.media.discrete_info = .{
                    .sample_rate_hz = .{ .Int = rate },
                };
            }

            return .{ .clip = cl };
        },
        .Gap => {
            const source_range = _read_range(obj);
            const gp = try allocator.create(otio.Gap);
            gp.* = .{
                .name= maybe_name,
                .duration_seconds = source_range.?.duration(),
            };

            return .{ .gap = gp };
        },
        // else => { 
        //     errdefer std.log.err("Not implemented yet: {s}\n", .{ schema_str });
        //     return error.NotImplemented; 
        // }
    }

    return error.NotImplemented;
}

/// deserialize OTIO json to the in-memory structure
pub fn read_from_file(
    in_allocator: std.mem.Allocator,
    file_path: string.latin_s8
) !*otio.Timeline 
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    var arena = std.heap.ArenaAllocator.init(in_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32)
    );

    const result = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        source,
        .{}
    );

    const hopefully_timeline = try read_otio_object(
        in_allocator,
        result.object
    );

    if (hopefully_timeline == otio.ComposedValueRef.timeline) {
        return hopefully_timeline.timeline;
    }

    return error.NotImplemented;
}

test "read_from_file test (simple)" 
{
    const allocator = std.testing.allocator;

    const root = "simple_cut";
    const otio_fpath = root ++ ".otio";
    const dot_fpath = root ++ ".dot";

    var tl = try read_from_file(
        std.testing.allocator,
        "sample_otio_files/"++otio_fpath,
    );
    defer {
        tl.recursively_deinit(allocator);
        allocator.destroy(tl);
    }

    const track0 = tl.tracks.children[0].track;

    if (std.mem.eql(u8, root, "simple_cut"))
    {
        try expectEqual(@as(usize, 1), tl.tracks.children.len);

        try expectEqual(@as(usize, 4), track0.children.len);
        try std.testing.expectEqualStrings(
            "Clip-001",
            track0.children[0].clip.name.?
        );
    }

    const tl_ptr = otio.ComposedValueRef{
        .timeline = tl,
    };

    const target_clip_ptr = track0.children[0];

    const map = try otio.build_temporal_map(
        std.testing.allocator,
        tl_ptr
    );
    defer map.deinit(allocator);

    var cache: otio.temporal_hierarchy.OperatorCache = .empty;
    defer cache.deinit(allocator);

    const tl_output_to_clip_media = try otio.build_projection_operator(
        std.testing.allocator,
        map,
        .{
            .source = try tl_ptr.space(otio.SpaceLabel.presentation),
            .destination = try target_clip_ptr.space(otio.SpaceLabel.media),
        },
        &cache,
    );
    defer tl_output_to_clip_media.deinit(allocator);
    
    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/" ++ dot_fpath,
        "read_from_file_test",
        .{},
    );

    try opentime.expectOrdinateEqual(
        0.175,
        try tl_output_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(0.05),
        ).ordinate(),
    );
}

test "read_from_file test (multiple, smoke)" 
{
    const allocator = std.testing.allocator;

    const root = "multiple_track";
    const otio_fpath = root ++ ".otio";

    var tl = try read_from_file(
        std.testing.allocator,
        "sample_otio_files/"++otio_fpath,
    );
    defer {
        tl.recursively_deinit(allocator);
        allocator.destroy(tl);
    }
}
