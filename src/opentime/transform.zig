const std = @import("std"); 

const interval = @import("interval.zig");
const ContinuousTimeInterval = interval.ContinuousTimeInterval; 

const expectEqual = std.testing.expectEqual;

// AffineTransform1D @{
// ////////////////////////////////////////////////////////////////////////////
// Represents a homogenous-coordinates transform matrix of the form:
//     | Scale Offset |
//     |   0     1    | (Implicit)
// ////////////////////////////////////////////////////////////////////////////
pub const AffineTransform1D = struct {
    offset_seconds: f32 = 0,
    scale: f32 = 1,

    pub fn applied_to_seconds(
        self: @This(),
        t_seconds: f32
    ) f32
    {
        return t_seconds * self.scale + self.offset_seconds;
    }

    pub fn applied_to_cti(
        self: @This(),
        cti: ContinuousTimeInterval,
    ) ContinuousTimeInterval
    {
        return .{
            .start_seconds = self.applied_to_seconds(cti.start_seconds),
            .end_seconds = self.applied_to_seconds(cti.end_seconds)
        };
    }

    pub fn applied_to_transform(
        self: @This(),
        rhs: AffineTransform1D,
    ) AffineTransform1D 
    {
        return .{
            .offset_seconds = self.applied_to_seconds(rhs.offset_seconds),
            .scale = rhs.scale * self.scale,
        };
    }

    // Return the inverse of this time transform.
    //    ** assumes that scale is non-zero **
    //
    // Because the AffineTransform1D is a 2x2 matrix of the form:
    //     | scale offset |
    //     |   0     1    |
    //
    // The inverse is:
    //     | 1/scale -offset/scale |
    //     |   0           1       |
    // To derive this:
    //     | A B | * | S O |   | 1 0 |
    //     | C D |   | 0 1 | = | 0 1 |
    //     =>
    //     A*S = 1 => A = 1/S
    //     A*O + B = 0 => B = -O/S
    //     C * S = 0 => C = 0
    //     C * O + D = 1 => D = 1
    pub fn inverted(
        self: @This()
    ) AffineTransform1D
    {
        // @QUESTION: should this do a check for 0 scale?  That could make
        //            this return type !AffineTransform1D.
        // if (self.scale == 0) {
        //     return ZeroScaleError;
        // }

        return .{
            .offset_seconds = -self.offset_seconds/self.scale,
            .scale = 1/self.scale,
        };
    }
};


test "AffineTransform1D: offset test" {
    const cti = ContinuousTimeInterval {
        .start_seconds = 10,
        .end_seconds = 20,
    };

    const xform = AffineTransform1D {
        .offset_seconds = 10,
        .scale = 1,
    };

    const result: ContinuousTimeInterval = xform.applied_to_cti(cti);
    
    try expectEqual(
        ContinuousTimeInterval {
            .start_seconds = 20,
            .end_seconds = 30
        },
        result
    );

    try expectEqual(
        @as(f32, 10),
        result.duration_seconds()
    );

    try expectEqual(
        cti.duration_seconds(),
        result.duration_seconds()
    );

    const result_xform = xform.applied_to_transform(xform);

    try expectEqual(
        result_xform,
        .{
            .offset_seconds = 20,
            .scale = 1
        }
    );
}

test "AffineTransform1D: scale test" {
    const cti = ContinuousTimeInterval {
        .start_seconds = 10,
        .end_seconds = 20,
    };

    const xform = AffineTransform1D {
        .offset_seconds = 10,
        .scale = 2,
    };

    const result = xform.applied_to_cti(cti);

    try expectEqual(
        ContinuousTimeInterval {
            .start_seconds = 30,
            .end_seconds = 50
        },
        result
    );

    try expectEqual(
        result.duration_seconds(),
        cti.duration_seconds() * xform.scale
    );

    const result_xform = xform.applied_to_transform(xform);

    try expectEqual(
        AffineTransform1D {
            .offset_seconds = 30,
            .scale = 4,
        },
        result_xform
    );
}

test "AffineTransform1D: invert test" {
    const xform = AffineTransform1D {
        .offset_seconds = 10,
        .scale = 2,
    };

    // const identity = xform.inverted().applied_to_transform(xform);
    const identity = xform.applied_to_transform(xform.inverted());

    try expectEqual(@as(f32, 0), identity.offset_seconds);
    try expectEqual(@as(f32, 1), identity.scale);

    const pt = @as(f32, 10);

    const result = xform.inverted().applied_to_seconds(
        xform.applied_to_seconds(pt)
    );

    try expectEqual(pt, result);
}
// @}
