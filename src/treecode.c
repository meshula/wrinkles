
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#ifndef UINT128_MAX
typedef unsigned __int128 uint128_t;
#endif
typedef uint128_t treecode_128;


// a treecode is formed by a 128-bit integer, where the most significant
// bit is a sentinel and the remaining bits are a path from the root
// to a leaf in a binary tree. The sentinel bit is always one, and the
// other bits encode left branches as a zero, and right branches as a one.
// The root is the least significant bit, and branches are ordered from
// left to right.

typedef struct {
    int sz;
    treecode_128* treecode_array;
} treecode;

typedef void* (*malloc_ptr)(size_t size);
typedef void (*free_ptr)(void* alloc);

treecode* treecode_alloc(malloc_ptr m, free_ptr f) {
    if (m == NULL || f == NULL)
        return NULL;
    treecode* new_treecode_a = m(sizeof(treecode));
    if (new_treecode_a == NULL)
        return NULL;
    new_treecode_a->sz = 1;
    new_treecode_a->treecode_array = m(sizeof(treecode_128));
    if (new_treecode_a->treecode_array == NULL) {
        f(new_treecode_a);
        return NULL;
    }
    return new_treecode_a;
}

// reallocate the treecode array to be twice as large
bool treecode_realloc(treecode* a, int new_size, malloc_ptr m, free_ptr f) {
    if (a == NULL || m == NULL || f == NULL)
        return false;
    if (new_size < a->sz)
        return false;
    if (new_size == a->sz)
        return true;
    treecode_128* new_treecode_array = m(new_size * sizeof(treecode_128));
    if (new_treecode_array == NULL)
        return false;
    for (int i = 0; i < a->sz; i++) {
        new_treecode_array[i] = a->treecode_array[i];
    }
    f(a->treecode_array);
    a->treecode_array = new_treecode_array;
    int sz = a->sz;
    a->sz = new_size;
    for (int i  = sz; i < a->sz; i++) {
        a->treecode_array[i] = 0;
    }
    return true;
}


int treecode_code_length(treecode* a) {
    if (a == NULL)
        return 0;
    if (a->sz == 0)
        return 0;
    if (a->sz == 1)
        return nlz128(a->treecode_array[0]);
    int count = 0;
    for (int i = a->sz; i > 1; --i) {
        if (a->treecode_array[i] != 0) {
            count = 128 - nlz128(a->treecode_array[i]);
            return count + i * 128;
        }
    }
    return 128 - nlz128(a->treecode_array[0]);
}


int nlz128(uint128_t x) {
   int n;

   if (x == 0) return(128);
   n = 0;
   if (x <= 0x00000000FFFF) {n = n +64; x = x <<64;}
   if (x <= 0x000000FFFFFF) {n = n +32; x = x <<32;}
   if (x <= 0x0000FFFFFFFF) {n = n +16; x = x <<16;}
   if (x <= 0x00FFFFFFFFFF) {n = n + 8; x = x << 8;}
   if (x <= 0x0FFFFFFFFFFF) {n = n + 4; x = x << 4;}
   if (x <= 0x3FFFFFFFFFFF) {n = n + 2; x = x << 2;}
   if (x <= 0x7FFFFFFFFFFF) {n = n + 1;}
   return n;
}

int nlz(treecode* tc) {
    if ((tc == NULL) || (tc->treecode_array == NULL) || (tc->sz == 0))
        return 0;

    if (tc->sz == 1)
        return nlz128(tc->treecode_array[0]);

    int n = 0;
    for (int i = tc->sz; i > 0; --i) {
        if (tc->treecode_array[i] == 0) {
            n += 128;
        } else {
            n += nlz128(tc->treecode_array[i]);
            break;
        }
    }

    return n;
}

bool test_nlz128() {
    uint128_t x = 0;
    if (nlz128(x) != 128) {
        return false;
    }
    for (int i = 0; i < 128; i++) {
        if (nlz128(x) != i) {
            return false;
        }
        x = (x << 1) | 1;
    }
    return true;
}

