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
# Uses Zig converter for full Timelines, Python converter as fallback for non-Timelines
convert-test-files: zig-out/bin/otio_dump_ziggy
	@echo "Converting OTIO files to Ziggy format..."
	@mkdir -p test_files_ziggy
	@success=0; failed=0; \
	for f in test_files/*.otio; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .otio); \
			echo "  Converting $$basename.otio -> $$basename.ziggy"; \
			if ./zig-out/bin/otio_dump_ziggy "$$f" "test_files_ziggy/$${basename}.ziggy" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			elif python3 otio_to_ziggy.py "$$f" "test_files_ziggy/$${basename}.ziggy" 2>&1 | grep -q "Converted"; then \
				echo "    (using Python fallback - no metadata support)"; \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo "Conversion complete: $$success succeeded, $$failed failed"

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

# Convert Ziggy files to binary (.tlb) format
convert-to-binary: zig-out/bin/otiocat
	@echo "Converting Ziggy files to binary format..."
	@mkdir -p otio_sample_data_binary
	@mkdir -p test_files_binary
	@success=0; failed=0; \
	for f in otio_sample_data/*.ziggy; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .ziggy); \
			echo "  Converting $$basename.ziggy -> $$basename.tlb"; \
			if ./zig-out/bin/otiocat "$$f" "otio_sample_data_binary/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	for f in test_files_ziggy/*.ziggy; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .ziggy); \
			echo "  Converting $$basename.ziggy -> $$basename.tlb"; \
			if ./zig-out/bin/otiocat "$$f" "test_files_binary/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo ""; \
	echo "Binary conversion complete: $$success succeeded, $$failed failed"

# Full conversion pipeline: OTIO -> Ziggy -> Binary
convert-all: convert-to-latest-schema convert-to-binary
	@echo "Full conversion pipeline complete."

# Verify round-trip consistency: ziggy -> binary -> ziggy
# The output of otiocat should be the same whether reading from ziggy or tlb
verify-roundtrip: zig-out/bin/otiocat
	@echo "Verifying round-trip consistency (ziggy -> binary -> ziggy)..."
	@mkdir -p /tmp/otio_roundtrip
	@success=0; failed=0; \
	for f in test_files_ziggy/*.ziggy; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .ziggy); \
			tlb_file="test_files_binary/$${basename}.tlb"; \
			if [ -f "$$tlb_file" ]; then \
				echo -n "  Checking $$basename... "; \
				./zig-out/bin/otiocat "$$f" "/tmp/otio_roundtrip/from_ziggy.ziggy" 2>/dev/null; \
				./zig-out/bin/otiocat "$$tlb_file" "/tmp/otio_roundtrip/from_tlb.ziggy" 2>/dev/null; \
				if diff -q "/tmp/otio_roundtrip/from_ziggy.ziggy" "/tmp/otio_roundtrip/from_tlb.ziggy" >/dev/null 2>&1; then \
					echo "OK"; \
					success=$$((success + 1)); \
				else \
					echo "MISMATCH"; \
					failed=$$((failed + 1)); \
				fi \
			fi \
		fi \
	done; \
	for f in otio_sample_data/*.ziggy; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .ziggy); \
			tlb_file="otio_sample_data_binary/$${basename}.tlb"; \
			if [ -f "$$tlb_file" ]; then \
				echo -n "  Checking $$basename... "; \
				./zig-out/bin/otiocat "$$f" "/tmp/otio_roundtrip/from_ziggy.ziggy" 2>/dev/null; \
				./zig-out/bin/otiocat "$$tlb_file" "/tmp/otio_roundtrip/from_tlb.ziggy" 2>/dev/null; \
				if diff -q "/tmp/otio_roundtrip/from_ziggy.ziggy" "/tmp/otio_roundtrip/from_tlb.ziggy" >/dev/null 2>&1; then \
					echo "OK"; \
					success=$$((success + 1)); \
				else \
					echo "MISMATCH"; \
					failed=$$((failed + 1)); \
				fi \
			fi \
		fi \
	done; \
	rm -rf /tmp/otio_roundtrip; \
	echo ""; \
	echo "Round-trip verification: $$success matched, $$failed mismatched"

.PHONY: all run-em docs run_c convert-test-files convert-otio-samples convert-to-binary convert-all verify-roundtrip
