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

# Convert OTIO files to TLA format
convert-to-tla: zig-out/bin/otiocat
	@echo "Converting OTIO files to TLA format..."
	@success=0; failed=0; \
	for dir in test_files otio_sample_data production_test_files; do \
		if [ -d "$$dir" ]; then \
			for f in $$dir/*.otio; do \
				if [ -f "$$f" ]; then \
					basename=$$(basename "$$f" .otio); \
					echo "  $$basename.otio -> $$basename.tla"; \
					if ./zig-out/bin/otiocat "$$f" "$$dir/$${basename}.tla" 2>&1 | grep -q "Wrote:"; then \
						success=$$((success + 1)); \
					else \
						echo "    FAILED"; \
						failed=$$((failed + 1)); \
					fi \
				fi \
			done \
		fi \
	done; \
	echo "TLA conversion: $$success succeeded, $$failed failed"

# Convert TLA files to binary TLB format
convert-to-tlb: zig-out/bin/otiocat
	@echo "Converting TLA files to TLB format..."
	@success=0; failed=0; \
	for dir in test_files otio_sample_data production_test_files; do \
		if [ -d "$$dir" ]; then \
			for f in $$dir/*.tla; do \
				if [ -f "$$f" ]; then \
					basename=$$(basename "$$f" .tla); \
					echo "  $$basename.tla -> $$basename.tlb"; \
					if ./zig-out/bin/otiocat "$$f" "$$dir/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
						success=$$((success + 1)); \
					else \
						echo "    FAILED"; \
						failed=$$((failed + 1)); \
					fi \
				fi \
			done \
		fi \
	done; \
	echo "TLB conversion: $$success succeeded, $$failed failed"

# Direct OTIO to TLB conversion (skips intermediate TLA)
convert-otio-to-tlb: zig-out/bin/otiocat
	@echo "Converting OTIO files directly to TLB format..."
	@success=0; failed=0; \
	for dir in test_files otio_sample_data production_test_files; do \
		if [ -d "$$dir" ]; then \
			for f in $$dir/*.otio; do \
				if [ -f "$$f" ]; then \
					basename=$$(basename "$$f" .otio); \
					echo "  $$basename.otio -> $$basename.tlb"; \
					if ./zig-out/bin/otiocat "$$f" "$$dir/$${basename}.tlb" 2>&1 | grep -q "Wrote:"; then \
						success=$$((success + 1)); \
					else \
						echo "    FAILED"; \
						failed=$$((failed + 1)); \
					fi \
				fi \
			done \
		fi \
	done; \
	echo "Direct TLB conversion: $$success succeeded, $$failed failed"

# Copy OpenTimelineIO sample files (if available)
copy-otio-samples:
	@if [ -d "../OpenTimelineIO/tests/sample_data" ]; then \
		mkdir -p otio_sample_data; \
		echo "Copying OTIO sample files..."; \
		cp ../OpenTimelineIO/tests/sample_data/*.otio otio_sample_data/ 2>/dev/null || true; \
		echo "  Copied $$(ls otio_sample_data/*.otio 2>/dev/null | wc -l | tr -d ' ') files"; \
	else \
		echo "Note: ../OpenTimelineIO not found, skipping sample copy"; \
	fi

# Full conversion pipeline: copy samples, then OTIO -> TLA -> TLB
convert-all: copy-otio-samples convert-to-tla convert-to-tlb
	@echo "Full conversion pipeline complete."

# Verify round-trip consistency (tla <-> tlb)
verify-roundtrip: zig-out/bin/otiocat
	@echo "Verifying round-trip consistency..."
	@mkdir -p /tmp/otio_roundtrip
	@success=0; failed=0; \
	for dir in test_files otio_sample_data production_test_files; do \
		if [ -d "$$dir" ]; then \
			for f in $$dir/*.tla; do \
				if [ -f "$$f" ]; then \
					basename=$$(basename "$$f" .tla); \
					tlb_file="$$dir/$${basename}.tlb"; \
					if [ -f "$$tlb_file" ]; then \
						printf "  %s... " "$$basename"; \
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
			done \
		fi \
	done; \
	rm -rf /tmp/otio_roundtrip; \
	echo "Round-trip: $$success matched, $$failed mismatched"

# use git-of-theseus to analyze the repo
analyze:
	git-of-theseus-analyze . --ignore-whitespace --cohortfm "%Y-%m" --only "src/*"
	git-of-theseus-stack-plot cohorts.json
	git-of-theseus-survival-plot survival.json
	git-of-theseus-line-plot authors.json


.PHONY: \
	all \
	run-em \
	docs \
	run_c \
	convert-to-tla \
	convert-to-tlb \
	convert-otio-to-tlb \
	copy-otio-samples \
	convert-all \
	verify-roundtrip \
	analyze
