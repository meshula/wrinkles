#pragma once
#include <cstdint>
#include <vector>
#include <bit>
#include <iostream>
#include <functional>

// Treecode: Binary encoding of a path through a binary tree
//
// Ported from wrinkles/src/treecode/treecode.zig

// ============================================================================
// Type Definitions and Constants
// ============================================================================

/// The type of a single word in a Treecode
using TreecodeWord = uint64_t;

/// Bit width of a single word in a Treecode
constexpr size_t WORD_BIT_COUNT = 64;

/// Hash type for a Treecode
using Hash = uint64_t;

/// All treecodes start with this code. Separates the empty 0 bits from the path bits.
constexpr TreecodeWord MARKER = 0b1;

/// The left or the right branch
enum class LeftOrRight : uint8_t {
    Left = 0,
    Right = 1
};

// ============================================================================
// Bit Manipulation Helpers (Private)
// ============================================================================

namespace detail {

/// Set a bit in a word at the given position
inline constexpr TreecodeWord set_bit_in_word(
    TreecodeWord word,
    size_t bit_position,
    LeftOrRight value
) noexcept {
    TreecodeWord mask = TreecodeWord(1) << bit_position;
    if (value == LeftOrRight::Right) {
        return word | mask;  // Set bit
    } else {
        return word & ~mask;  // Clear bit
    }
}

/// Create a mask for the given number of leading zeros
inline constexpr TreecodeWord treecode_word_mask(size_t leading_zeros) noexcept {
    return (TreecodeWord(1) << (WORD_BIT_COUNT - leading_zeros)) - 1;
}

/// Return true if lhs is a prefix of rhs
inline constexpr bool treecode_word_is_prefix_of(
    TreecodeWord lhs,
    TreecodeWord rhs
) noexcept {
    if (lhs == rhs || lhs == MARKER) {
        return true;
    }

    if (lhs == 0 || rhs == 0) {
        return false;
    }

    // Mask the leading zeros + the marker bit
    size_t lhs_leading_zeros = std::countl_zero(lhs) + 1;
    TreecodeWord mask = treecode_word_mask(lhs_leading_zeros);

    TreecodeWord lhs_masked = lhs & mask;
    TreecodeWord rhs_masked = rhs & mask;

    return lhs_masked == rhs_masked;
}

/// Append a bit to a treecode word
inline constexpr TreecodeWord treecode_word_append(
    TreecodeWord target_word,
    LeftOrRight new_branch
) noexcept {
    size_t significant_bits = WORD_BIT_COUNT - 1 - std::countl_zero(target_word);

    // Set the new data bit
    TreecodeWord new_val = set_bit_in_word(target_word, significant_bits, new_branch);

    if (significant_bits == WORD_BIT_COUNT - 1) {
        return new_val;
    }

    // Set the marker bit
    return set_bit_in_word(new_val, significant_bits + 1, LeftOrRight::Right);
}

} // namespace detail

// ============================================================================
// Treecode Class
// ============================================================================

/// A binary encoding of a path through a binary tree, packed into a vector of
/// TreecodeWord (uint64_t) words which contain the bits.
///
/// The path is read from LSB (right most bit) to MSB (left most bit). Between
/// the final step in the path (MSB path bit) and the zeroes of the unused
/// space in the integer is a single marker bit (0b1).
///
/// Example: 0b1011 => read as:
///   * 0b1 marker bit (MSB/Left most non-zero bit), always a 1
///   * 011 path (read from right to left, LSB -> MSB, omitting the marker),
///         so in order from start to finish: 1, 1, 0 from the root node.
///
/// Path step directions:
/// * 0: left child
/// * 1: right child
///
/// Examples:
/// * 0b1 => marker bit only (no direction)
/// * 0b1001 => 0b1 001 -> right, left, left
/// * 0b111001 => 0b1 11001 -> right, left, left, right, right
/// * 0b1010 => 0b1 010 -> left, right, left
class Treecode {
public:
    std::vector<TreecodeWord> words;

    // ---- Construction ----

