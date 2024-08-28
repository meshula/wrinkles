const std = @import("std");

const otio = @import("opentimelineio");

const c = @cImport(
    {
        @cInclude("opentimelineio_c.h");
    }
);

var raw = std.heap.GeneralPurposeAllocator(.{}){};
const ALLOCATOR:std.mem.Allocator = raw.allocator();

/// constant to represent an error (nullpointer)
const ERR_REF : c.otio_ComposedValueRef = .{
    .kind = c.err,
    .ref = null 
};

pub export fn otio_read_from_file(
    filepath_c: [*c]u8,
) c.otio_ComposedValueRef
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
    input: c.otio_ComposedValueRef,
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
) c.otio_ComposedValueRef
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

pub export fn otio_child_count_cvr(
    input: c.otio_ComposedValueRef,
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

pub export fn otio_fetch_child_cvr_ind(
    input: c.otio_ComposedValueRef,
    c_index: c_int,
) c.otio_ComposedValueRef
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

const ERR_TOPO_MAP = c.otio_TopologicalMap{ .ref = null };

pub export fn otio_build_topo_map_cvr(
    timeline: c.otio_ComposedValueRef,
) c.otio_TopologicalMap
{
    const ref = init_ComposedValueRef(
        timeline
    ) catch return ERR_TOPO_MAP;

    const result = ALLOCATOR.create(
        otio.TopologicalMap
    ) catch return ERR_TOPO_MAP;

    result.* = otio.build_topological_map(
        ALLOCATOR,
        ref,
    ) catch return ERR_TOPO_MAP;

    return .{ .ref = result };
}

const ERR_PO_MAP = c.otio_ProjectionOperatorMap{ .ref = null };

pub export fn otio_build_projection_op_map_to_media_tp_cvr(
    in_map: c.otio_TopologicalMap,
    source: c.otio_ComposedValueRef,
) c.otio_ProjectionOperatorMap
{
    const map = in_map.ref;

    if (map == null) {
        return ERR_PO_MAP;
    }

    const t_map = ptrCast(otio.TopologicalMap, map.?);

    const result = ALLOCATOR.create(
        otio.ProjectionOperatorMap
    ) catch return ERR_PO_MAP;

    const src = init_ComposedValueRef(
        source
    ) catch return ERR_PO_MAP;

    result.* = otio.projection_map_to_media_from(
        ALLOCATOR,
        t_map.*,
        src.space(.presentation) catch return null,
    ) catch |err| {
        std.log.err("Couldn't build map: {any}\n", .{ err});
        return ERR_PO_MAP;
    };

    return .{ .ref = result };
}
