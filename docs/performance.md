# Performance Measurements

Generated: 2026-11-26 08:46:38
Platform: darwin
Build: ReleaseFast
OTIO v1 baseline: python otiocat
OTIO v1 version: 0.17.0
Local test files: measure_performance.local.txt

## File Sizes

| File | Format | Total | Timeline Data | Metadata |
|------|--------|-------|---------------|----------|
| production_1 | .otio | 18.20MB | - | - |
| production_1 | .tla | 7.73MB | - | - |
| production_1 | .tlb | 4.10MB | 2.82MB | 1.27MB |
| production_2 | .otio | 178.44MB | - | - |
| production_2 | .tla | 80.78MB | - | - |
| production_2 | .tlb | 96.85MB | 8.07MB | 88.77MB |
| premiere_example | .otio | 112.0KB | - | - |
| premiere_example | .tla | 27.0KB | - | - |
| premiere_example | .tlb | 34.8KB | 5.0KB | 29.7KB |
| screening_example | .otio | 19.5KB | - | - |
| screening_example | .tla | 7.9KB | - | - |
| screening_example | .tlb | 6.6KB | 2.5KB | 4.1KB |

## Baseline Read Performance (OTIO v1, python)

Time for `otiocat <file>.otio > /dev/null` (median of 5 runs).

| File | Format | Read Time |
|------|--------|-----------|
| production_1 | .otio | 337.6ms |
| production_2 | .otio | 2.28s |
| premiere_example | .otio | 137.8ms |
| screening_example | .otio | 136.7ms |

## Read Performance

Time to read and convert to TLA format (median of 5 runs).
"vs OTIO v1" is the speedup of the with-metadata read relative to
the python otiocat baseline above (higher is faster).

| File | Format | With Metadata | Without Metadata | Speedup | vs OTIO v1 |
|------|--------|---------------|------------------|---------|------------|
| production_1 | .tla | 28.7ms | 25.6ms | 1.12x | 11.77x |
| production_1 | .tlb | 21.0ms | 17.5ms | 1.19x | 16.11x |
| production_2 | .tla | 417.1ms | 163.3ms | 2.55x | 5.46x |
| production_2 | .tlb | 287.9ms | 54.2ms | 5.32x | 7.92x |
| premiere_example | .tla | 5.0ms | 4.9ms | 1.02x | 27.59x |
| premiere_example | .tlb | 4.7ms | 4.7ms | 1.00x | 29.08x |
| screening_example | .tla | 4.8ms | 4.8ms | 1.00x | 28.61x |
| screening_example | .tlb | 5.1ms | 4.9ms | 1.04x | 27.04x |

## Write Performance

Time to write from TLA source (median of 5 runs).

| File | Target | With Metadata | Without Metadata | Speedup |
|------|--------|---------------|------------------|---------|
| production_1 | .tlb | 28.0ms | 25.1ms | 1.11x |
| production_2 | .tlb | 492.8ms | 172.4ms | 2.86x |
| premiere_example | .tlb | 5.1ms | 5.1ms | 1.00x |
| screening_example | .tlb | 5.5ms | 4.7ms | 1.17x |

