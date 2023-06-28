# Prepend test-filter string
ifdef TEST_FILTER
override TEST_FILTER:=--test-filter "$(TEST_FILTER)"
endif


all:
	zig build

# notes for lldb:
# to print all the variables in a frame:
# frame variable
# to print as binary:
# frame variable -f b
# to print as hex:
# frame variable -f x
# ; lldb $(mkfile_dir)otio_test.out -o run -o "frame variable -f b"

test:
	zig test -femit-bin=$(mkfile_dir)otio_test.out -freference-trace src/opentime/time_topology.zig $(TEST_FILTER)
	zig test -femit-bin=$(mkfile_dir)otio_test.out -freference-trace src/opentimelineio.zig $(TEST_FILTER)
	zig test -femit-bin=$(mkfile_dir)otio_test.out src/opentime/test_topology_projections.zig $(TEST_FILTER)
	zig test -femit-bin=$(mkfile_dir)otio_test.out src/opentime/opentime.zig $(TEST_FILTER)
	# for testing the hodographs
	# zig test src/test_hodograph.zig spline-gym/src/hodographs.c --pkg-begin opentime src/opentime/opentime.zig --pkg-end -Ispline-gym/src -femit-bin=otio_test.out --test-filter "s curve"
	# zig build test
	# new zig 0.11 syntax
	# zig test --mod opentime::src/opentime/opentime.zig --mod string_stuff::src/string_stuff.zig --mod otio_allocator::src/allocator.zig --deps opentime,string_stuff,otio_allocator src/curve/bezier_curve.zig -Ispline-gym/src spline-gym/src/hodographs.c

debug:
	lldb -o run -- $(mkfile_dir)otio_test.out $(shell readlink $(shell which zig))
