const std = @import("std");
const opentime = @import("opentime");
const otio = @import("opentimelineio");

const STDOUT = std.io.getStdOut().writer();

// global general purpose allocator
const allocator = @import("./allocator.zig");
const ALLOCATOR = allocator.ALLOCATOR;

pub fn audio_render_test() !void {
    const tl = try otio.build_single_track_timeline();
    // const tl = otio.build_single_track_timeline() catch |err| return err;

    try STDOUT.print("\n", .{});

    // There's no RAII, by design. defer is the answer for destructors
    // var handle = fopen(...);
    // defer fclose();
    //
    // var something = handle.read();
    
    // defer -- always runs when scopes close
    // errdefer  -- only runs when an error closes scopes <- in addition to defer
    
    // exception handling is very explicit. bang returns, e.g. !void, indicate
    // that either a value, or an error result are returned. Functions that try
    // but don't catch must have a bang return.

    // ------------------------------------------------------------------------
    // for large monolithic datastructures (like OTIO), an arena allocator is 
    // used to allocate all the components of the tree, so that the arena can
    // be deallocated in one shot, rather than having to navigate the entire
    // tree and deallocate all the leaves. Care must be taken that a tree of
    // otio data is self contained; if objects are retained outside the tree,
    // or non-arena based elements are in the tree, trouble will ensue.
    // ------------------------------------------------------------------------

    try otio.print_structure(tl);

    try STDOUT.print("\n", .{});
    const output_domain = try otio.build_24fps_192khz_output_domain();

    try otio.print_structure(output_domain);

    const frames_to_render = audio_frames_to_render(tl, output_domain);

    try STDOUT.print("\n", .{});
    for (frames_to_render.items) |audio_frames| 
    {
        for (audio_frames.items) |media_window_to_print| 
        {
            try STDOUT.print(
                    "{s}: {s}", 
                    .{
                        media_window_to_print.media, 
                        media_window_to_print.selected_samples_media,
                    }
            );
        }
    }
}

const MediaWindow = struct {
    media: otio.MediaReference,
    selected_samples_media: otio.DiscreteTimeInterval,
};

// what we want to do:
// output domain:
//      optical printer @ 24fps frame writes audio track at 192khz
//
// input timeline 1: (trivial case, no transformation, only searching)
// timeline:
//      stack:
//          track:
//              clip:
//                  media_references:
//                      - picture: mymov.mov (24hz mjpeg)
//                      - audio: myaudio.wav (mono 192khz audio .wav)
//
// input timeline 2: (transformation + searching, but still single track)
// timeline:
//      stack:
//          track:
//              clip:
//                  media_references:
//                      - picture: mymov.mov (30fps mjpeg)
//                      - audio: myaudio.wav (mono 46khz audio .wav)
//
// input timeline 3: introduce an STRETCHY BITS @TODO
//

//
// problem statement:
// 1. determine the print indices and their attendant time intervals in the
//      reference coordinate system
// 2. for each print interval, find the audio samples, along with the
//      sampling and reconstruction kernels that correspond to the same
//      time interval in the reference coordinate system
// 3. Use the sampling and reconstruction kernels to synthesize the output
//      audio samples to be printed onto the celluloid
//
// Algorithm:
// 1. Get the topology of the picture domain of the input timeline
// 2. Use the output domain to generate a picture sampling on the topology
// 3. For each picture sample that we generate on the topology, build an 
//    interval, from i to i+1
// 4. for each picture intervals, use the output domain to generate an audio 
//    sampling.
// 5. For each audio sample, find the intersecting audio media
//    6. for each intersecting audio media, project the sample into its space, 
//       and record it, pairing the audio media with the sample.
pub fn audio_frames_to_render(
    tl: otio.Timeline,
    output_domain: otio.EvaluationContext,
) std.ArrayList(std.ArrayList(MediaWindow))
{
    // a list of MediaWindows per picture frame in the output domain
    var result = std.ArrayList(std.ArrayList(MediaWindow)).init(ALLOCATOR);

    // cache the otput domain by media domain
    var output_picture_domain = output_domain.get("picture");
    var output_audio_domain = output_domain.get("audio");

    // 1. get the audio/picture time topology of the timeline
    var picture_d_tl_topology = tl.time_topology_for_domain("picture");

    // use the output_picture_domain to generate samples over the picture 
    // topology of the timeline (in this case, a 24hz sequence of samples)
    var picture_od_samples = output_picture_domain.generate_samples_over(
        picture_d_tl_topology
    );
    // What coordinates are these samples in?  Is another projection needed?

    result.resize(picture_od_samples.to_slice().len);

    for (picture_od_samples) 
        |picture_sample, sample_index|
    {
        // for each 24hz sample, convert it to an interval
        var interval_tl = opentime.TimeTopology.from_sample(picture_sample);

        // ...and then sample over that interval using the output audio domain
        var audio_od_samples = (
            output_audio_domain.generate_samples_over(interval_tl)
        );

        // ...this determines the inner size, the number of output audio 
        //    samples per output picture frame
        result[sample_index].resize(audio_od_samples.to_slice().len);

        //    2a. for each audio reference, find the samples associated with 
        //        this 24hz chunk
        for (audio_od_samples) 
            |audio_sample, audio_index| 
        {
            // one thing that bumps me is that we've defined the Domains as 
            // having a coordinate system (by having an origin)... I think that 
            // means they need a transformation.

            // returns all the media references that overlap with the picture's
            // time topology
            var audio_refs = tl.overlapping_media_with_sample(audio_sample);

            // @TODO: audio_refs is known to be of length 1 in this first test
            var audio_media = audio_refs[0];

            var proj_tl_to_audio_media = build_projection_operator(
                tl.space_references.output.for_domain("audio"),
                audio_media.space_references.media.for_domain("audio"),
            );
            var audio_sample_media_space = (
                proj_tl_to_audio_media.project_sample(audio_sample)
            );

            // ? there needs to be something to generate the overlapping
            // samples I think maybe the sample in media space needs to be
            // converted to an interval, and then the media domain (from the
            // media) needs to be used to generate a sampling over the
            // interval?  THOSE resulting samples are the ones that are desired
            //
            //   I _think_ the way this is written implies that the FINAL
            //   sampling happens outside of this function, this function just
            //   returns what to sample and what the interval to sample is
            result[picture_index][audio_index] = .{
                .media = audio_media,
                .selected_samples_media = selected_samples
            };
        }
    }

    return result;
}

