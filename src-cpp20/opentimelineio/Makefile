# OpenTimelineIO C++20 Implementation Makefile

CXX = clang++
CXXFLAGS = -std=c++20 -Wall -Wextra -I.. -I../../libs/rapidjson/include
LDFLAGS =

# Targets
TEST_SCHEMA = test-schema
TEST_JSON = test-json
TEST_TEMPORAL = test-temporal

all: $(TEST_SCHEMA) $(TEST_JSON) $(TEST_TEMPORAL)

# Test schema types
$(TEST_SCHEMA): test-schema.cpp schema.hpp core.hpp ../topology/topology.hpp ../opentime/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ test-schema.cpp $(LDFLAGS)

# Test JSON serialization
$(TEST_JSON): test-json.cpp json.hpp schema.hpp core.hpp ../topology/topology.hpp ../opentime/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ test-json.cpp $(LDFLAGS)

# Test temporal hierarchy
$(TEST_TEMPORAL): test-temporal.cpp temporal_hierarchy.hpp schema.hpp core.hpp ../topology/topology.hpp ../opentime/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ test-temporal.cpp $(LDFLAGS)

# Run tests
test: $(TEST_SCHEMA) $(TEST_JSON) $(TEST_TEMPORAL)
	./$(TEST_SCHEMA)
	./$(TEST_JSON)
	./$(TEST_TEMPORAL)

# Clean
clean:
	rm -f $(TEST_SCHEMA) $(TEST_JSON) $(TEST_TEMPORAL)

.PHONY: all test clean
