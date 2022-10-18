all:
	zig build

test:
	zig test -femit-bin=$(mkfile_dir)otio_test.out src/opentime/opentime.zig
	# zig build test

debug:
	lldb -o run -- $(mkfile_dir)otio_test.out $(shell readlink $(shell which zig))
