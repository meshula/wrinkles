const std = @import("std");

const opentime = @import("opentime");
const otio = @import("opentimelineio");
const topology = @import("topology");

const c = @import("opentimelineio_c");

var gpa = std.heap.DebugAllocator(.{}){};
const ALLOCATOR:std.mem.Allocator = gpa.allocator();

/// constant to represent an error (nullpointer)
const ERR_REF : c.otio_CompositionItemHandle = .{
    .kind = c.otio_ct_err,
    .ref = null 
};

const ERR_ALLOCATOR = c.otio_Allocator{
    .ref = null 
};
const ERR_ARENA = c.otio_Arena{
    .arena = null,
    .allocator = ERR_ALLOCATOR 
};
pub export fn otio_fetch_allocator_gpa() c.otio_Allocator
{
    return .{ .ref = @ptrCast(@constCast(&ALLOCATOR)) };
}
pub export fn otio_fetch_allocator_new_arena(
) c.otio_Arena
{
    // Use page_allocator to allocate the arena struct itself first.
    // This avoids the bug where we create an arena on the stack and then
    // try to copy it - the internal state becomes inconsistent.
    const page_alloc = std.heap.page_allocator;

    // Allocate the arena struct on the heap
    const arena_ptr = page_alloc.create(std.heap.ArenaAllocator) catch return ERR_ARENA;

    // Initialize the arena in-place on the heap
    arena_ptr.* = std.heap.ArenaAllocator.init(page_alloc);

    // Now get the allocator from the heap-allocated arena
    const allocator = arena_ptr.allocator();

    // Allocate the Allocator wrapper and vtable using the arena
    const alloc_ptr = allocator.create(std.mem.Allocator) catch return ERR_ARENA;
    const vtable = allocator.create(std.mem.Allocator.VTable) catch return ERR_ARENA;

    // Copy the vtable (these are function pointers to static code)
    vtable.* = allocator.vtable.*;

    // Build the allocator wrapper pointing to our heap-allocated arena
    alloc_ptr.* = .{
        .ptr = arena_ptr,
        .vtable = vtable,
    };

    return c.otio_Arena{
        .arena = arena_ptr,
        .allocator = .{ .ref = alloc_ptr },
    };
}
pub export fn otio_arena_deinit(
    ref_c: c.otio_Arena,
) void
{
    if (ref_c.arena == null)
    {
        return;
    }

    const ref = ptrCast(
        std.heap.ArenaAllocator,
        ref_c.arena.?
    );

    // First deinit the arena (frees all arena-allocated memory)
    ref.*.deinit();

    // Then free the arena struct itself (allocated with page_allocator)
    std.heap.page_allocator.destroy(ref);
}

pub export fn otio_read_from_file(
    allocator_c: c.otio_Allocator,
    filepath_c: [*:0]const u8,
) c.otio_CompositionItemHandle
{
    const filepath : []const u8 = std.mem.span(filepath_c);
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_REF;

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const result = otio.read_from_file(
        allocator,
        io,
        filepath,
        .{},
    ) catch |err| {
        std.log.err(
            "couldn't read file: '{s}', error: {any}\n",
            .{filepath, err},
        );
        return ERR_REF;
    };

    return .{
        .kind = c.otio_ct_timeline,
        .ref = @ptrCast(result.timeline),
    };
}

pub export fn otio_write_to_file(
    allocator_c: c.otio_Allocator,
    timeline_c: c.otio_CompositionItemHandle,
    filepath_c: [*:0]const u8,
) c_int
{
    // Validate that input is a timeline
    if (timeline_c.kind != c.otio_ct_timeline) {
        std.log.err("otio_write_to_file: expected timeline, got {}\n", .{timeline_c.kind});
        return -1;
    }

    const filepath: []const u8 = std.mem.span(filepath_c);
    const allocator = fetch_allocator(allocator_c) catch |err| {
        std.log.err("otio_write_to_file: couldn't fetch allocator: {any}\n", .{err});
        return -1;
    };

    // Get the timeline pointer
    const timeline = ptrCast(
        otio.Timeline,
        timeline_c.ref orelse {
            std.log.err(
                "otio_write_to_file: null timeline reference\n",
                .{},
            );
            return -1;
        },
    );

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    // Write to file (format auto-detected from extension)
    const handle = otio.CompositionItemHandle.init(timeline);
    otio.serialization.write_to_file(
        allocator,
        io,
        handle,
        filepath,
        .{}, // default options
    ) catch |err| {
        std.log.err("otio_write_to_file: couldn't write file '{s}': {any}\n", .{ filepath, err });
        return -1;
    };

    return 0;
}

