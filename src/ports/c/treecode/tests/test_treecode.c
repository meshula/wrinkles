// test_treecode.c - Tests for treecode functionality
// Ported from src/treecode/treecode.zig tests

#include "../treecode.h"
#include "../../opentime/tests/test_harness.h"

TEST(treecode_code_length_init_word) {
    Treecode tc;
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    struct test_case {
        TreecodeWord input;
        size_t expected;
    };

    struct test_case tests[] = {
        { 0x1,   0 },   // 0b1
        { 0x3,   1 },   // 0b11
        { 0xD,   3 },   // 0b1101
        { 0x7F,  6 },   // 0b1111111
        { 0x3B6, 9 },   // 0b1110110110
    };

    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        EXPECT_TRUE(treecode_init_word(&tc, alloc, tests[i].input));
        EXPECT_EQ(tests[i].expected, tc.code_length);
        treecode_deinit(&tc, alloc);
    }

    // Test a long path
    EXPECT_TRUE(treecode_init(&tc, alloc));
    size_t target_code_length = TREECODE_WORD_BIT_COUNT * 16;
    for (size_t i = 0; i < target_code_length; i++) {
        EXPECT_TRUE(treecode_append(&tc, alloc, TREECODE_LEFT));
    }
    EXPECT_EQ(target_code_length, tc.code_length);
    treecode_deinit(&tc, alloc);
}

TEST(treecode_word_append) {
    struct test_case {
        TreecodeWord expected;
        TreecodeWord input;
        Treecode_LorR branch;
    };

    struct test_case tests[] = {
        { 0x2, 0x1, TREECODE_LEFT },    // 0b10, 0b1
        { 0x3, 0x1, TREECODE_RIGHT },   // 0b11, 0b1
        { 0xD, 0x5, TREECODE_RIGHT },   // 0b1101, 0b101
        { 0x9, 0x5, TREECODE_LEFT },    // 0b1001, 0b101
    };

    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        TreecodeWord result = treecode_word_append(tests[i].input, tests[i].branch);
        EXPECT_EQ(tests[i].expected, result);
    }
}

TEST(treecode_append_lots_of_left) {
    Treecode tc;
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    EXPECT_TRUE(treecode_init(&tc, alloc));

    size_t bits = TREECODE_WORD_BIT_COUNT + 2;
    for (size_t i = 0; i < bits; i++) {
        EXPECT_TRUE(treecode_append(&tc, alloc, TREECODE_LEFT));
    }

    EXPECT_EQ(0x4, tc.words[1]);  // 0b100
    EXPECT_EQ(bits, tc.code_length);

    EXPECT_TRUE(treecode_append(&tc, alloc, TREECODE_LEFT));
    EXPECT_EQ(0x8, tc.words[1]);  // 0b1000
    EXPECT_EQ(bits + 1, tc.code_length);

    treecode_deinit(&tc, alloc);
}

TEST(treecode_append_lots_of_right) {
    Treecode tc;
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    EXPECT_TRUE(treecode_init(&tc, alloc));

    size_t bits = TREECODE_WORD_BIT_COUNT + 2;
    for (size_t i = 0; i < bits; i++) {
        EXPECT_TRUE(treecode_append(&tc, alloc, TREECODE_RIGHT));
    }

    EXPECT_EQ(0x7, tc.words[1]);   // 0b111
    EXPECT_EQ(bits, tc.code_length);

    EXPECT_TRUE(treecode_append(&tc, alloc, TREECODE_LEFT));
    EXPECT_EQ(0xB, tc.words[1]);   // 0b1011
    EXPECT_EQ(bits + 1, tc.code_length);

    treecode_deinit(&tc, alloc);
}

TEST(treecode_word_is_prefix) {
    struct test_case {
        TreecodeWord lhs;
        TreecodeWord rhs;
        bool expected;
    };

    struct test_case tests[] = {
        { 0x3,  0x0,   false },   // 0b11, 0b0
        { 0x0,  0x1,   false },   // 0b0, 0b01
        { 0x3,  0xD,   true  },   // 0b11, 0b1101
        { 0xD,  0xCD,  true  },   // 0b1101, 0b11001101
        { 0x1A, 0x19A, true  },   // 0b11010, 0b110011010
        { 0x19, 0xCD,  false },   // 0b11001, 0b11001101
    };

    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        bool result = treecode_word_is_prefix_of(tests[i].lhs, tests[i].rhs);
        EXPECT_EQ(tests[i].expected, result);
    }
}

TEST(treecode_is_prefix) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    struct test_case {
        TreecodeWord lhs_word;
        TreecodeWord rhs_word;
        bool expected;
    };

    struct test_case tests[] = {
        { TREECODE_MARKER, TREECODE_MARKER, true  },
        { 0x1,   0xD,   true  },   // 0b1, 0b1101
        { 0x2,   0x1,   false },   // 0b10, 0b1
        { 0x2,   0x3,   false },   // 0b10, 0b11
        { 0x3,   0x3,   true  },   // 0b11, 0b11
        { 0x3,   0x5,   true  },   // 0b11, 0b101
        { 0x6D,  0xD,   false },   // 0b1101101, 0b1101
        { 0xDA,  0x1A,  false },   // 0b11011010, 0b11010
        { 0xD,   0x6D,  true  },   // 0b1101, 0b1101101
        { 0x1A,  0xDA,  true  },   // 0b11010, 0b11011010
    };

    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        Treecode lhs, rhs;
        EXPECT_TRUE(treecode_init_word(&lhs, alloc, tests[i].lhs_word));
        EXPECT_TRUE(treecode_init_word(&rhs, alloc, tests[i].rhs_word));

        bool result = treecode_is_prefix_of(&lhs, &rhs);
        EXPECT_EQ(tests[i].expected, result);

        treecode_deinit(&lhs, alloc);
        treecode_deinit(&rhs, alloc);
    }
}