treecode_128 treecode128_mask(int leading_zeros) {
    return ((treecode_128)1 << (128 - leading_zeros)) - 1;
}

bool treecode128_b_is_a_subset(treecode_128 a, treecode_128 b) {
    if (a == b) {
        return true;
    }
    if (a == 0 || b == 0) {
        return false;
    }
    int leading_zeros = nlz128(b) - 1;
    treecode_128 mask = treecode128_mask(leading_zeros);
    return (a & mask) == (b & mask);
}

bool treecode_b_is_a_subset(treecode *a, treecode *b) {
    if (a == NULL || b == NULL)
        return false;
    if (a == b)
        return true;
    int len_a = treecode_code_length(a);
    int len_b = treecode_code_length(b);
    if (len_a == 0 || len_b == 0 || len_b > len_a)
        return false;
    if (len_a <= 128) {
        return treecode128_b_is_a_subset(a->treecode_array[0], b->treecode_array[0]);
    }
    int greatest_nozero_b_index = len_b / 128;
    for (int i = 0; i < greatest_nozero_b_index; i++) {
        if (a->treecode_array[i] != b->treecode_array[i])
            return false;
    }
    treecode_128 mask = treecode128_mask(128 - ((len_b - 1) % 128));
    return (a->treecode_array[greatest_nozero_b_index] & mask) == (b->treecode_array[greatest_nozero_b_index] & mask);
}

bool treecode_is_equal(treecode* a, treecode* b) {
    if (a == NULL || b == NULL)
        return false;
    if (a == b)
        return true;
    int len_a = treecode_code_length(a);
    int len_b = treecode_code_length(b);
    if (len_a != len_b)
        return false;
    int greatest_nozero_index = len_a / 128;
    for (int i = 0; i < greatest_nozero_index; i++) {
        if (a->treecode_array[i] != b->treecode_array[i])
            return false;
    }
    return true;
}

bool test_treecode_is_equal() {
    treecode_128 a = 0;
    treecode_128 b = 0;
    if (!treecode_is_equal(a, b)) {
        return false;
    }
    for (int i = 0; i < 128; i++) {
        if (!treecode_is_equal(a, b)) {
            return false;
        }
        a = (a << 1) | 1;
        b = (b << 1) | 1;
    }
    return true;
}

treecode_128 treecode_append(treecode_128 a, uint8_t l_or_r) {
    int leading_zeros = nlz128(a);
    // strip leading bit
    treecode_128 leading_bit = ((treecode_128)1 << (128 - leading_zeros));
    a -= leading_bit;
    return a | (leading_bit << 1) | (l_or_r << (128 - leading_zeros - 1));
}

treecode* treecode_append(treecode* a, int l_or_r, malloc_ptr m, free_ptr f) {
    if (a == NULL) {
        return NULL;
    }
    if (a->sz == 0) {
        treecode* ret = treecode_new(m, f);
        if (ret == NULL)
            return NULL;
        ret->treecode_array[0] = 1;
    }
    int len = treecode_code_length(a);
    if (len < 128) {
        a->treecode_array[0] = treecode128_append(a->treecode_array[0]);
        return a;
    }
    int index = len / 128;
    if (index >= a->sz) {
        // in this case, the array is full.
        treecode* ret = treecode_realloc(a, index + 1, m, f);
        if (ret == NULL)
            return NULL;
        ret->treecode_array[index] = 1;
        // clear highest bit
        ret->treecode_array[index-1] &= ~((treecode_128)1 << 127);
        ret->treecode_array[index-1] |= (treecode_128)l_or_r << 127;
        return ret;
    }
    a->treecode_array[index] = treecode128_append(a->treecode_array[index]);
    return a;
}

int main() {
    if (!test_nlz128()) {
        return 1;
    }
    if (!test_treecode_is_equal()) {
        return 1;
    }
    return 0;
}