    /// Default constructor - creates empty treecode (invalid state, should use init())
    Treecode() = default;

    /// Initialize with just the MARKER bit
    static Treecode init() noexcept {
        Treecode tc;
        tc.words.push_back(MARKER);
        return tc;
    }

    /// Initialize from a single TreecodeWord
    static Treecode init_word(TreecodeWord input) noexcept {
        Treecode tc;
        tc.words.push_back(input);
        return tc;
    }

    /// Clone (deep copy)
    Treecode clone() const {
        Treecode tc;
        tc.words = words;  // Vector copy
        return tc;
    }

    // ---- Path Operations ----

    /// Returns the number of bits used to encode the path
    /// (number of non-zero bits before trailing zeros, omitting marker bit)
    size_t code_length() const noexcept {
        if (words.empty()) {
            return 0;
        }

        // Find the last occupied word
        size_t occupied_words = 0;
        for (size_t i = words.size(); i > 0; --i) {
            if (words[i - 1] != 0) {
                occupied_words = i - 1;
                break;
            }
        }

        // Count bits in the occupied word
        size_t count = (WORD_BIT_COUNT - 1) - std::countl_zero(words[occupied_words]);

        if (occupied_words == 0) {
            return count;
        }

        return count + (occupied_words * WORD_BIT_COUNT);
    }

    /// By-value equality of the treecode
    /// Does not consider the size of the treecode array
    /// Example: 0b1 == 0b00001
    bool eql(Treecode const& rhs) const noexcept {
        size_t self_code_len = code_length();

        if (self_code_len != rhs.code_length()) {
            return false;
        }

        size_t end_word = self_code_len / WORD_BIT_COUNT + 1;

        // Make sure we don't go out of bounds
        if (end_word > words.size() || end_word > rhs.words.size()) {
            return false;
        }

        for (size_t i = 0; i < end_word; ++i) {
            if (words[i] != rhs.words[i]) {
                return false;
            }
        }

        return true;
    }

    /// In place append a bit to this treecode. Will grow vector if needed.
    void append(LeftOrRight new_branch) {
        if (words.empty()) {
            throw std::runtime_error("Cannot append to empty treecode");
        }

        size_t current_code_length = code_length();

        // Index for the new branch
        size_t next_index = current_code_length + 1;

        // Special case: single word with room for append
        if (next_index < WORD_BIT_COUNT) {
            words[0] = detail::treecode_word_append(words[0], new_branch);
            return;
        }

        // The last index that can be written to without triggering a realloc
        size_t last_allocated_index = (words.size() * WORD_BIT_COUNT) - 1;

        if (next_index > last_allocated_index) {
            // Grow the vector (add 3 words as per Zig implementation)
            size_t old_size = words.size();
            words.resize(old_size + 3, 0);  // Fill new words with 0
        }

        // Move the marker one index over
        size_t new_marker_word = next_index / WORD_BIT_COUNT;
        size_t new_data_word = current_code_length / WORD_BIT_COUNT;

        if (new_marker_word == new_data_word) {
            words[new_marker_word] = detail::treecode_word_append(
                words[new_marker_word],
                new_branch
            );
            return;
        }

        // If the marker word doesn't match the data word,
        // then the marker is getting pushed into the new word
        words[new_marker_word] = MARKER;

        // Set the last bit in the last word
        words[new_data_word] = detail::set_bit_in_word(
            words[new_data_word],
            WORD_BIT_COUNT - 1,
            new_branch
        );
    }

