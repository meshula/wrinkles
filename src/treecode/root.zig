//! Treecode Library
//!
//! * `treecode.Treecode`: binary encoding of a path through a binary tree
//! * `binary_tree.BinaryTree`: nodetype-agnostic implementation of a binary
//!                             tree, including `treecode.Treecode` addresses
//!                             for efficient, low-cost path computation
//!                             between nodes.

pub const treecode = @import("treecode.zig");
pub const Treecode = treecode.Treecode;
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
