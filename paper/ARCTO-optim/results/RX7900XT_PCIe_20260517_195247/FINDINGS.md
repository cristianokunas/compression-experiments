# PCIe transfer characterization on RX 7900 XT

Standalone (no compression involved) measurement to motivate the
generalization of the pinned-host optimization to all four compressors.
Two scripts (`pcie_bw.cu`, `pcie_chunked.cu`) are vendored alongside this
findings doc so the experiment is reproducible.

## What was measured

1. **Bulk transfer**: single `hipMemcpy` of a 100 MB / 686 MB buffer in each
   direction, pageable vs `hipHostMalloc`'d source.
2. **Chunked transfer**: 1600 × 64 KB `hipMemcpyAsync` calls totalling
   100 MB -- the exact access pattern of `benchmark_template_chunked.cuh`
   line 439-443 -- in four variants:
   - scattered pageable chunks (current behavior)
   - same but with one of the obvious half-fixes (pinned **dest** only)
   - one bulk `hipMemcpy` from a flat pageable buffer
   - one bulk `hipMemcpy` from a flat pinned buffer
   - 1600 × 64 KB slices INTO a single pinned allocation

## Headline numbers (RX 7900 XT, PCIe Gen4 x16, gfx1100)

| Variant                                           |   Time   | Throughput |
|---|---:|---:|
| **loop 1600 x 64KB scattered pageable** (current) | 16.6 ms  | **6.3 GB/s** |
| loop 1600 x 64KB sliced into one pinned alloc     | 15.2 ms  | 6.9 GB/s |
| single 100 MB pageable -> device                  |  6.4 ms  | 16.3 GB/s |
| **single 100 MB pinned -> device**                |  **3.9 ms** | **27.2 GB/s** |

Bulk single-call (100 MB / 686 MB), for reference:

|              | pageable | pinned |
|---|---:|---:|
| H2D (100 MB) | 14.2 GB/s | 27.0 GB/s |
| D2H (100 MB) | 14.4 GB/s | 28.5 GB/s |
| H2D (686 MB) | 16.5 GB/s | 27.6 GB/s |
| D2H (686 MB) | 16.7 GB/s | 28.2 GB/s |

## Three things this tells us

**1. Per-call overhead dominates the chunked pattern.** Sliced pinned
chunks (one pinned allocation, 1600 small `hipMemcpyAsync` calls into it)
runs at **6.9 GB/s**. That is only ~10% faster than the fully pageable
version. The PCIe link runs at 27 GB/s when used right; the chunked pattern
caps it at 6.3-6.9 regardless of how the host memory was allocated. The
limiter is the **launch overhead** of 1600 separate `hipMemcpyAsync` calls,
not bandwidth.

**2. Coalescing matters more than pinning for chunked APIs.** Going from
"1600 small pageable transfers" to "one bulk pageable transfer" is a
**2.6x speedup** (6.3 -> 16.3 GB/s); going from "one bulk pageable" to
"one bulk pinned" adds another **1.7x** (16.3 -> 27.2 GB/s). Combined,
coalesce+pin is a **4.3x speedup** end-to-end on the H2D path that
`benchmark_template_chunked.cuh` runs today.

**3. The optimization is not "use pinned memory."** The optimization is
"coalesce the chunked transfers into one (or a small number) of bulk
transfers, then make those bulk transfers pinned." The two fixes are
multiplicative and the per-chunk pinning that one would write first as
"the obvious thing" is a no-op without the coalescing.

## How this maps onto the existing benchmarks

The arcto chunked benchmark (`benchmark_template_chunked.cuh`) reports
"Transfer H2D (ms)" and "Transfer D2H (ms)" columns SEPARATELY from
compression/decompression throughput -- those columns are what we just
showed scales 4.3x. The "Compression throughput in GB/s" and
"Decompression throughput in GB/s" columns time only the device-resident
compute kernel and would NOT change from this optimization (LZ4 / Snappy /
Cascaded keep the compressed payload on the GPU during the timed loop).

So generalizing this to LZ4/Snappy/Cascaded:

- **Big win for end-to-end pipelines** (file -> device -> compress ->
  device -> uncompress -> device): the H2D + D2H columns drop dramatically
  and the "Total time (ms)" column drops correspondingly.
- **No change** for peak compress / decompress GB/s columns -- those are
  device-only.

ZFP is different in this respect: the canonical's HIP backend folds an
implicit D2H of the compressed payload into every `zfp_compress()` call,
so its compress GB/s column directly reflects host-buffer choice. That is
why the pinned-host fix on ZFP gave a +65% compression-throughput speedup
(`RX7900XT_ZFP_PINNED_20260517_193901/`) while the same fix on LZ4 would
only show up in the Transfer columns.

## What this implies for the ARCTO library design

The library could expose two thin helpers:

```c
arctoStatus_t arctoAllocHostPinned(void** ptr, size_t bytes);
arctoStatus_t arctoFreeHostPinned(void* ptr);
```

and document: "for best end-to-end throughput, allocate input buffers
with these helpers and prefer one bulk transfer over many chunked ones."

A heavier addition would be a host-side staging API:

```c
// Allocates a single pinned host buffer big enough to hold all chunks,
// returns per-chunk pointers backed by slices into that buffer. One
// bulk H2D then uploads everything to GPU at PCIe peak.
arctoStatus_t arctoBuildHostBatch(
    size_t batch_size, const size_t* chunk_sizes,
    void*** out_host_chunk_ptrs, void** out_pinned_storage);
```

That second helper is what would make a meaningful end-to-end difference
in any application that batches small inputs (the seismic checkpoint
case in Fletcher-IO, the typical RAM-to-disk staging case, etc.).

## Reproducing

The two source files are in this directory. Inside the SIF:

```bash
hipcc -O2 -o /tmp/pcie_bw      pcie_bw.cu
hipcc -O2 -o /tmp/pcie_chunked pcie_chunked.cu
/tmp/pcie_bw 104857600   # 100 MB
/tmp/pcie_bw 719323136   # 686 MB
/tmp/pcie_chunked        # 1600 x 64 KB on 100 MB
```

Raw output of one such run is captured in `raw_output.txt`.
