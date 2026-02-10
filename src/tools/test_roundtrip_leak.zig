//! Round trip leak test

const std = @import("std");
const serialization = @import("opentimelineio").serialization;

fn testRoundtrip(
    allocator: std.mem.Allocator,
    tla_path: []const u8,
    tlb_path: []const u8,
) !bool
{
    // Parse TLA using the serializable API
    const ser_tl = try serialization.serializable.read_from_file(
        allocator,
        tla_path,
        .{},
    );

    var timeline_from_tla = switch (ser_tl) {
        .timeline => |t| t,
        .collection => return error.UnexpectedCollection,
    };
    defer timeline_from_tla.deinit(allocator);

    // Serialize TLA to string using an allocating writer
    var tla_buffer = std.Io.Writer.Allocating.init(allocator);
    defer tla_buffer.deinit();

    try serialization.write_serializable_to_writer(
        allocator,
        timeline_from_tla,
        .tla,
        .hash_reference,
        &tla_buffer.writer,
    );
    const tla_output = try tla_buffer.toOwnedSlice();
    defer allocator.free(tla_output);

    // Parse TLB
    const tlb_content = try std.fs.cwd().readFileAlloc(
        allocator,
        tlb_path,
        std.math.maxInt(usize),
    );
    defer allocator.free(tlb_content);

    var timeline_from_tlb = (
        try serialization.binary.deserialize_to_serializable_timeline(
            allocator,
            tlb_content,
            .{},
        )
    );
    defer timeline_from_tlb.deinit(allocator);

    // Serialize TLB to string using an allocating writer
    var tlb_buffer = std.Io.Writer.Allocating.init(allocator);
    defer tlb_buffer.deinit();

    try serialization.write_serializable_to_writer(
        allocator,
        timeline_from_tlb,
        .tla,
        .hash_reference,
        &tlb_buffer.writer,
    );
    const tlb_output = try tlb_buffer.toOwnedSlice();
    defer allocator.free(tlb_output);

    // Compare
    return std.mem.eql(u8, tla_output, tlb_output);
}

pub fn main() !void {
    // Use the General Purpose Allocator with safety checks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("\n*** MEMORY LEAK DETECTED ***\n", .{});
        } else {
            std.debug.print("\n*** NO LEAKS ***\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Test files to check
    const test_pairs = [_]struct { tla: []const u8, tlb: []const u8 }{
        .{ .tla = "test_files/just_warp.tla", .tlb = "test_files/just_warp.tlb" },
        .{ .tla = "test_files/just_warp_bez.tla", .tlb = "test_files/just_warp_bez.tlb" },
        .{ .tla = "test_files/just_transition.tla", .tlb = "test_files/just_transition.tlb" },
        .{ .tla = "test_files/just_clip.tla", .tlb = "test_files/just_clip.tlb" },
        .{ .tla = "test_files/just_track.tla", .tlb = "test_files/just_track.tlb" },
        .{ .tla = "test_files/simple_cut.tla", .tlb = "test_files/simple_cut.tlb" },
        .{ .tla = "test_files/simple_cut_with_markers.tla", .tlb = "test_files/simple_cut_with_markers.tlb" },
        .{ .tla = "test_files/warp_on_warp.tla", .tlb = "test_files/warp_on_warp.tlb" },
        .{ .tla = "otio_sample_data/clip_example.tla", .tlb = "otio_sample_data/clip_example.tlb" },
        .{ .tla = "otio_sample_data/transition.tla", .tlb = "otio_sample_data/transition.tlb" },
    };

    std.debug.print("Testing roundtrip for {d} file pairs...\n\n", .{test_pairs.len});

    var passed: usize = 0;
    var failed: usize = 0;

    for (test_pairs) |pair| {
        // Check if files exist
        std.fs.cwd().access(pair.tla, .{}) catch {
            std.debug.print("  {s}... SKIP (file not found)\n", .{pair.tla});
            continue;
        };
        std.fs.cwd().access(pair.tlb, .{}) catch {
            std.debug.print("  {s}... SKIP (tlb not found)\n", .{pair.tla});
            continue;
        };

        const match = testRoundtrip(allocator, pair.tla, pair.tlb) catch |err| {
            std.debug.print("  {s}... ERROR: {}\n", .{ pair.tla, err });
            failed += 1;
            continue;
        };

        if (match) {
            std.debug.print("  {s}... OK\n", .{pair.tla});
            passed += 1;
        } else {
            std.debug.print("  {s}... MISMATCH\n", .{pair.tla});
            failed += 1;
        }
    }

    std.debug.print("\n=== Results: {d} passed, {d} failed ===\n", .{ passed, failed });
}
