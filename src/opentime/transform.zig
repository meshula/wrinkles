//! Implementation of a 1d Affine transformation

const std = @import("std"); 

const ordinate = @import("ordinate.zig");
const interval = @import("interval.zig");
const ContinuousTimeInterval = interval.ContinuousInterval; 

/// AffineTransform1D @{
/// ///////////////////////////////////////////////////////////////////////////
/// Represents a homogenous-coordinates transform matrix of the form:
///     | Scale Offset |
///     |   0     1    | (Implicit)
///
/// Transform order scale then offset, ie y = T(x) = (x * Scale + offset)
/// ///////////////////////////////////////////////////////////////////////////
pub const AffineTransform1D = struct {
    offset: ordinate.Ordinate = 0,
    scale: ordinate.Ordinate = 1,

    /// transform the ordinate.  Order is scale and then offset.
    pub fn applied_to_ordinate(
        self: @This(),
        ord: ordinate.Ordinate,
    ) ordinate.Ordinate
    {
        return ord * self.scale + self.offset;
    }

    /// transform the interval by transforming its endpoints.
    pub fn applied_to_interval(
        self: @This(),
        cint: ContinuousTimeInterval,
    ) ContinuousTimeInterval
    {
        return .{
            .start_seconds = self.applied_to_ordinate(cint.start_seconds),
            .end_seconds = self.applied_to_ordinate(cint.end_seconds)
        };
    }

    /// if the scale of the transform is negative, the ends will flip during
    /// projection.  For bounds, this isn't meaningful and can cause problems.
    /// This function makes sure that result.start_seconds < result.end_seconds
    pub fn applied_to_bounds(
        self: @This(),
        bnds: ContinuousTimeInterval,
    ) ContinuousTimeInterval {
        if (self.scale < 0) {
            return .{
                .start_seconds = self.applied_to_ordinate(bnds.end_seconds),
                .end_seconds = self.applied_to_ordinate(bnds.start_seconds),
            };
        }

        return self.applied_to_interval(bnds);
    }

    /// transform the transform
    pub fn applied_to_transform(
        self: @This(),
        rhs: AffineTransform1D,
    ) AffineTransform1D 
    {
        return .{
            .offset = self.applied_to_ordinate(rhs.offset),
            .scale = rhs.scale * self.scale,
        };
    }

    /// Return the inverse of this time transform.
    ///    ** assumes that scale is non-zero **
    ///
    /// Because the AffineTransform1D is a 2x2 matrix of the form:
    ///     | scale offset |
    ///     |   0     1    |
    ///
    /// The inverse is:
    ///     | 1/scale -offset/scale |
    ///     |   0           1       |
    /// To derive this:
    ///     | A B | * | S O |   | 1 0 |
    ///     | C D |   | 0 1 | = | 0 1 |
    ///     =>
    ///     A*S = 1 => A = 1/S
    ///     A*O + B = 0 => B = -O*A => B = -O/S
    ///     C * S = 0 => C = 0
    ///     C * O + D = 1 => D = 1
    pub fn inverted(
        self: @This(),
    ) AffineTransform1D
    {
        // !! Assumes that scale is not 0
        // if (self.scale == 0) {
        //     return ZeroScaleError;
        // }

        return .{
            .offset = -self.offset/self.scale,
            .scale = 1/self.scale,
        };
    }

    /// custom formatter for std.fmt
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        try writer.print(
            "Aff1D{{ offset: {d} scale: {d} }}",
            .{
                self.offset,
                self.scale,
            }
        );
    }
};

pub const IDENTITY_TRANSFORM = AffineTransform1D{
    .offset = 0,
    .scale = 1,
};

test "AffineTransform1D: offset test" 
{
    const cti = ContinuousTimeInterval {
        .start_seconds = 10,
        .end_seconds = 20,
    };

    const xform = AffineTransform1D {
        .offset = 10,
        .scale = 1,
    };

    const result: ContinuousTimeInterval = xform.applied_to_interval(cti);
    
    try std.testing.expectEqual(
        ContinuousTimeInterval {
            .start_seconds = 20,
            .end_seconds = 30
        },
        result
    );

    try std.testing.expectEqual(
        10,
        result.duration_seconds()
    );

    try std.testing.expectEqual(
        cti.duration_seconds(),
        result.duration_seconds()
    );

    const result_xform = xform.applied_to_transform(xform);

    try std.testing.expectEqual(
        result_xform,
        AffineTransform1D{
            .offset = 20,
            .scale = 1
        }
    );
}

test "AffineTransform1D: scale test" 
{
    const cti = ContinuousTimeInterval {
        .start_seconds = 10,
        .end_seconds = 20,
    };

    const xform = AffineTransform1D {
        .offset = 10,
        .scale = 2,
    };

    const result = xform.applied_to_interval(cti);

    try std.testing.expectEqual(
        ContinuousTimeInterval {
            .start_seconds = 30,
            .end_seconds = 50,
        },
        result
    );

    try std.testing.expectEqual(
        result.duration_seconds(),
        cti.duration_seconds() * xform.scale,
    );

    const result_xform = xform.applied_to_transform(xform);

    try std.testing.expectEqual(
        AffineTransform1D {
            .offset = 30,
            .scale = 4,
        },
        result_xform,
    );
}

test "AffineTransform1D: invert test" 
{
    const xform = AffineTransform1D {
        .offset = 10,
        .scale = 2,
    };

    const identity = xform.applied_to_transform(
        xform.inverted()
    );

    try std.testing.expectEqual(0, identity.offset);
    try std.testing.expectEqual(1, identity.scale);

    const pt:ordinate.Ordinate = 10;

    const result = xform.inverted().applied_to_ordinate(
        xform.applied_to_ordinate(pt)
    );

    try std.testing.expectEqual(pt, result);
}

test "AffineTransform1D: applied_to_bounds" 
{
    const xform = AffineTransform1D {
        .offset = 10,
        .scale = -1,
    };
    const bounds = ContinuousTimeInterval{
        .start_seconds = 10,
        .end_seconds = 20,
    };
    const result = xform.applied_to_bounds(bounds);

    try std.testing.expect(result.start_seconds < result.end_seconds);
}
