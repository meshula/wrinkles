// treecode.h - Binary encoding of paths through binary trees
// Ported from src/treecode/treecode.zig
//
// A Treecode is a binary encoding of a path through a binary tree,
// packed into a slice of TreecodeWord (u64) words.
//
// The path is read from LSB to MSB. Between the final step and the
// unused space is a single marker bit (0b1).
//
// Example: 0b1011 => marker bit (0b1) + path (011 from right to left)
//   = right(1), right(1), left(0) from the root node.
//
// Path step directions:
//   0: left child
//   1: right child

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// Forward declaration for allocator (we'll use a simple function pointer pattern)
typedef struct Treecode_Allocator Treecode_Allocator;

/// The type of a single word in a Treecode
typedef uint64_t TreecodeWord;

/// Bit width of a single word
#define TREECODE_WORD_BIT_COUNT 64

/// Hash type for a Treecode
typedef uint64_t TreecodeHash;

/// Left or right branch
typedef enum {
    TREECODE_LEFT = 0,
    TREECODE_RIGHT = 1
} Treecode_LorR;

/// Marker bit - separates empty 0 bits from path bits
#define TREECODE_MARKER ((TreecodeWord)1)

/// A binary encoding of a path through a binary tree
typedef struct {
    /// Number of bits set in the treecode (excluding marker)
    size_t code_length;
    /// Backing array of words for the bit path encoding
    TreecodeWord* words;
    /// Number of words allocated
    size_t word_capacity;
} Treecode;

//-----------------------------------------------------------------------------
// Simple allocator interface
//-----------------------------------------------------------------------------

struct Treecode_Allocator {
    void* (*alloc)(void* ctx, size_t size);
    void* (*realloc)(void* ctx, void* ptr, size_t old_size, size_t new_size);
    void (*free)(void* ctx, void* ptr, size_t size);
    void* ctx;
};

// Standard malloc-based allocator
static inline void* treecode_std_alloc(void* ctx, size_t size) {
    (void)ctx;
    return malloc(size);
}

static inline void* treecode_std_realloc(void* ctx, void* ptr, size_t old_size, size_t new_size) {
    (void)ctx;
    (void)old_size;
    return realloc(ptr, new_size);
}

static inline void treecode_std_free(void* ctx, void* ptr, size_t size) {
    (void)ctx;
    (void)size;
    free(ptr);
}

static Treecode_Allocator TREECODE_STD_ALLOCATOR = {
    .alloc = treecode_std_alloc,
    .realloc = treecode_std_realloc,
    .free = treecode_std_free,
    .ctx = NULL
};

//-----------------------------------------------------------------------------
// Internal helper functions
//-----------------------------------------------------------------------------

// Count leading zeros in a TreecodeWord
static inline int treecode_clz(TreecodeWord x) {
    if (x == 0) return TREECODE_WORD_BIT_COUNT;
    return __builtin_clzll(x);
}

// Set a specific bit in a word
static inline TreecodeWord treecode_set_bit_in_word(
    TreecodeWord word,
    int bit_index,
    Treecode_LorR val
) {
    if (val == TREECODE_RIGHT) {
        return word | (((TreecodeWord)1) << bit_index);
    } else {
        return word & ~(((TreecodeWord)1) << bit_index);
    }
}

// Append a bit to a single treecode word
static inline TreecodeWord treecode_word_append(
    TreecodeWord target_word,
    Treecode_LorR new_branch
) {
    int significant_bits = (TREECODE_WORD_BIT_COUNT - 1 - treecode_clz(target_word));

    // Set the new data bit
    TreecodeWord new_val = treecode_set_bit_in_word(
        target_word,
        significant_bits,
        new_branch
    );

    if (significant_bits == TREECODE_WORD_BIT_COUNT - 1) {
        return new_val;
    }

    // Set the marker bit
    return treecode_set_bit_in_word(
        new_val,
        significant_bits + 1,
        TREECODE_RIGHT
    );
}

