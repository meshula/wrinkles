#include "tiny_test.hpp"
#include "autodiff/forward/dual.hpp" // or your minimal autodiff header
#include <cassert>

using namespace autodiff;

// Simple forward mode test (replace with your own smoke tests)
TEST(ForwardDerivative) {
    dual x = 3.0;
    dual y = x * x + 2 * x + 1;
    double dydx = derivative([](dual x) { return x * x + 2 * x + 1; }, wrt(x), at(x = 3.0));
    assert(dydx == 8.0);
}

// Add more Zig-style tests easily
TEST(SineDerivative) {
    dual x = 0.0;
    double dydx = derivative(sin, wrt(x), at(x = 0.0));
    assert(std::abs(dydx - 1.0) < 1e-12);
}

int main() {
    return tinytest::run_all();
}