fn ptrCast(
    t: type,
    ptr: *anyopaque,
) *t
{
    return @as(*t, @ptrCast(@alignCast(ptr)));
}

fn fetch_allocator(
    input: c.otio_Allocator
) !std.mem.Allocator
{
    if (input.ref == null) {
        std.log.err("Null allocator argument\n",.{});
        return error.InvalidAllocatorError;
    }

    return ptrCast(std.mem.Allocator, input.ref.?).*;
}

fn init_CompositionItemHandle(
    input: c.otio_CompositionItemHandle,
) !otio.CompositionItemHandle
{
    if (input.ref)
        |ptr|
    {
        return switch (input.kind) {
            c.otio_ct_timeline => otio.CompositionItemHandle.init(ptrCast(otio.Timeline, ptr)),
            c.otio_ct_stack => otio.CompositionItemHandle.init(ptrCast(otio.Stack, ptr)),
            c.otio_ct_track => otio.CompositionItemHandle.init(ptrCast(otio.Track, ptr)),
            c.otio_ct_clip =>  otio.CompositionItemHandle.init(ptrCast(otio.Clip, ptr)),
            c.otio_ct_gap =>   otio.CompositionItemHandle.init(ptrCast(otio.Gap, ptr)),
            c.otio_ct_warp =>  otio.CompositionItemHandle.init(ptrCast(otio.Warp, ptr)),
            c.otio_ct_transition =>  otio.CompositionItemHandle.init(ptrCast(otio.Transition, ptr)),
            else => return error.ErrorReference,
        };
    }

    return error.ErrorReference;
}

pub fn to_c_ref(
    input: otio.CompositionItemHandle,
) c.otio_CompositionItemHandle
{
    return switch (input) {
        .timeline => |t| .{ .kind = c.otio_ct_timeline, .ref = t },
        .stack => |t|       .{ .kind = c.otio_ct_stack,    .ref = t },
        .track => |t|       .{ .kind = c.otio_ct_track,    .ref = t },
        .clip =>  |t|        .{ .kind = c.otio_ct_clip,     .ref = t },
        .gap =>   |t|         .{ .kind = c.otio_ct_gap,      .ref = t },
        .warp =>  |t|        .{ .kind = c.otio_ct_warp,     .ref = t },
        .transition => |t| .{ .kind = c.otio_ct_transition, .ref = t },
        // Collection is not exposed in C API - should not be passed through here
        .collection => ERR_REF,
    };
}

pub export fn otio_child_count_cvr(
    input: c.otio_CompositionItemHandle,
) c_int
{
    const ref: otio.CompositionItemHandle = init_CompositionItemHandle(input) catch { 
        return -1;
    };

    return switch (ref) {
        .timeline => |tl| @intCast(tl.tracks.children.len),
        inline .stack, .track => |t|  @intCast(t.children.len),
        inline else => 0,
    };
}

pub export fn otio_fetch_child_cvr_ind(
    input: c.otio_CompositionItemHandle,
    c_index: c_int,
) c.otio_CompositionItemHandle
{
    const ref: otio.CompositionItemHandle = init_CompositionItemHandle(input) catch { 
        return ERR_REF; 
    };

    const index: usize = @intCast(c_index);

    const result = switch (ref) {
        .timeline => |tl| res: {
            break :res to_c_ref(tl.tracks.children[index]);
        },
        inline .stack, .track => |t|  res: {
            break :res to_c_ref(t.children[index]);
        },
        inline else => return ERR_REF,
    };

    return result;
}