pub fn main() !void {
    // basic hello world
    try STDOUT.print("Hello, {s}!\n", .{"world"});

    // BASIC LIST
    var some_list = std.ArrayList(i32).init(ALLOCATOR);
    try some_list.append(12);
    try some_list.append(4);
    try some_list.append(314159);
    try STDOUT.print("List contents:\n", .{});
    for (some_list.items) |value, index| {
        try STDOUT.print("   {d}: {d}\n", .{index, value});
    }
    try STDOUT.print("---\n", .{});

    // LIST HOLDING A UNION (generic-ish)
    try STDOUT.print("\nItem list check\n", .{});
    var item_list = std.ArrayList(otio.MediaReference).init(ALLOCATOR);
    const eref = otio.MediaReference {
        .name = "EREF",
        .domain = otio.IDENTITY_PICTURE_DOMAIN,
        .content = .{
            .external_reference = .{
                .target_url = "/var/tmp/foo.mov",
            },
        },
    };
    try item_list.append(eref);
    const noname_eref = otio.MediaReference {
        .domain = otio.IDENTITY_PICTURE_DOMAIN,
        .content = .{
            .external_reference = .{
                .target_url = "/var/tmp/foo.mov",
            },
        },
    };
    try item_list.append(noname_eref);

    try STDOUT.print("\nItem List: \n", .{});
    for (item_list.items) |value, index| {
        var name = value.name orelse "(no name set)";
        try STDOUT.print("   {d}: {s}\n", .{index, name});
    }

    // TIMELINE TEST
    try audio_render_test();

    // dictionary test
    
    var test_dict = otio.OTIOMetadataDict.init(ALLOCATOR);
    try test_dict.put("test_float", otio.OTIOMetadata { .float = 0.5});
    try test_dict.put("test_int",  otio.OTIOMetadata {.int= 5});
    
    try STDOUT.print(" dict: {s}\n", .{test_dict});

}

const expect = @import("std").testing.expect;
const expectError = @import("std").testing.expectError;
const expectEqual = @import("std").testing.expectEqual;
const expectEqualStrings = @import("std").testing.expectEqualStrings;

test "generated_timeline_test" {
    const tl = try otio.build_single_track_timeline();

    try expectEqual(tl.name, "single track test");

    // expectEqual(tl.tracks.children.items[0].name, "simple clip");
}

test "active union field" {
    const simple = struct {
        name: []const u8 = "",
    };

    const alt = struct {
        name : []const u8 = "",
        float: f32,
    };

    const SimpleOrAlt = union(enum) {
        simple : simple,
        alt: alt,

        pub fn fetched_name(self: @This()) []const u8 {
            return switch(self) {
                .simple => |simpobj| simpobj.name,
                .alt => |altobj| altobj.name,
            };
        }
    };

    const test1 = SimpleOrAlt { .simple = .{.name = "simple_test"}};
    // const test2 = SimpleOrAlt {
    //     .alt = .{
    //         .name = "alt_test", 
    //         .float=3.14
    //     }
    // };

    try expectEqualStrings(test1.simple.name, "simple_test");
    try expectEqualStrings(test1.fetched_name(), "simple_test");

    // is there a way to say test1.<ACTIVE_FIELD>.name?  Because both 
    // possibilities have a "name" field.  Or alternatively can I unpack the
    // value from the union into a concrete type and access its .name?
    // expect(test1.??.name == "simple_test");
    // answer: there will be but isn't at present.  The answer will be:
    // const name = switch (test1) { inline else |*active| => active.name };
}

test "understanding tagged vs untagged unions" {

    const tagged_example = union (enum) {
        float: f32,
        int: i32,
    };

    // var tagged_test = tagged_example { .float=1.5 };
    // below is a synonym for above.  Because the type is specified after the :
    //  as tagged_example, it can be omitted from the assignment.
    var tagged_test : tagged_example = .{ .float=1.5 };
    try expectEqual(tagged_test.float, 1.5);
    try expect(tagged_test == tagged_example.float);

    const bare_example = union {
        float: f32,
        int: i32,
    };

    var bare_test = bare_example { .float=1.5 };
    try expect(bare_test.float == 1.5);

    // would cause an error
    // expectError(bare_test == bare_example.float);
}