// Measure code length from a word array
static inline size_t treecode_code_length_measured(
    const TreecodeWord* words,
    size_t word_count
) {
    // Find the last occupied word
    size_t occupied_words = 0;
    for (size_t i = word_count; i > 0; i--) {
        if (words[i - 1] != 0) {
            occupied_words = i - 1;
            break;
        }
    }

    size_t count = (size_t)((TREECODE_WORD_BIT_COUNT - 1) - treecode_clz(words[occupied_words]));

    if (occupied_words == 0) {
        return count;
    }

    return count + (occupied_words * TREECODE_WORD_BIT_COUNT);
}

// Check if lhs is a prefix of rhs (single word version)
static inline bool treecode_word_is_prefix_of(
    TreecodeWord lhs,
    TreecodeWord rhs
) {
    if (lhs == rhs || lhs == TREECODE_MARKER) {
        return true;
    }

    if (lhs == 0 || rhs == 0) {
        return false;
    }

    // Mask the leading zeros + the marker bit
    int lhs_leading_zeros = treecode_clz(lhs) + 1;
    TreecodeWord mask = (((TreecodeWord)1) << (TREECODE_WORD_BIT_COUNT - lhs_leading_zeros)) - 1;

    TreecodeWord lhs_masked = (lhs & mask);
    TreecodeWord rhs_masked = (rhs & mask);

    return lhs_masked == rhs_masked;
}

//-----------------------------------------------------------------------------
// Treecode API
//-----------------------------------------------------------------------------

/// Initialize an empty treecode (just the marker bit)
static inline bool treecode_init(
    Treecode* out,
    Treecode_Allocator* allocator
) {
    out->code_length = 0;
    out->word_capacity = 1;
    out->words = allocator->alloc(allocator->ctx, sizeof(TreecodeWord));
    if (!out->words) return false;
    out->words[0] = TREECODE_MARKER;
    return true;
}

/// Initialize from a single TreecodeWord
static inline bool treecode_init_word(
    Treecode* out,
    Treecode_Allocator* allocator,
    TreecodeWord input
) {
    out->word_capacity = 1;
    out->words = allocator->alloc(allocator->ctx, sizeof(TreecodeWord));
    if (!out->words) return false;
    out->words[0] = input;
    out->code_length = treecode_code_length_measured(out->words, 1);
    return true;
}

/// Free a treecode
static inline void treecode_deinit(
    Treecode* self,
    Treecode_Allocator* allocator
) {
    if (self->words) {
        allocator->free(
            allocator->ctx,
            self->words,
            self->word_capacity * sizeof(TreecodeWord)
        );
        self->words = NULL;
    }
}

/// Clone a treecode
static inline bool treecode_clone(
    const Treecode* self,
    Treecode* out,
    Treecode_Allocator* allocator
) {
    out->code_length = self->code_length;
    out->word_capacity = self->word_capacity;
    out->words = allocator->alloc(
        allocator->ctx,
        self->word_capacity * sizeof(TreecodeWord)
    );
    if (!out->words) return false;
    memcpy(out->words, self->words, self->word_capacity * sizeof(TreecodeWord));
    return true;
}

/// Reallocate to a larger size
static inline bool treecode_realloc(
    Treecode* self,
    Treecode_Allocator* allocator,
    size_t new_word_capacity
) {
    size_t old_size = self->word_capacity * sizeof(TreecodeWord);
    size_t new_size = new_word_capacity * sizeof(TreecodeWord);

    TreecodeWord* new_words = allocator->realloc(
        allocator->ctx,
        self->words,
        old_size,
        new_size
    );
    if (!new_words) return false;

    // Zero out new memory
    memset(
        new_words + self->word_capacity,
        0,
        (new_word_capacity - self->word_capacity) * sizeof(TreecodeWord)
    );

    self->words = new_words;
    self->word_capacity = new_word_capacity;
    return true;
}