const ERR_PO_MAP = c.otio_ProjectionTopology{ .ref = null };

pub export fn otio_build_projection_op_map_to_media_tp_cvr(
    allocator_c: c.otio_Allocator,
    source: c.otio_CompositionItemHandle,
) c.otio_ProjectionTopology
{
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_PO_MAP;

    const result = allocator.create(
        otio.TemporalProjectionBuilder
    ) catch return ERR_PO_MAP;

    const src = init_CompositionItemHandle(
        source
    ) catch return ERR_PO_MAP;

    result.* = otio.TemporalProjectionBuilder.init_from(
        allocator,
        src.space_node(.presentation),
    ) catch |err| {
        std.log.err("Couldn't build map: {any}\n", .{ err});
        return ERR_PO_MAP;
    };

    return .{ .ref = result };
}

pub export fn otio_fetch_cvr_type_str(
    self: c.otio_CompositionItemHandle,
    buf: [*]u8,
    len: usize,
) c_int
{
    const space: [:0]const u8 = switch (self.kind) {
        c.otio_ct_timeline => "timeline",
        c.otio_ct_stack => "stack",
        c.otio_ct_track => "track",
        c.otio_ct_clip => "clip",
        c.otio_ct_gap => "gap",
        c.otio_ct_warp => "warp",
        c.otio_ct_err => "err",
        else => "unknown",
    };

    const buf_slice = buf[0..len];

    _ = std.fmt.bufPrintZ(
        buf_slice,
        "{s}",
        .{ space },
    ) catch |err| {
        std.log.err("error printing to buffer: {any}\n", .{err});
        std.log.err("input buffer: '{s}'", .{buf_slice});

        return -1;
    };

    return 0;
}

pub export fn otio_fetch_cvr_name_str(
    self: c.otio_CompositionItemHandle,
    buf: [*]u8,
    len: usize,
) c_int
{
    const ref = init_CompositionItemHandle(self) catch return -1;

    const buf_slice = buf[0..len];

    const item_name = ref.name();

    _ = std.fmt.bufPrintZ(
        buf_slice,
        "{?s}",
        .{ item_name },
    ) catch |err| {
        std.log.err("error printing to buffer: {any}\n", .{err});
        std.log.err("input buffer: '{s}'", .{buf_slice});

        return -1;
    };

    return 0;
}

pub export fn otio_write_map_to_png(
    allocator_c: c.otio_Allocator,
    projection_builder_c: c.otio_ProjectionTopology,
    filepath_c: [*:0]const u8,
) void 
{
    const projection_builder = ptrCast(
        otio.TemporalProjectionBuilder,
        projection_builder_c.ref.?
    );
    const allocator = fetch_allocator(
        allocator_c
    ) catch  return ; 

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    projection_builder.tree.write_dot_graph(
        allocator,
        io,
        std.mem.span(filepath_c),
        "OTIO_TemporalHierarchy",
        .{},
    ) catch {
        std.log.err(
            "couldn't write map to: '{s}'\n",
            .{ filepath_c }
        );
        return;
    };

    std.log.debug("wrote map to: '{s}'\n", .{ filepath_c });
}

pub export fn otio_po_map_fetch_num_endpoints(
    in_po_map: c.otio_ProjectionTopology,
) usize
{
    const po_map = ptrCast(
        otio.TemporalProjectionBuilder,
        in_po_map.ref.?
    );

    return po_map.intervals.items(.mapping_index).len;
}

pub export fn otio_po_map_fetch_endpoints(
    in_po_map_c: c.otio_ProjectionTopology,
) [*]const c.otio_ContinuousInterval
{
    const po_map = ptrCast(
        otio.TemporalProjectionBuilder,
        in_po_map_c.ref.?
    );

    // because Ordinate is a boxed float, the ptr can be cast to a ptr to an
    // array of f32
    return @ptrCast(po_map.intervals.items(.input_bounds).ptr);
}

