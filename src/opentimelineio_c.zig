const std = @import("std");

const otio = @import("opentimelineio");

const c = @cImport(
    {
        @cInclude("opentimelineio_c.h");
    }
);

pub export fn test_fn(
) c_int
{
    return 4;
}

var raw = std.heap.GeneralPurposeAllocator(.{}){};
const ALLOCATOR:std.mem.Allocator = raw.allocator();

/// constant to represent an error (nullpointer)
const ERR_REF : c.ComposedValueRef_c = .{
    .kind = c.err,
    .ref = null 
};

pub export fn read_otio_timeline_from_file(
    filepath_c: [*c]u8,
) c.ComposedValueRef_c
{
    const filepath : []u8 = std.mem.span(filepath_c);
    const parsed_tl = otio.read_from_file(
        ALLOCATOR, 
        filepath,
    ) catch |err| {
        std.log.err(
            "couldn't read file: '{s}', error: {any}\n",
            .{filepath, err}
        );
        return ERR_REF;
    };

    const result = ALLOCATOR.create(otio.Timeline) catch {
        return ERR_REF;
    };

    result.* = parsed_tl;

    return .{ .kind = c.timeline, .ref = @as(*anyopaque, result) };
}

fn ptrCast(
    t: type,
    ptr: *anyopaque,
) *t
{
    return @as(*t, @ptrCast(@alignCast(ptr)));
}

fn init_ComposedValueRef(
    input: c.ComposedValueRef_c,
) !otio.ComposedValueRef
{
    if (input.ref)
        |ptr|
    {
        return switch (input.kind) {
            c.timeline => otio.ComposedValueRef.init(ptrCast(otio.Timeline, ptr)),
            c.stack => otio.ComposedValueRef.init(ptrCast(otio.Stack, ptr)),
            c.track => otio.ComposedValueRef.init(ptrCast(otio.Track, ptr)),
            c.clip =>  otio.ComposedValueRef.init(ptrCast(otio.Clip, ptr)),
            c.gap =>   otio.ComposedValueRef.init(ptrCast(otio.Gap, ptr)),
            c.warp =>  otio.ComposedValueRef.init(ptrCast(otio.Warp, ptr)),
            else => return error.ErrorReference,
        };
    }

    return error.ErrorReference;
}

pub fn to_c_ref(
    input: *otio.ComposedValueRef,
) c.ComposedValueRef_c
{
    return switch (input.*) {
        .timeline_ptr => |*t| .{ .kind = c.timeline, .ref = @ptrCast(t) },
        .stack_ptr => |*t| .{ .kind = c.stack, .ref = @ptrCast(t) },
        .track_ptr => |*t| .{ .kind = c.track, .ref = @ptrCast(t) },
        .clip_ptr =>  |*t| .{ .kind = c.clip, .ref = @ptrCast(t) },
        .gap_ptr =>   |*t| .{ .kind = c.gap, .ref = @ptrCast(t) },
        .warp_ptr =>  |*t| .{ .kind = c.warp, .ref = @ptrCast(t) },
    };
}

pub export fn get_child_count(
    input: c.ComposedValueRef_c,
) c_int
{
    const ref: otio.ComposedValueRef = init_ComposedValueRef(input) catch { 
        return -1;
    };

    return switch (ref) {
        .timeline_ptr => |*tl| @intCast(tl.*.tracks.children.items.len),
        inline .stack_ptr, .track_ptr => |*t|  @intCast(t.*.children.items.len),
        inline else => 0,
    };
}

pub export fn get_child_ref_by_index(
    input: c.ComposedValueRef_c,
    c_index: c_int,
) c.ComposedValueRef_c
{
    const ref: otio.ComposedValueRef = init_ComposedValueRef(input) catch { 
        return ERR_REF; 
    };

    const index: usize = @intCast(c_index);

    return switch (ref) {
        .timeline_ptr => |*tl| res: {
            var med = tl.*.tracks.child_ptr_from_index(index);
            break :res to_c_ref(&med);
        },
        inline .stack_ptr, .track_ptr => |*t|  res: {
            var med = t.*.child_ptr_from_index(index);
            break :res to_c_ref(&med);
        },
        inline else => return ERR_REF,
    };
}

pub export fn build_topological_map(
    timeline: c.ComposedValueRef_c,
) ?*anyopaque
{
    const ref = init_ComposedValueRef(
        timeline
    ) catch return null;

    const result = ALLOCATOR.create(
        otio.TopologicalMap
    ) catch return null;

    result.* = otio.build_topological_map(
        ALLOCATOR,
        ref,
    ) catch return null;

    return result;
}

