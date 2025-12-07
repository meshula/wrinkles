//! Domain enum definition
const string = @import("string_stuff");

/// A Domain narrows an operation to a particular media domain (E
/// picture, audio, etc).
pub const Domain = union (enum) {
    time,
    picture,
    audio,
    metadata,

    other: string.latin_s8,
};