pub export fn otio_po_map_fetch_num_operators_for_segment(
    in_po_map_c: c.otio_ProjectionTopology,
    ind: usize,
) usize
{
    const po_map = ptrCast(
        otio.TemporalProjectionBuilder,
        in_po_map_c.ref.?
    );

    return po_map.intervals.items(.mapping_index)[ind].len;
}
pub export fn otio_po_map_fetch_op(
    allocator_c: c.otio_Allocator,
    in_po_map_c: c.otio_ProjectionTopology,
    segment_ind: usize,
    operator_ind: usize,
    result: *c.otio_ProjectionOperator,
) c_int
{
    const po_map = ptrCast(
        otio.TemporalProjectionBuilder,
        in_po_map_c.ref.?
    );

    const destination_index = (
        po_map.intervals.items(.mapping_index)[segment_ind][operator_ind]
    );

    const allocator = fetch_allocator(allocator_c) catch return 1;

    const po = allocator.create(
        otio.ProjectionOperator
    ) catch return 1;

    // @TODO: Error Codes
    po.* = po_map.projection_operator_to_index(
        allocator,
        destination_index,
    ) catch return 1;

    result.ref = @constCast(@ptrCast(po));

    return 0;
}

fn init_ProjectionOperator(
    maybe_in_po_c: c.otio_ProjectionOperator,
) !*otio.ProjectionOperator
{
    if (maybe_in_po_c.ref)
        |in_po_c|
    {
        return ptrCast(otio.ProjectionOperator, in_po_c);
    }
    else {
        return error.NullProjectionOperator;
    }
}

pub fn otio_po_fetch_topology_erroring(
    in_po_c: c.otio_ProjectionOperator,
    result: *c.otio_Topology,
) !c_int
{
    const po = try init_ProjectionOperator(in_po_c);

    result.* = .{ .ref = &po.src_to_dst_topo };

    return 0;
}

pub export fn otio_po_fetch_topology(
    in_po_c: c.otio_ProjectionOperator,
    result: *c.otio_Topology,
) c_int
{
    return otio_po_fetch_topology_erroring(
        in_po_c,
        result
    ) catch {
        return -1;
    };
}

fn otio_po_fetch_destination_erroring(
    in_po_c: c.otio_ProjectionOperator,
) !c.otio_CompositionItemHandle
{
    const po = try init_ProjectionOperator(in_po_c);

    // note - returns a SpaceReference, not a CompositionItemHandle
    return to_c_ref(po.destination.item);
}

pub export fn otio_po_fetch_destination(
    in_po_c: c.otio_ProjectionOperator,
) c.otio_CompositionItemHandle
{
    return otio_po_fetch_destination_erroring(in_po_c) catch {
        return ERR_REF;
    };
}

fn otio_po_fetch_source_erroring(
    in_po_c: c.otio_ProjectionOperator,
) !c.otio_CompositionItemHandle
{
    const po = try init_ProjectionOperator(in_po_c);

    // note - returns a SpaceReference, not a CompositionItemHandle
    return to_c_ref(po.source.item);
}

pub export fn otio_po_fetch_source(
    in_po_c: c.otio_ProjectionOperator,
) c.otio_CompositionItemHandle
{
    return otio_po_fetch_source_erroring(in_po_c) catch {
        return ERR_REF;
    };
}

pub export fn otio_po_project_ordinate_cc(
    in_po_c: c.otio_ProjectionOperator,
    input: f64,
    output: *f64,
) c_int
{
    const po = init_ProjectionOperator(in_po_c) catch return -1;

    const input_f32: f32 = @floatCast(input);
    const result = po.project_instantaneous_cc(
        opentime.Ordinate.init(input_f32),
    );

    switch (result) {
        .success_ordinate => |val| {
            output.* = val.as(f64);
            return 0;
        },
        .success_interval => |interval| {
            // For instantaneous projection, take the start of the interval
            output.* = interval.start.as(f64);
            return 0;
        },
        .out_of_bounds => return 1,
    }
}

