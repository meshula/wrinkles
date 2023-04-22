pub const EPSILON: f32 = 0.000001;

/// compare the start coordinate of two segments
pub fn cmpSegmentsByStart(a: anytype, b: anytype) bool {
    return a.p0.time < b.p0.time;
}