/// Append a bit to the treecode
static inline bool treecode_append(
    Treecode* self,
    Treecode_Allocator* allocator,
    Treecode_LorR new_branch
) {
    size_t current_code_length = self->code_length;
    self->code_length += 1;
    size_t new_marker_bit_index = self->code_length;

    // Special case: single word with room
    if (new_marker_bit_index < TREECODE_WORD_BIT_COUNT) {
        self->words[0] = treecode_word_append(self->words[0], new_branch);
        return true;
    }

    // Check if realloc is needed
    size_t last_allocated_index = (self->word_capacity * TREECODE_WORD_BIT_COUNT) - 1;

    if (new_marker_bit_index > last_allocated_index) {
        if (!treecode_realloc(self, allocator, self->word_capacity + 3)) {
            return false;
        }
    }

    // Move the marker one index over
    size_t new_marker_word = new_marker_bit_index / TREECODE_WORD_BIT_COUNT;
    size_t new_data_word = current_code_length / TREECODE_WORD_BIT_COUNT;

    if (new_marker_word == new_data_word) {
        self->words[new_marker_word] = treecode_word_append(
            self->words[new_marker_word],
            new_branch
        );
        return true;
    }

    // Marker is pushed into a new word
    self->words[new_marker_word] = TREECODE_MARKER;

    // Set the last bit in the data word
    self->words[new_data_word] = treecode_set_bit_in_word(
        self->words[new_data_word],
        TREECODE_WORD_BIT_COUNT - 1,
        new_branch
    );

    return true;
}

/// Check if self is a prefix of rhs
static inline bool treecode_is_prefix_of(
    const Treecode* self,
    const Treecode* rhs
) {
    size_t len_self = self->code_length;

    // Empty path is always a prefix
    if (len_self == 0) {
        return true;
    }

    size_t len_rhs = rhs->code_length;

    // If rhs is 0 length or shorter, not a prefix
    if (len_rhs == 0 || len_rhs < len_self) {
        return false;
    }

    if (len_self < TREECODE_WORD_BIT_COUNT) {
        return treecode_word_is_prefix_of(self->words[0], rhs->words[0]);
    }

    size_t greatest_nonzero_index = len_self / TREECODE_WORD_BIT_COUNT;

    for (size_t i = 0; i < greatest_nonzero_index; i++) {
        if (self->words[i] != rhs->words[i]) {
            return false;
        }
    }

    return treecode_word_is_prefix_of(
        self->words[greatest_nonzero_index],
        rhs->words[greatest_nonzero_index]
    );
}

/// Check equality by value
static inline bool treecode_eql(
    const Treecode* self,
    const Treecode* rhs
) {
    if (self->code_length != rhs->code_length) {
        return false;
    }

    size_t end_word = self->code_length / TREECODE_WORD_BIT_COUNT + 1;
    if (end_word > self->word_capacity) end_word = self->word_capacity;
    if (end_word > rhs->word_capacity) end_word = rhs->word_capacity;

    for (size_t i = 0; i < end_word; i++) {
        if (self->words[i] != rhs->words[i]) {
            return false;
        }
    }

    return true;
}

/// Compute hash for this treecode
static inline TreecodeHash treecode_hash(const Treecode* self) {
    // Simple Wyhash-like hash
    uint64_t hash = 0;

    for (size_t i = 0; i < self->word_capacity; i++) {
        if (self->words[i] > 0) {
            // Hash index and word value
            hash ^= (i + 1) * 0x9e3779b97f4a7c15ULL;
            hash ^= self->words[i] * 0xbf58476d1ce4e5b9ULL;
            hash = (hash << 27) | (hash >> 37);
        }
    }

    return hash;
}

/// Find the next step from self towards dest
static inline Treecode_LorR treecode_next_step_towards(
    const Treecode* self,
    const Treecode* dest
) {
    size_t self_len = self->code_length;
    size_t self_len_word = self_len / TREECODE_WORD_BIT_COUNT;
    size_t self_len_pos_local = self_len % TREECODE_WORD_BIT_COUNT;

    TreecodeWord target_word = dest->words[self_len_word];
    bool bit_set = (target_word & (((TreecodeWord)1) << self_len_pos_local)) != 0;

    return bit_set ? TREECODE_RIGHT : TREECODE_LEFT;
}

/// Check if there is a monotonic path from fst to snd
static inline bool treecode_path_exists(
    const Treecode* fst,
    const Treecode* snd
) {
    return (
        treecode_eql(fst, snd) ||
        treecode_is_prefix_of(fst, snd) ||
        treecode_is_prefix_of(snd, fst)
    );
}