pub export fn otio_po_project_range_cc(
    allocator_c: c.otio_Allocator,
    in_po_c: c.otio_ProjectionOperator,
    input_start: f64,
    input_end: f64,
    output_start: *f64,
    output_end: *f64,
) c_int
{
    const allocator = fetch_allocator(allocator_c) catch return -1;
    const po = init_ProjectionOperator(in_po_c) catch return -1;

    const start_f32: f32 = @floatCast(input_start);
    const end_f32: f32 = @floatCast(input_end);
    const input_range = opentime.ContinuousInterval{
        .start = opentime.Ordinate.init(start_f32),
        .end = opentime.Ordinate.init(end_f32),
    };

    const result_topo = po.project_range_cc(allocator, input_range) catch return -1;
    const bounds = result_topo.output_bounds() orelse return -1;

    output_start.* = bounds.start.as(f64);
    output_end.* = bounds.end.as(f64);

    return 0;
}

/// attempt to clean up the timeline/object
pub export fn otio_timeline_deinit(
    allocator_c: c.otio_Allocator,
    root_c : c.otio_CompositionItemHandle,
) void
{
    const root = (
        init_CompositionItemHandle(root_c) catch |err| {
            std.log.err(
                " [C-API::deinit] Error converting to object: {any}\n",
                .{ err} ,
            );
            return;
        }
    );

    switch (root) {
        inline .timeline, .stack, .track => 
            |t| (
                // @TODO: remove the need for constCast
                //        constCast becuase CompositionItemHandle is a const*
                //        wrapper
                @constCast(t).deinit(
                    fetch_allocator(allocator_c) catch @panic(
                        "Couldn't find allocator",
                    ),
                )

            ),
        inline else => {},
    }
}

const ERR_TOPO:c.otio_Topology = .{ .ref = null };

/// compute the topology for the CompositionItemHandle
pub export fn otio_fetch_topology(
    allocator_c: c.otio_Allocator,
    ref_c: c.otio_CompositionItemHandle,
) c.otio_Topology
{
    const ref = init_CompositionItemHandle(ref_c) 
        catch return ERR_TOPO;
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_TOPO;

    const result = allocator.create(
        topology.Topology
    ) catch |err|
    {
        std.log.err("problem building topo: {any}\n", .{ err });
        return ERR_TOPO;
    };

    result.* = ref.spanning_topology(allocator) catch return ERR_TOPO;

    return .{ .ref = result };
}

pub export fn otio_topo_fetch_input_bounds(
    topo_c: c.otio_Topology,
    result: *c.otio_ContinuousInterval,
) i32
{
    if (topo_c.ref == null) {
        std.log.err("Null topo pointer\n", .{});

        return -1;
    }

    const ref = topo_c.ref.?;

    const topo = ptrCast(
        topology.Topology,
        ref,
    );

    const b = topo.input_bounds() orelse return -1;

    result.*.start = b.start.as(@TypeOf(result.start));
    result.*.end = b.end.as(@TypeOf(result.end));

    return 0;
}

pub export fn otio_topo_fetch_output_bounds(
    topo_c: c.otio_Topology,
    result: *c.otio_ContinuousInterval,
) i32
{
    if (topo_c.ref == null) {
        std.log.err("Null topo pointer\n", .{});

        return -1;
    }

    const ref = topo_c.ref.?;

    const topo = ptrCast(
        topology.Topology,
        ref,
    );

    const b = topo.output_bounds() orelse return -1;

    result.*.start = b.start.as(@TypeOf(result.start));
    result.*.end = b.end.as(@TypeOf(result.end));

    return 0;
}

fn init_TemporalSpace(
    in_c: c.otio_TemporalSpace
) !otio.TemporalSpace
{
    return switch (in_c) {
        c.otio_sl_presentation => .presentation,
        c.otio_sl_media => .media,
        else => error.InvalidTemporalSpace,
    };
}

