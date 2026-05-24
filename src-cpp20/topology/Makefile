# --- Configuration ---
# Use g++ as the compiler driver for C++ code
CXX = g++
# Standard flags: C++20 standard, plus useful warnings
# Include parent directory for access to opentime, curve, treecode
CXXFLAGS = -std=c++20 -Wall -Wextra -I..

# --- Executable Definitions ---

# List of all test source files
TEST_SRCS = \
    test-mapping-empty.cpp \
    test-mapping-affine.cpp \
    test-mapping-curve-linear.cpp \
    test-mapping.cpp \
    test-topology.cpp

# List of all resulting executable names (by replacing .cpp with nothing)
TEST_EXES = $(patsubst %.cpp, %, $(TEST_SRCS))

# --- Targets ---

# Default target: builds all test executables
all: $(TEST_EXES)
.PHONY: all

# Target to run all tests
tests: all
	@echo "--- Running All Topology Tests ---"
	@for exe in $(TEST_EXES); do \
		echo "Running $$exe..."; \
		./$$exe; \
	done
.PHONY: tests

# Pattern Rule for compilation

# This rule tells make how to build an executable ($@) from a C++ source file ($<)
# It ensures any missing executable is built before being run by the 'tests' target.
%: %.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

# Clean up built executables
clean:
	@echo "Cleaning up executables..."
	rm -f $(TEST_EXES) a.out
.PHONY: clean
