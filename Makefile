# Prepend test-filter string
ifdef TEST_FILTER
override TEST_FILTER:=--test-filter "$(TEST_FILTER)"
endif


all:
	zig build 

run-em:
	clear 
	zig build curvet-run -Dtarget=wasm32-emscripten

clean:
	rm -rf .zig-cache zig-out

# notes for lldb:
# to print all the variables in a frame:
# frame variable
# to print as binary:
# frame variable -f b
# to print as hex:
# frame variable -f x
# ; lldb $(mkfile_dir)otio_test.out -o run -o "frame variable -f b"

run_c:
	zig build 
	zig-out/bin/test_opentimelineio_c sample_otio_files/multiple_track.otio -v -m

docs:
	@zig build docs
	@echo "open: http://localhost:8000"
	@python -m http.server --directory zig-out/docs

.PHONY: all run-em docs run_c
