const std = @import("std");

const curve = @import("curve");
const string_stuff = @import("string_stuff");
const latin_s8 = string_stuff.latin_s8;
const util = @import("util.zig");

// @TODO: this needs to be removed before this will compile
// const time_topology = @import("time_topology");

const sample = @import("sample.zig");

const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

pub const MediaDomainToken = latin_s8;

// @QUESTION: I suspect this really belongs in OTIO and not opentime.  We
//            haven't revisited the 'domain' idea since sketching this out,
//            however.


// @TODO: this is a more complicated object than it was before, so we should
//        provide some convie functions to handle cases like a regularly sampled
//        movie with a known rate and range.
// @QUESTION: One thing I'm not seeing with this is a use case we discussed -
//            let say we have a timeline but want to serialize it to a 24hz
//            picture sample thing where the first index starts at 86400.
//            I'm not sure how to rig that with this arrangement.
pub const Domain = struct {
    label: MediaDomainToken, // <- token?

    // @QUESTION: it doesn't appear as though this tcs has any usage at the moment
    tcs: time_topology.TimeTopology = .{},

    sample_generator: sample.StepSampleGenerator = .{ 
        .start_offset = 0,
        // @QUESTION: I think this should _not_ have a default value
        .rate_hz = 24
    },

    pub fn init(
        label: MediaDomainToken,
        rate_hz: f32
    ) Domain 
    {
        return .{
            .label = label,
            .sample_generator = .{
                .rate_hz = rate_hz
            }
        };
    }

    // only going to do regular sampling
    pub fn generate_samples_over(
        self: @This(),
        topology: time_topology.TimeTopology
    ) ![]sample.Sample {
        return try self.sample_generator.sample_over(topology);
    }
};

test "Domain: identity" 
{
    var ident_domain: Domain = .{.label = "picture"};
    _ = ident_domain;
}


