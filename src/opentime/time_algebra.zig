const std = @import("std");
const opentime = @import("./opentime.zig");

// a point cannot contain a point because contains means that fst strictly 
// contains snd
//
// a point is a convienence for a range with 0 duration
//
// we need a definition of a playhead and of a time frame, how does a playback 
//    system describe how it is filtered
// what is a playhead -- maybe as a halfspace w/ a domain specific 
//    reconstruction kernel for the playhead
// what is a time coordinate -- is the rate an implication of duration or 
//    not -- and defining that specifically
// for a transformation, if a point has 

pub fn range_contains_point(
    fst: opentime.TimeRange,
    snd: opentime.TimePoint
) bool
{
    return (
        fst.start_time.t_seconds <= snd.t_seconds 
        and snd.t_seconds < fst.end_time_exclusive_s()
    );
}
