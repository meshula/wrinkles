pub const EPSILON : f32 = 0.00001;

/// compare the start coordinate of two segments
pub fn cmpSegmentsByStart(a: anytype, b: anytype) bool {
    return a.p0.in < b.p0.in;
}
