const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const util = opentime.util;

const otio  = @import("opentimelineio.zig");
const opentime = @import("opentime");
const interval = opentime.interval;
const transform = opentime.transform;
const curve = @import("curve");
const string = @import("string_stuff");

pub const SerializableObjectTypes = enum {
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
};

pub const SerializableObject = union(SerializableObjectTypes) {
    Timeline:otio.Timeline,
    Stack:otio.Stack,
    Track:otio.Track,
    Clip:otio.Clip,
    Gap:otio.Gap,
};


pub fn read_float(
    obj:std.json.Value
) opentime.Ordinate 
{
    return switch (obj) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => 0,
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

            return @floatCast(value/rate);
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
                .start_ordinate = start_time, 
                .end_seconds = start_time + duration 
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

pub fn read_otio_object(
    allocator: std.mem.Allocator,
    obj:std.json.ObjectMap
) !SerializableObject 
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

    const name = if (obj.get("name")) 
        |n| 
        switch (n) 
    {
        .string => |s| s,
        else => ""
    } else "";

    switch (schema_enum) {
        .Timeline => { 
            const so_stack = (
                try read_otio_object(
                    allocator,
                    obj.get("tracks").?.object
                )
            );
            const st = otio.Stack{
                .name = so_stack.Stack.name,
                .children = so_stack.Stack.children,
            };
            const tl = otio.Timeline{
                .tracks = st,
                .discrete_info = .{
                    .presentation = null,
                },
            };
            return .{ .Timeline = tl };
        },
        .Stack => {
            var st = otio.Stack.init(allocator);
            st.name = try allocator.dupe(u8, name);

            for (obj.get("children").?.array.items) 
                |track| 
            {
                try st.children.append(
                    .{
                        .track = (
                            try read_otio_object(
                                allocator,
                                track.object
                            )
                        ).Track 
                    }
                );
            }

            return .{ .Stack = st };
        },
        .Track => {
            var tr = otio.Track.init(allocator);
            tr.name = try allocator.dupe(u8, name);

            for (obj.get("children").?.array.items) 
                |child| 
            {
                switch (
                    try read_otio_object(allocator, child.object)
                ) 
                {
                    .Clip => |cl| { try tr.children.append( .{ .clip = cl }); },
                    .Gap => |gp| { try tr.children.append( .{ .gap = gp }); },
                    else => return error.NotImplementedTrackChildJson,
                }
            }

            return .{ .Track = tr };
        },
        .Clip => {
            const range = _read_range(obj);

            const maybe_rate = _read_rate(obj);

            var cl = otio.Clip{
                .name=try allocator.dupe(u8, name),
                .media_temporal_bounds  = range,
            };

            if (maybe_rate)
                |rate|
            {
                cl.discrete_info.media = .{
                        .sample_rate_hz = rate,
                };
            }

            return .{ .Clip = cl };
        },
        .Gap => {
            const source_range = _read_range(obj);

            const gp = otio.Gap{
                .name=try allocator.dupe(u8, name),
                .duration_seconds = source_range.?.duration_seconds(),
            };

            return .{ .Gap = gp };
        },
        // else => { 
        //     errdefer std.log.err("Not implemented yet: {s}\n", .{ schema_str });
        //     return error.NotImplemented; 
        // }
    }

    return error.NotImplemented;
}

pub fn read_from_file(
    in_allocator: std.mem.Allocator,
    file_path: string.latin_s8
) !otio.Timeline 
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

    if (hopefully_timeline == SerializableObject.Timeline) {
        return hopefully_timeline.Timeline;
    }

    return error.NotImplemented;
}

test "read_from_file test" 
{
    const allocator = std.testing.allocator;

    const root = "simple_cut";
    const otio_fpath = root ++ ".otio";
    const dot_fpath = root ++ ".dot";

    const tl = try read_from_file(
        std.testing.allocator,
        "sample_otio_files/"++otio_fpath
    );
    defer tl.recursively_deinit();

    const track0 = tl.tracks.children.items[0].track;

    if (std.mem.eql(u8, root, "simple_cut"))
    {
        try expectEqual(@as(usize, 1), tl.tracks.children.items.len);

        try expectEqual(@as(usize, 4), track0.children.items.len);
        try std.testing.expectEqualStrings(
            "Clip-001",
            track0.children.items[0].clip.name.?
        );
    }

    const tl_ptr = otio.ComposedValueRef{ .timeline_ptr = &tl };
    const target_clip_ptr = (
        track0.child_ptr_from_index(0)
    );

    const map = try otio.build_topological_map(
        std.testing.allocator,
        tl_ptr
    );
    defer map.deinit();

    const tl_output_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
        .{
            .source = try tl_ptr.space(otio.SpaceLabel.presentation),
            .destination = try target_clip_ptr.space(otio.SpaceLabel.media),
        }
    );
    defer tl_output_to_clip_media.deinit(allocator);
    
    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/" ++ dot_fpath,
    );

    try expectApproxEqAbs(
        @as(opentime.Ordinate, 0.175),
        try tl_output_to_clip_media.project_instantaneous_cc(0.05).ordinate(),
        util.EPSILON
    );
}
