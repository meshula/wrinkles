# Performance Measurements

- **Generated:** 2026-11-26 08:52:59
- **Platform:** darwin
- **Build:** ReleaseFast
- **OTIO v1 baseline:** python otiocat
- **OTIO v1 version:** 0.17.0
- **Local test files:** `measure_performance.local.txt`

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

| File | Format | Size | Read Time |
|------|--------|------|-----------|
| production_1 | .otio | 18.20MB | 342.8ms |
| production_2 | .otio | 178.44MB | 2.33s |
| premiere_example | .otio | 112.0KB | 139.4ms |
| screening_example | .otio | 19.5KB | 138.5ms |

## Read Performance

Time to read and convert to TLA format (median of 5 runs).
"vs OTIO v1" is the speedup of the with-metadata read relative to
the python otiocat baseline above (higher is faster).

| File | Format | Size | With Metadata | Without Metadata | Speedup | vs OTIO v1 |
|------|--------|------|---------------|------------------|---------|------------|
| production_1 | .tla | 7.73MB | 30.1ms | 25.3ms | 1.19x | 11.40x |
| production_1 | .tlb | 4.10MB | 20.9ms | 18.0ms | 1.16x | 16.42x |
| production_2 | .tla | 80.78MB | 426.3ms | 166.5ms | 2.56x | 5.47x |
| production_2 | .tlb | 96.85MB | 288.3ms | 55.0ms | 5.24x | 8.09x |
| premiere_example | .tla | 27.0KB | 5.4ms | 5.1ms | 1.05x | 25.78x |
| premiere_example | .tlb | 34.8KB | 5.2ms | 5.3ms | 0.98x | 26.84x |
| screening_example | .tla | 7.9KB | 4.9ms | 5.0ms | 0.97x | 28.39x |
| screening_example | .tlb | 6.6KB | 5.2ms | 5.4ms | 0.96x | 26.71x |

## Write Performance

Time to write from TLA source (median of 5 runs).
"Target Size" is the size of the existing (with-metadata) target
file next to the source, if there is one.

| File | Target | Source Size | Target Size | With Metadata | Without Metadata | Speedup |
|------|--------|-------------|-------------|---------------|------------------|---------|
| production_1 | .tlb | 7.73MB | 4.10MB | 28.4ms | 25.3ms | 1.12x |
| production_2 | .tlb | 80.78MB | 96.85MB | 488.6ms | 174.8ms | 2.80x |
| premiere_example | .tlb | 27.0KB | 34.8KB | 5.9ms | 5.1ms | 1.14x |
| screening_example | .tlb | 7.9KB | 6.6KB | 4.8ms | 4.7ms | 1.04x |

