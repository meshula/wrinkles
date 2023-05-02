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
	zig test -femit-bin=$(mkfile_dir)otio_test.out -freference-trace src/opentimelineio.zig $(TEST_FILTER)
	zig test -femit-bin=$(mkfile_dir)otio_test.out src/opentime/test_topology_projections.zig $(TEST_FILTER)
	zig test -femit-bin=$(mkfile_dir)otio_test.out src/opentime/opentime.zig $(TEST_FILTER)
	# zig build test

debug:
	lldb -o run -- $(mkfile_dir)otio_test.out $(shell readlink $(shell which zig))
