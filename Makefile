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

# Convert OTIO test files to TLA format with latest schema
# Uses Zig converter for full Timelines, Python converter as fallback for non-Timelines
convert-test-files: zig-out/bin/otio_dump_tla
	@echo "Converting OTIO files to TLA format in test_files/..."
	@success=0; failed=0; \
	for f in test_files/*.otio; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .otio); \
			echo "  Converting $$basename.otio -> $$basename.tla"; \
			if ./zig-out/bin/otio_dump_tla "$$f" "test_files/$${basename}.tla" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			elif python3 otio_to_ziggy.py "$$f" "test_files/$${basename}.tla" 2>&1 | grep -q "Converted"; then \
				echo "    (using Python fallback - no metadata support)"; \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo "Conversion complete: $$success succeeded, $$failed failed"

# Convert OpenTimelineIO sample files to TLA format using otio_dump_tla
# Output goes to otio_sample_data/ alongside source files
# Also copies the original .otio files for reference
convert-otio-samples: zig-out/bin/otio_dump_tla
	@echo "Converting OpenTimelineIO sample files to TLA format..."
	@if [ ! -d "../OpenTimelineIO/tests/sample_data" ]; then \
		echo "Error: ../OpenTimelineIO/tests/sample_data not found"; \
		echo "Please clone OpenTimelineIO to ../OpenTimelineIO"; \
		exit 1; \
	fi
	@mkdir -p otio_sample_data
	@echo "Copying original .otio files..."
	@copied=0; \
	for f in ../OpenTimelineIO/tests/sample_data/*.otio; do \
		if [ -f "$$f" ]; then \
			cp "$$f" otio_sample_data/; \
			copied=$$((copied + 1)); \
		fi \
	done; \
	echo "  Copied $$copied .otio files"
	@success=0; failed=0; \
	for f in ../OpenTimelineIO/tests/sample_data/*.otio; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .otio); \
			echo "  Converting $$basename.otio -> $$basename.tla"; \
			if ./zig-out/bin/otio_dump_tla "$$f" "otio_sample_data/$${basename}.tla" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo ""; \
	echo "Conversion complete: $$success succeeded, $$failed failed"; \
	ls -lh otio_sample_data/*.tla 2>/dev/null || true

convert-to-latest-schema: \
	convert-otio-samples \
	convert-test-files
	@echo "Converted all test files to latest schema."

# Convert TLA files to binary (.tlb) format
# Output goes alongside source files in the same directory
convert-to-binary: zig-out/bin/otiocat
	@echo "Converting TLA files to binary format..."
	@success=0; failed=0; \
	for f in otio_sample_data/*.tla; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .tla); \
			echo "  Converting $$basename.tla -> $$basename.tlb"; \
			if ./zig-out/bin/otiocat "$$f" "otio_sample_data/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	for f in test_files/*.tla; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .tla); \
			echo "  Converting $$basename.tla -> $$basename.tlb"; \
			if ./zig-out/bin/otiocat "$$f" "test_files/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo ""; \
	echo "Binary conversion complete: $$success succeeded, $$failed failed"

# Full conversion pipeline: OTIO -> TLA -> Binary
convert-all: convert-to-latest-schema convert-to-binary
	@echo "Full conversion pipeline complete."

# Verify round-trip consistency: tla -> binary -> tla
# The output of otiocat should be the same whether reading from tla or tlb
verify-roundtrip: zig-out/bin/otiocat
	@echo "Verifying round-trip consistency (tla -> binary -> tla)..."
	@mkdir -p /tmp/otio_roundtrip
	@success=0; failed=0; \
	for f in test_files/*.tla; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .tla); \
			tlb_file="test_files/$${basename}.tlb"; \
			if [ -f "$$tlb_file" ]; then \
				echo -n "  Checking $$basename... "; \
				./zig-out/bin/otiocat "$$f" "/tmp/otio_roundtrip/from_tla.tla" 2>/dev/null; \
				./zig-out/bin/otiocat "$$tlb_file" "/tmp/otio_roundtrip/from_tlb.tla" 2>/dev/null; \
				if diff -q "/tmp/otio_roundtrip/from_tla.tla" "/tmp/otio_roundtrip/from_tlb.tla" >/dev/null 2>&1; then \
					echo "OK"; \
					success=$$((success + 1)); \
				else \
					echo "MISMATCH"; \
					failed=$$((failed + 1)); \
				fi \
			fi \
		fi \
	done; \
	for f in otio_sample_data/*.tla; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .tla); \
			tlb_file="otio_sample_data/$${basename}.tlb"; \
			if [ -f "$$tlb_file" ]; then \
				echo -n "  Checking $$basename... "; \
				./zig-out/bin/otiocat "$$f" "/tmp/otio_roundtrip/from_tla.tla" 2>/dev/null; \
				./zig-out/bin/otiocat "$$tlb_file" "/tmp/otio_roundtrip/from_tlb.tla" 2>/dev/null; \
				if diff -q "/tmp/otio_roundtrip/from_tla.tla" "/tmp/otio_roundtrip/from_tlb.tla" >/dev/null 2>&1; then \
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

# Convert production test files (OTIO -> TLA -> TLB)
# Results stay in production_test_files/ directory
convert-production-files: zig-out/bin/otio_dump_tla zig-out/bin/otiocat
	@echo "Converting production test files..."
	@if [ ! -d "production_test_files" ]; then \
		echo "Warning: production_test_files/ not found (this is expected if you don't have the large test files)"; \
		exit 0; \
	fi
	@success=0; failed=0; \
	echo "Step 1: OTIO -> TLA"; \
	for f in production_test_files/*.otio; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .otio); \
			echo "  Converting $$basename.otio -> $$basename.tla"; \
			if ./zig-out/bin/otio_dump_tla "$$f" "production_test_files/$${basename}.tla" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo "Step 2: TLA -> TLB"; \
	for f in production_test_files/*.tla; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .tla); \
			echo "  Converting $$basename.tla -> $$basename.tlb"; \
			if ./zig-out/bin/otiocat "$$f" "production_test_files/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
				success=$$((success + 1)); \
			else \
				echo "    FAILED"; \
				failed=$$((failed + 1)); \
			fi \
		fi \
	done; \
	echo ""; \
	echo "Production file conversion complete: $$success succeeded, $$failed failed"; \
	ls -lh production_test_files/ 2>/dev/null || true

# Verify production file round-trips
verify-production-roundtrip: zig-out/bin/otiocat
	@echo "Verifying production file round-trip consistency..."
	@if [ ! -d "production_test_files" ]; then \
		echo "Warning: production_test_files/ not found"; \
		exit 0; \
	fi
	@mkdir -p /tmp/otio_prod_roundtrip
	@success=0; failed=0; \
	echo "Checking TLA vs TLB:"; \
	for f in production_test_files/*.tla; do \
		if [ -f "$$f" ]; then \
			basename=$$(basename "$$f" .tla); \
			tlb_file="production_test_files/$${basename}.tlb"; \
			if [ -f "$$tlb_file" ]; then \
				echo -n "  Checking $$basename (tlb)... "; \
				./zig-out/bin/otiocat "$$f" "/tmp/otio_prod_roundtrip/from_tla.tla" 2>/dev/null; \
				./zig-out/bin/otiocat "$$tlb_file" "/tmp/otio_prod_roundtrip/from_tlb.tla" 2>/dev/null; \
				if diff -q "/tmp/otio_prod_roundtrip/from_tla.tla" "/tmp/otio_prod_roundtrip/from_tlb.tla" >/dev/null 2>&1; then \
					echo "OK"; \
					success=$$((success + 1)); \
				else \
					echo "MISMATCH"; \
					failed=$$((failed + 1)); \
				fi \
			fi \
		fi \
	done; \
	rm -rf /tmp/otio_prod_roundtrip; \
	echo ""; \
	echo "Production round-trip verification: $$success matched, $$failed mismatched"

.PHONY: all run-em docs run_c convert-test-files convert-otio-samples convert-to-binary convert-all verify-roundtrip convert-production-files verify-production-roundtrip