fn otio_fetch_discrete_info_erroring(
    handle_c: c.otio_CompositionItemHandle,
    space_c: c.otio_TemporalSpace,
    domain: c.otio_Domain,
    result: *c.otio_DiscreteDatasourceIndexGenerator,
) !c_int
{
    const cih = try init_CompositionItemHandle(handle_c);
    const space = try init_TemporalSpace(space_c);

    const maybe_di = (
        cih.discrete_partition_for_space(
            space,
            domain_from_c(domain),
        )
    );

    if (maybe_di)
        |di|
    {
        const rate : c.otio_Rational = switch (di.sample_rate_hz) {
            .Integer => |i| .{ .num = i, .den = 1 },
            .Rational => |r| .{ .num = r.num, .den = r.den },
        };

        result.* = .{
            .sample_rate_hz = rate,
            .start_index = di.start_index,
        };
        return 0;
    }

    return -1;
}

pub export fn otio_fetch_discrete_info(
    ref_c: c.otio_CompositionItemHandle,
    space: c.otio_TemporalSpace,
    domain: c.otio_Domain,
    result: *c.otio_DiscreteDatasourceIndexGenerator,
) c_int
{
    return otio_fetch_discrete_info_erroring(
        ref_c,
        space,
        domain,
        result,
    ) catch 
    {
        // std.log.err("couldn't fetch discrete info: {any}\n", .{err});
        return -1;
    };
}

fn domain_from_c(
    c_domain: c.otio_Domain,
) otio.Domain
{
    return switch (c_domain) {
        0 => .time,
        1 => .picture,
        2 => .audio,
        3 => .metadata,
        // "other" + is unsupported
        else => @panic("unsupported"),
    };
}

fn otio_fetch_continuous_ordinate_to_discrete_index_erroring(
    ref_c: c.otio_CompositionItemHandle,
    val: f32,
    space_c: c.otio_TemporalSpace,
    domain: c.otio_Domain,
) !i64
{
    const ref = try init_CompositionItemHandle(ref_c);
    const space = try init_TemporalSpace(space_c);
    return try ref.continuous_ordinate_to_discrete_index(
        opentime.Ordinate.init(val),
        space,
        domain_from_c(domain),
    );
}

pub export fn otio_fetch_continuous_ordinate_to_discrete_index(
    ref_c: c.otio_CompositionItemHandle,
    val: f32,
    space_c: c.otio_TemporalSpace,
    domain: c.otio_Domain,
) i64
{
    return otio_fetch_continuous_ordinate_to_discrete_index_erroring(
        ref_c,
        val,
        space_c,
        domain,
    ) catch |err| {
        std.log.err(
            "Error fetching the continuous value: {any}\n",
            .{err}
        );
        return 0;
    };
}

// Extended C API for C++ binding
///////////////////////////////////////////////////////////////////////////////

pub export fn otio_composable_bounds(
    handle_c: c.otio_CompositionItemHandle,
    result: *c.otio_ContinuousInterval,
) c_int
{
    const cih = init_CompositionItemHandle(handle_c) catch return -1;

    // Get bounds based on type - each type stores bounds differently
    const maybe_bounds: ?opentime.ContinuousInterval = switch (cih) {
        .clip => |cl| cl.maybe_bounds_s orelse cl.media.maybe_bounds_s,
        .gap => |g| g.bounds_s,
        .track => |t| t.maybe_bounds_s,
        .stack => |s| s.maybe_bounds_s,
        .timeline => null, // Timeline bounds are derived from tracks
        .warp => null,     // Warp bounds depend on child
        .transition => |tr| tr.maybe_bounds_s,
        .collection => null, // Collection has no temporal bounds
    };

    if (maybe_bounds)
        |bounds|
    {
        result.*.start = bounds.start.as(f32);
        result.*.end = bounds.end.as(f32);
        return 0;
    }

    return -1;
}

