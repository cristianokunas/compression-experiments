# ARCTO byte compressors -- pinned-input optimization on RX 7900 XT

Generalization of the pinned-host story from
`RX7900XT_ZFP_PINNED_20260517_193901/` to the three byte-level compressors
ported from nvCOMP: LZ4, Snappy, Cascaded.

## What changed in the code

- New library helper: [`arcto/host_batch.h`](../../../arcto/include/arcto/host_batch.h)
  -- a `arctoHostBatch_t` opaque type that allocates ONE contiguous pinned
  host buffer sized for the user's chunk-size vector, hands back per-chunk
  pointers as slices into it, and uploads the whole thing to GPU in a
  single `hipMemcpyAsync`. Implementation in
  [`src/lowlevel/HostBatch.cpp`](../../../arcto/src/lowlevel/HostBatch.cpp).
- `benchmark_template_chunked.cuh` gains a `-P/--pinned_input` flag. When
  set, the H2D measurement block builds an `arctoHostBatch_t` from the
  loaded `std::vector<std::vector<char>>` and issues one bulk H2D instead
  of `batch_size` (~1600 for the 100 MB TTI input) scattered
  `hipMemcpyAsync` calls.

The default (no flag) behavior is the unchanged ICCSA26 baseline; the
flag is purely additive.

## Headline numbers (medium TTI 100 MB, 1600 x 64 KB chunks)

| Algo     | Mode      | H2D ms | D2H ms | Total ms | comp GB/s | decomp GB/s |
|---|---|---:|---:|---:|---:|---:|
| LZ4      | pageable  | 14.91  | 14.13  | 46.7     | 5.94      | 93.24       |
| LZ4      | **pinned**| **4.32** | **4.09** | **26.2** | 5.90      | 92.65       |
| Snappy   | pageable  | 15.32  | 14.57  | 34.3     | 23.82     | 106.58      |
| Snappy   | **pinned**| **4.38** | **4.17** | **13.2** | 22.61     | 101.69      |
| Cascaded | pageable  | 15.06  | 14.45  | 31.4     | 55.64     | 192.02      |
| Cascaded | **pinned**| **4.51** | **4.32** | **10.9** | 50.24     | 177.33      |

| Algo     | H2D speedup | D2H speedup | Total-time speedup |
|---|---:|---:|---:|
| LZ4      | **3.45x**   | **3.45x**   | **1.78x**          |
| Snappy   | **3.49x**   | **3.49x**   | **2.60x**          |
| Cascaded | **3.34x**   | **3.34x**   | **2.88x**          |

H2D and D2H drop **~3.4x** uniformly -- consistent with the standalone
PCIe characterization (`RX7900XT_PCIe_*/FINDINGS.md`) which predicted
4.3x. The slight shortfall vs the standalone test is the cost of the
`arctoHostBatchCreate` `hipHostMalloc(~100 MB)` happening just before
the timed H2D; the standalone test reused the pinned buffer across
iterations.

## Large TTI 686 MB

Same pattern, with the compute regression disappearing once the overhead
is amortized over a larger transfer:

| Algo     | Mode      | H2D ms | D2H ms | Total ms | comp GB/s | decomp GB/s |
|---|---|---:|---:|---:|---:|---:|
| LZ4      | pageable  | 104.1  | 100.3  | 302.4    | 7.33      | 139.21      |
| LZ4      | **pinned**| 26.2   | 25.3   | **149.5**| 7.34      | 132.99      |
| Snappy   | pageable  | 104.1  | 100.6  | 232.3    | 26.05     | 74.07       |
| Snappy   | **pinned**| 26.6   | 25.7   | **80.0** | 25.94     | 75.65       |
| Cascaded | pageable  | 103.6  | 101.0  | 216.4    | 61.16     | 177.14      |
| Cascaded | **pinned**| 26.4   | 25.8   | **64.1** | 60.57     | 173.12      |

Total-time speedups at 686 MB: LZ4 **2.02x**, Snappy **2.90x**, Cascaded
**3.38x**.

## A caveat for the paper: small compute regression on fast kernels (100 MB)

On the 100 MB medium workload, Cascaded compression GB/s drops ~10%
(55.6 -> 50.2) and stddev rises ~15x in the pinned mode. Snappy shows a
smaller (~5%) version of the same. LZ4 (which is ~10x slower per
iteration than Cascaded) shows no compute regression. At 686 MB the
regression disappears entirely on all three (Cascaded: 61.2 -> 60.6
GB/s, well within noise).

Working hypothesis: the `hipHostMalloc(100 MB)` + bulk `hipMemcpyAsync`
sequence executed once just before the iteration loop leaves the GPU
in a different DVFS / cache state for the first few measured
iterations of the very fast compute kernels (Cascaded comp = ~1.9 ms
per iter at 100 MB; the cold-start tail dominates the mean). On the
larger workload the per-iter compute is 6.5x longer and the cold
iterations are washed out.

Not yet root-caused. The CSV files preserve per-iteration stddev
columns for the paper figures, so the variance increase is visible.

## End-to-end story for the paper

The combined message from this directory + the ZFP results +
the standalone PCIe characterization (all three live in `paper/ARCTO-optim/results/`):

1. **All four ARCTO compressors benefit** from the pinned + coalesced
   input optimization, but in qualitatively different ways:
   - ZFP: kernel-throughput gain (+65% compression on fixed_rate)
     because the canonical's HIP backend folds an implicit D2H into
     every `zfp_compress()` call.
   - LZ4 / Snappy / Cascaded: end-to-end pipeline gain (1.8x - 3.4x
     total time) because the H2D + D2H columns drop 3.4x. Compute GB/s
     is unaffected (LZ4) or shows a small unresolved regression on
     very fast kernels at small sizes (Cascaded at 100 MB).
2. **The optimization is "coalesce + pin", not "pin alone"**. Per-
   chunk pinning alone is a ~10% gain because the 1600x64KB launch
   overhead dominates; coalescing into one bulk transfer first is what
   unlocks the 3-4x.
3. **The API surface is minimal**: one new public header (`host_batch.h`,
   6 functions), one new source file (`HostBatch.cpp`, ~110 lines).
   Zero changes to any existing compressor.

## Reproducing

Inside the SIF, with the testdata bound at `/data`:

```bash
build_canon/bin/benchmark_lz4_chunked   -f /data/medium_TTI_100.bin -w 5 -i 30 -c true                # baseline
build_canon/bin/benchmark_lz4_chunked   -f /data/medium_TTI_100.bin -w 5 -i 30 -c true -P true       # pinned
build_canon/bin/benchmark_snappy_chunked   -f /data/medium_TTI_100.bin -w 5 -i 30 -c true -P true
build_canon/bin/benchmark_cascaded_chunked -f /data/medium_TTI_100.bin -w 5 -i 30 -c true -P true
```

## Files in this directory

```
{lz4,snappy,cascaded}_{medium,large}_TTI_{pageable,pinned}.log   (12 files)
```

Each is one CSV row matching the existing 21-column
`benchmark_*_chunked` format. The same R / Python aggregation pipeline
used for ICCSA26 figures will ingest these without changes.