TEST(treecode_eql_positive) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    Treecode a, b;

    EXPECT_TRUE(treecode_init(&a, alloc));
    EXPECT_TRUE(treecode_init(&b, alloc));

    for (size_t i = 0; i < 100; i++) {
        EXPECT_TRUE(treecode_eql(&a, &b));
        Treecode_LorR next = (i % 5 == 0) ? TREECODE_LEFT : TREECODE_RIGHT;
        EXPECT_TRUE(treecode_append(&a, alloc, next));
        EXPECT_TRUE(treecode_append(&b, alloc, next));
    }

    EXPECT_TRUE(treecode_eql(&a, &b));

    treecode_deinit(&a, alloc);
    treecode_deinit(&b, alloc);
}

TEST(treecode_eql_negative) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    {
        Treecode tc_fst, tc_snd;
        EXPECT_TRUE(treecode_init_word(&tc_fst, alloc, 0xD));   // 0b1101
        EXPECT_TRUE(treecode_init_word(&tc_snd, alloc, 0xB));   // 0b1011

        EXPECT_FALSE(treecode_eql(&tc_fst, &tc_snd));
        EXPECT_FALSE(treecode_eql(&tc_snd, &tc_fst));

        treecode_deinit(&tc_fst, alloc);
        treecode_deinit(&tc_snd, alloc);
    }
}

TEST(treecode_clone) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    Treecode tc_src, tc_cln;

    EXPECT_TRUE(treecode_init(&tc_src, alloc));
    EXPECT_TRUE(treecode_clone(&tc_src, &tc_cln, alloc));

    // Pointers are different
    EXPECT_TRUE(tc_src.words != tc_cln.words);
    EXPECT_EQ(tc_src.word_capacity, tc_cln.word_capacity);
    EXPECT_TRUE(treecode_eql(&tc_src, &tc_cln));

    // Modify one
    EXPECT_TRUE(treecode_append(&tc_src, alloc, TREECODE_RIGHT));
    EXPECT_FALSE(treecode_eql(&tc_src, &tc_cln));

    treecode_deinit(&tc_src, alloc);
    treecode_deinit(&tc_cln, alloc);
}

TEST(treecode_hash) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;
    Treecode tc1, tc2;

    EXPECT_TRUE(treecode_init_word(&tc1, alloc, 0x5));  // 0b101
    EXPECT_TRUE(treecode_init_word(&tc2, alloc, 0x5));  // 0b101

    EXPECT_EQ(treecode_hash(&tc1), treecode_hash(&tc2));

    EXPECT_TRUE(treecode_append(&tc1, alloc, TREECODE_RIGHT));
    EXPECT_TRUE(treecode_append(&tc2, alloc, TREECODE_RIGHT));
    EXPECT_EQ(treecode_hash(&tc1), treecode_hash(&tc2));

    EXPECT_TRUE(treecode_append(&tc2, alloc, TREECODE_LEFT));
    EXPECT_TRUE(treecode_hash(&tc1) != treecode_hash(&tc2));

    treecode_deinit(&tc1, alloc);
    treecode_deinit(&tc2, alloc);
}

TEST(treecode_next_step_towards) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    struct test_case {
        TreecodeWord source;
        TreecodeWord dest;
        Treecode_LorR expected;
    };

    struct test_case tests[] = {
        { 0x3,   0x5,   TREECODE_LEFT  },   // 0b11, 0b101
        { 0x3,   0x7,   TREECODE_RIGHT },   // 0b11, 0b111
        { 0x2,   0x9C,  TREECODE_LEFT  },   // 0b10, 0b10011100
        { 0x2,   0xBE,  TREECODE_RIGHT },   // 0b10, 0b10111110
        { 0x5,   0xBD,  TREECODE_RIGHT },   // 0b101, 0b10111101
        { 0x5,   0xA9,  TREECODE_LEFT  },   // 0b101, 0b10101001
    };

    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        Treecode tc_src, tc_dst;
        EXPECT_TRUE(treecode_init_word(&tc_src, alloc, tests[i].source));
        EXPECT_TRUE(treecode_init_word(&tc_dst, alloc, tests[i].dest));

        Treecode_LorR result = treecode_next_step_towards(&tc_src, &tc_dst);
        EXPECT_EQ(tests[i].expected, result);

        treecode_deinit(&tc_src, alloc);
        treecode_deinit(&tc_dst, alloc);
    }
}

TEST(treecode_path_exists) {
    Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

    // Test cases: path should exist
    {
        Treecode fst, snd;
        EXPECT_TRUE(treecode_init_word(&fst, alloc, 0x5));   // 0b101
        EXPECT_TRUE(treecode_init_word(&snd, alloc, 0x1D));  // 0b11101

        EXPECT_TRUE(treecode_path_exists(&fst, &snd));

        treecode_deinit(&fst, alloc);
        treecode_deinit(&snd, alloc);
    }

    // Test cases: no path
    {
        Treecode fst, snd;
        EXPECT_TRUE(treecode_init_word(&fst, alloc, 0xD));   // 0b1101
        EXPECT_TRUE(treecode_init_word(&snd, alloc, 0xC));   // 0b1100

        EXPECT_FALSE(treecode_path_exists(&fst, &snd));

        treecode_deinit(&fst, alloc);
        treecode_deinit(&snd, alloc);
    }
}

OPENTIME_TEST_MAIN()
