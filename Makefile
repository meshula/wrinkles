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

# Convert OTIO test files to Ziggy format with latest schema
convert-test-files:
	@echo "Converting OTIO files to Ziggy format..."
	@mkdir -p test_files_ziggy
	@for f in test_files/*.otio; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .otio); \
			echo "  Converting $$basename.otio -> $$basename.ziggy"; \
			python3 otio_to_ziggy.py "$$f" "test_files_ziggy/$${basename}.ziggy"; \
		fi \
	done
	@echo "All files converted successfully!"

# Convert OpenTimelineIO sample files to Ziggy format using otio_dump_ziggy
convert-otio-samples: zig-out/bin/otio_dump_ziggy
	@echo "Converting OpenTimelineIO sample files..."
	@if [ ! -d "../OpenTimelineIO/tests/sample_data" ]; then \
		echo "Error: ../OpenTimelineIO/tests/sample_data not found"; \
		echo "Please clone OpenTimelineIO to ../OpenTimelineIO"; \
		exit 1; \
	fi
	@mkdir -p otio_sample_data
	@success=0; failed=0; \
	for f in ../OpenTimelineIO/tests/sample_data/*.otio; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .otio); \
			echo "  Converting $$basename.otio -> $$basename.ziggy"; \
			if ./zig-out/bin/otio_dump_ziggy "$$f" "otio_sample_data/$${basename}.ziggy" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo ""; \
	echo "Conversion complete: $$success succeeded, $$failed failed"; \
	ls -lh otio_sample_data

convert-to-latest-schema: \
	convert-otio-samples \
	convert-test-files
	@echo "Converted all test files to latest schema."

.PHONY: all run-em docs run_c convert-test-files convert-otio-samples
