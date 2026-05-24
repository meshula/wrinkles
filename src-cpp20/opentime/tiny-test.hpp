#pragma once
#include <iostream>
#include <string>
#include <vector>
#include <functional>

namespace tinytest {

struct TestCase {
    std::string name;
    std::function<void()> fn;
};

inline std::vector<TestCase>& registry() {
    static std::vector<TestCase> tests;
    return tests;
}

struct Register {
    Register(const std::string& name, std::function<void()> fn) {
        registry().push_back({name, fn});
    }
};

inline int run_all() {
    int failures = 0;
    for (auto& test : registry()) {
        try {
            test.fn();
            std::cout << "✅ " << test.name << "\n";
        } catch (const std::exception& e) {
            std::cerr << "❌ " << test.name << " — exception: " << e.what() << "\n";
            ++failures;
        } catch (...) {
            std::cerr << "❌ " << test.name << " — unknown error\n";
            ++failures;
        }
    }
    std::cout << "\n" << (failures == 0 ? "All tests passed.\n" : "Failures: " + std::to_string(failures) + "\n");
    return failures;
}

} // namespace tinytest

#define TEST(name) \
    static void name(); \
    static tinytest::Register name##_reg(#name, name); \
    static void name()
