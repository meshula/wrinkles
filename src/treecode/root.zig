//! Treecode Library
//!
//! * `treecode.Treecode`: binary encoding of a path through a graph
//! * `map.Map`: a Mapping of treecodes to entries in a graph

pub const treecode = @import("treecode.zig");
pub const Treecode = treecode.Treecode;
pub const MARKER = treecode.MARKER;
pub const TreecodeWord = treecode.TreecodeWord;
pub const TreecodeHashMap= treecode.TreecodeHashMap;
pub const l_or_r= treecode.l_or_r;
pub const path_exists= treecode.path_exists;

pub const binary_tree = @import("binary_tree.zig");
pub const BinaryTree = binary_tree.BinaryTree;

test
{
    _ = treecode;
    _ = binary_tree;
}
