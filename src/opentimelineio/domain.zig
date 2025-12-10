//! Domains represent different media domains present in a temporal document.
//! For example, a single timeline can describe picture and audio data in the
//! same overall temporal tree.
//!
//! Media and Discrete spaces must be tied to specific domains so that
//! consumers of this library know what type of media is meant to be operated
//! on by sub trees.

const string = @import("string_stuff");

/// A Domain narrows an operation to a particular media domain (E
/// picture, audio, etc).
pub const Domain = union (enum) {
    /// Temporal domain (@TODO: remove?)
    time,

    /// Picture domain (images, videos, etc)
    picture,

    /// Audio domain (sound)
    audio,

    /// Metadata (@TODO: remove?)
    metadata,

    /// Anything else can be referred to by a string label.  Fireworks, motion
    /// capture data, etc.
    other: string.latin_s8,
};