pub export fn otio_clip_media(
    clip_c: c.otio_CompositionItemHandle,
    result: *c.otio_MediaReference,
) c_int
{
    if (clip_c.kind != c.otio_ct_clip) {
        return -1;
    }

    const clip = ptrCast(otio.Clip, clip_c.ref orelse return -1);

    // Initialize result with defaults
    result.*.data_type = c.otio_mdt_null;
    result.*.target_uri = null;
    result.*.domain = c.otio_dm_time;
    result.*.has_bounds = 0;
    result.*.has_discrete_info = 0;

    const media_ref = clip.media;

    // Determine data type and URI
    switch (media_ref.data_reference) {
        .uri => |uri_data| {
            result.*.data_type = c.otio_mdt_uri;
            result.*.target_uri = uri_data.target_uri.ptr;
        },
        .signal => {
            result.*.data_type = c.otio_mdt_signal;
        },
        .null => {
            result.*.data_type = c.otio_mdt_null;
        },
        .image_sequence => |img_seq| {
            // Treat image sequence as a URI type, using the base URL
            result.*.data_type = c.otio_mdt_uri;
            result.*.target_uri = img_seq.target_url_base.ptr;
        },
    }

    // Domain
    result.*.domain = switch (media_ref.domain) {
        .time => c.otio_dm_time,
        .picture => c.otio_dm_picture,
        .audio => c.otio_dm_audio,
        .metadata => c.otio_dm_metadata,
        .other => c.otio_dm_other,
    };

    // Bounds
    if (media_ref.maybe_bounds_s)
        |bounds|
    {
        result.*.has_bounds = 1;
        result.*.bounds.start = bounds.start.as(f32);
        result.*.bounds.end = bounds.end.as(f32);
    }

    // Discrete info
    if (media_ref.maybe_discrete_partition)
        |di|
    {
        result.*.has_discrete_info = 1;
        result.*.discrete_info.start_index = di.start_index;
        result.*.discrete_info.sample_rate_hz = switch (di.sample_rate_hz) {
            .Integer => |i| .{ .num = i, .den = 1 },
            .Rational => |r| .{ .num = r.num, .den = r.den },
        };
    }

    return 0;
}

pub export fn otio_transition_kind(
    transition_c: c.otio_CompositionItemHandle,
    buf: [*]u8,
    len: usize,
) c_int
{
    if (transition_c.kind != c.otio_ct_transition) {
        return -1;
    }

    const transition = ptrCast(otio.Transition, transition_c.ref orelse return -1);

    const buf_slice = buf[0..len];
    const kind_str = transition.kind;

    _ = std.fmt.bufPrintZ(
        buf_slice,
        "{s}",
        .{ kind_str },
    ) catch return -1;

    return @intCast(kind_str.len);
}

pub export fn otio_warp_child(
    warp_c: c.otio_CompositionItemHandle,
) c.otio_CompositionItemHandle
{
    if (warp_c.kind != c.otio_ct_warp) {
        return ERR_REF;
    }

    const warp = ptrCast(otio.Warp, warp_c.ref orelse return ERR_REF);

    return to_c_ref(warp.child);
}

pub export fn otio_po_map_fetch_num_segments(
    in_po_map: c.otio_ProjectionTopology,
) usize
{
    const po_map = ptrCast(
        otio.TemporalProjectionBuilder,
        in_po_map.ref orelse return 0,
    );

    // Number of segments is number of intervals
    return po_map.intervals.len;
}

pub export fn otio_po_map_fetch_segment_bounds(
    in_po_map_c: c.otio_ProjectionTopology,
    segment_ind: usize,
    result: *c.otio_ContinuousInterval,
) c_int
{
    const po_map = ptrCast(
        otio.TemporalProjectionBuilder,
        in_po_map_c.ref orelse return -1,
    );

    if (segment_ind >= po_map.intervals.len) {
        return -1;
    }

    const bounds = po_map.intervals.items(.input_bounds)[segment_ind];
    result.*.start = bounds.start.as(f32);
    result.*.end = bounds.end.as(f32);

    return 0;
}