    /// Self is a prefix of rhs if self is the same length or shorter than rhs
    /// and all of the bits in self's path are the same as the first bits of rhs.
    ///
    /// Examples:
    /// * 0b1101 is a parent of 0b00101
    /// * 0b1101 is not a parent of 0b1010
    /// * 0b1 is a parent of anything, including 0b1
    /// * 0b10 is not a parent of 0b1
    bool is_prefix_of(Treecode const& rhs) const noexcept {
        size_t len_self = code_length();

        // Empty lhs path is always a prefix of rhs
        if (len_self == 0) {
            return true;
        }

        size_t len_rhs = rhs.code_length();

        // If rhs is 0 length or shorter than self, self is not a prefix of rhs
        if (len_rhs == 0 || len_rhs < len_self) {
            return false;
        }

        if (len_self < WORD_BIT_COUNT) {
            return detail::treecode_word_is_prefix_of(words[0], rhs.words[0]);
        }

        size_t greatest_nonzero_rhs_index = len_self / WORD_BIT_COUNT;

        for (size_t i = 0; i < greatest_nonzero_rhs_index; ++i) {
            if (words[i] != rhs.words[i]) {
                return false;
            }
        }

        return detail::treecode_word_is_prefix_of(
            words[greatest_nonzero_rhs_index],
            rhs.words[greatest_nonzero_rhs_index]
        );
    }

    /// Compute and return the Hash for this Treecode
    /// The hash includes the index and value of each non-zero word
    Hash hash() const noexcept {
        // Simple hash combining index and value
        // Using FNV-1a algorithm
        Hash h = 14695981039346656037ULL;  // FNV offset basis

        for (size_t index = 0; index < words.size(); ++index) {
            TreecodeWord word = words[index];
            if (word > 0) {
                // Hash index (add 1 to match Zig which starts at 1)
                h ^= (index + 1);
                h *= 1099511628211ULL;  // FNV prime

                // Hash word
                h ^= word;
                h *= 1099511628211ULL;
            }
        }

        return h;
    }

    /// Given a dest code which is a child (longer/with the same prefix) of
    /// self, find the next bit after the bits in self that is present in dest
    /// (IE the next step down the tree towards the location of dest).
    ///
    /// Examples:
    /// * 0b1 next step toward 0b11 -> Right
    /// * 0b101 next step toward 0b10101 -> Left
    /// * 0b101 next step toward 0b111011101 -> Right
    LeftOrRight next_step_towards(Treecode const& dest) const noexcept {
        size_t self_len = code_length();
        size_t self_len_pos_local = self_len % WORD_BIT_COUNT;
        size_t self_len_word = self_len / WORD_BIT_COUNT;

        TreecodeWord mask = TreecodeWord(1) << self_len_pos_local;
        TreecodeWord masked_val = dest.words[self_len_word] & mask;

        return static_cast<LeftOrRight>((masked_val >> self_len_pos_local));
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, Treecode const& tc) {
        size_t marker_pos_abs = tc.code_length();
        size_t last_index = marker_pos_abs / WORD_BIT_COUNT;

        if (last_index >= tc.words.size()) {
            os << "0b0";
            return os;
        }

        os << "0b";

        // Print from most significant word to least
        for (size_t i = last_index + 1; i > 0; --i) {
            size_t word_index = i - 1;
            TreecodeWord tcw = tc.words[word_index];

            if (word_index == last_index) {
                // For the most significant word, just print the value
                for (int bit = 63; bit >= 0; --bit) {
                    if (tcw & (TreecodeWord(1) << bit)) {
                        // Found first 1 bit, print from here
                        for (int b = bit; b >= 0; --b) {
                            os << ((tcw & (TreecodeWord(1) << b)) ? '1' : '0');
                        }
                        break;
                    }
                }
            } else {
                // For other words, print all 64 bits
                for (int bit = 63; bit >= 0; --bit) {
                    os << ((tcw & (TreecodeWord(1) << bit)) ? '1' : '0');
                }
            }
        }

        return os;
    }
};

// ============================================================================
// Hash and Equality for std::unordered_map
// ============================================================================

struct TreecodeHash {
    size_t operator()(Treecode const& tc) const noexcept {
        return static_cast<size_t>(tc.hash());
    }
};

struct TreecodeEqual {
    bool operator()(Treecode const& lhs, Treecode const& rhs) const noexcept {
        return lhs.eql(rhs);
    }
};

/// Convenience type alias for hash map with Treecode keys
template<typename T>
using TreecodeHashMap = std::unordered_map<Treecode, T, TreecodeHash, TreecodeEqual>;
