const std = @import("std");

/// Collect edits to ALWAYS break conditions containing boolean operators
/// (and/or)
fn example(
) void
{
    // so we repeat until no more edits are produced (stable) or we hit the
    // limit.
    const x: i32 = 42;

    // This is a short comment.

    _ = x;
}

test "comments"
{
    example();
}
