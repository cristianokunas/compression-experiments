# MI300X cross-GPU validation -- ARCTO paper2 optimizations

First measurement of the pinned + coalesced H2D optimization on AMD's
MI300X (gfx942, CDNA3). Mirrors the RX 7900 XT snapshots so the two
architectures can be compared apples-to-apples: same arcto commit
(`8599fbf`), same TTI workload, same benchmark binaries.

Run on Grid5000 `vianden-1`, ROCm 7.0.1, PCIe Gen4 x16 (host link).
SIF built with `--mode sudo` directly on the node (~30 min build).

## TL;DR -- three headline findings

1. **Coalesce+pin gives EVEN BIGGER total-time speedups on MI300X than
   on RX 7900 XT** for the byte compressors. The MI300X kernels are
   faster, so the H2D was a larger fraction of total time, so fixing it
   helps proportionally more.
2. **The "pin" part is mostly arch-independent for the chunked pattern**:
   per-call launch overhead caps both GPUs at ~6.4 GB/s on the
   1600x64KB pattern regardless of pageable vs pinned source. But the
   "pin" part of *bulk* transfers is much smaller on MI300X (1.05x vs
   RX 7900 XT's 1.9x) because MI300X's pageable bulk path is already
   close to PCIe peak (~52 vs ~14 GB/s on RX 7900 XT).
3. **No compute regression on gfx942**: the ~13-iter cold-start tail
   triggered by `hipHostMalloc` on gfx1100 (root-caused in
   `RX7900XT_BYTE_PINNED_ROOTCAUSE_*/FINDINGS.md`) does NOT reproduce on
   MI300X. The persistent-batch fix added to the benchmark is still
   good practice but solves a RDNA3-specific issue.

## PCIe characterization (RX 7900 XT vs MI300X)

| Pattern (100 MB)                                | RX 7900 XT | MI300X | MI300X/RX |
|---|---:|---:|---:|
| H2D pageable, single bulk                       | 14.2 GB/s  | **52.4 GB/s** | 3.7x |
| H2D pinned, single bulk                         | 27.0 GB/s  | **55.1 GB/s** | 2.0x |
| pin/pageable ratio (bulk)                       | **1.90x**  | 1.05x         |       |
| H2D scattered 1600x64KB pageable (current bench)| 6.30 GB/s  | 6.35 GB/s     | 1.01x |
| H2D coalesced+pinned (this work)                | 27.18 GB/s | **55.06 GB/s**| 2.03x |
| coalesce+pin speedup over current bench         | **4.32x**  | **8.67x**     |       |

MI300X gets **8.7x** end-to-end H2D speedup from coalesce+pin vs the
RX 7900 XT's 4.3x -- because both effects (coalesce, pin) compound and
MI300X already has 3.7x faster pageable bulk to start with.

## Byte compressors -- medium TTI 100 MB

| Algo     | Mode      | Comp GB/s | Decomp GB/s | H2D ms | Total ms |
|---|---|---:|---:|---:|---:|
| LZ4      | pageable  | 4.83      | 70.94       | 25.48  | 71.32    |
| LZ4      | **pinned**| 4.81      | 71.41       | **1.96** | **25.61** |
| Snappy   | pageable  | 59.93     | 184.54      | 17.87  | 36.62    |
| Snappy   | **pinned**| 59.77     | 183.60      | **2.26** | **6.17**  |
| Cascaded | pageable  | 90.37     | 292.32      | 16.33  | 33.16    |
| Cascaded | **pinned**| 90.45     | 289.52      | **4.41** | **9.81**  |

| Algo     | Total-time speedup MI300X | (for reference: RX 7900 XT) |
|---|---:|---:|
| LZ4      | **2.79x**                 | 1.78x                       |
| Snappy   | **5.94x**                 | 2.60x                       |
| Cascaded | **3.38x**                 | 2.88x                       |

Compute throughput (compress, decompress GB/s) is **within 0.5%**
between pageable and pinned for all three algorithms -- the
hipHostMalloc cold-start observed on gfx1100 does not reproduce.

## Byte compressors -- large TTI 686 MB

| Algo     | Mode      | Comp GB/s | Decomp GB/s | H2D ms | Total ms |
|---|---|---:|---:|---:|---:|
| LZ4      | pageable  | 12.15     | 306.71      | 169.46 | 391.86   |
| LZ4      | **pinned**| 12.11     | 301.77      | 13.10  | **85.13** |
| Snappy   | pageable  | 83.85     | 297.50      | 111.75 | 228.32   |
| Snappy   | **pinned**| 80.49     | 298.49      | 13.98  | **36.42** |
| Cascaded | pageable  | 126.69    | 629.94      | 111.86 | 226.62   |
| Cascaded | **pinned**| 126.91    | 628.37      | 13.14  | **31.63** |

| Algo     | Total-time speedup MI300X large | (RX 7900 XT large) |
|---|---:|---:|
| LZ4      | **4.60x**                       | 2.02x              |
| Snappy   | **6.27x**                       | 2.90x              |
| Cascaded | **7.17x**                       | 3.38x              |

**Cascaded large at 7.2x is the headline number.** End-to-end pipeline
time (file -> device -> compress -> device -> decompress -> device)
drops from 227 ms to 32 ms on a 686 MB input. That is a real-world
checkpoint write-back budget collapsing by an order of magnitude on the
flagship AMD data-center GPU.

## ZFP medium TTI 100 MB

| Mode                 | Ratio | comp pageable | comp pinned | comp speedup | decomp pageable | decomp pinned | decomp speedup |
|---|---:|---:|---:|---:|---:|---:|---:|
| fixed_rate K=16      | 1.97  | 27.75 | **34.08** | +22.8%   | 34.86 | **45.88** | **+31.6%** |
| fixed_precision p=12 | 5.79  | 16.18 | 19.10     | +18%     | 41.86 | **59.78** | **+42.8%** |
| fixed_precision p=20 | 2.55  | 17.39 | 17.29     | noise    | 46.68 | 47.04     | noise      |
| fixed_accuracy 1e-3  | 21.65 | 20.35 | 20.34     | noise    | 79.90 | 80.75     | noise      |
| fixed_accuracy 1e-6  | 7.80  | 19.19 | 19.25     | noise    | 60.54 | 61.80     | noise      |

ZFP gains on MI300X are **smaller** than on RX 7900 XT (e.g.
fixed_rate K=16 comp: MI300X +22.8% vs RX 7900 XT +65%). Same mechanism
as the PCIe characterization shows: MI300X's pageable bulk is already
3.7x faster, so the canonical's internal D2H is already efficient. The
remaining win is the modest pin/pageable difference (~1.05x on bulk).

For variable-rate ZFP modes at high precision/accuracy, the kernel
itself is the bottleneck on MI300X and the H2D contribution is too
small to matter -- gains are in noise.

## What this means for the paper

The cross-GPU comparison rewrites the optimization story per algorithm
class:

| Algorithm        | RX 7900 XT (consumer)         | MI300X (data-center)            |
|---|---|---|
| ZFP `fixed_rate` | **+65% comp** (pin dominates)  | +23% comp (smaller win)         |
| ZFP variable     | +14-25% comp                   | mostly noise                    |
| LZ4 / Snappy / Cascaded | 1.8-3.4x total time     | **2.8-7.2x total time**         |

- On **consumer GPUs (RX 7900 XT, gfx1100)**: pinning the host buffer
  is the dominant fix for ZFP (because the canonical backend folds an
  implicit D2H into compress), and coalesce+pin gives 1.8-3.4x
  end-to-end on the byte compressors.
- On **data-center GPUs (MI300X, gfx942)**: pinning alone is barely
  detectable (PCIe path is already efficient), but coalescing the
  scattered chunks gives 2.8-7.2x end-to-end -- *more* than on RX 7900
  XT, because the kernels are fast enough that the unfixed H2D was the
  bottleneck.
- The **persistent-batch fix** for the hipHostMalloc cold-start was
  necessary on RDNA3 but is a no-op on CDNA3. Still good practice;
  arch-portable code.

This becomes a clean section in the paper: "Architecture-dependent
optimization: the same code-level fix gives qualitatively different
gains on consumer vs data-center AMD GPUs, because the underlying
bottleneck differs."

## Open question for the next experiment

MI50 (gfx906, GCN5) and MI210 (gfx90a, CDNA2) sit between these two
points architecturally. Do they pattern more like RX 7900 XT (pinning
matters a lot) or like MI300X (only coalescing matters)? That's the
4-GPU matrix that lands in the SBAC-PAD paper figure.

## Reproducing

Inside `arcto_gfx942.sif` on the node (built from arcto@8599fbf):

```bash
TD=/home/ckunas/testdata
SIF=/home/ckunas/compression-experiments/arcto_gfx942.sif

# ZFP example
singularity exec --rocm -B $TD:/data $SIF \
    /opt/arcto/build/bin/benchmark_zfp_single \
    -f /data/medium_TTI_100.bin -i 10 -w 2 \
    -m fixed_rate -r 16 -3 448,448,130 --device-buffer

# Byte compressors example
singularity exec --rocm -B $TD:/data $SIF \
    /opt/arcto/build/bin/benchmark_cascaded_chunked \
    -f /data/medium_TTI_100.bin -w 5 -i 30 -c true -P true
```

The full sweep script is preserved at
`/home/ckunas/mi300x_sweep.sh` on the node.

## Files in this directory

```
pcie_bw.cu, pcie_chunked.cu, pcie_raw.txt    -- standalone PCIe characterization
zfp_3d_<mode><param>_{medium,large}_TTI_{pageable,pinned}.log   (20 files)
{lz4,snappy,cascaded}_{medium,large}_TTI_{pageable,pinned}.log  (12 files)
```

Same CSV schema as the existing snapshots; direct apples-to-apples
comparison with `RX7900XT_BYTE_PINNED_ROOTCAUSE_*` and
`RX7900XT_ZFP_PINNED_*`.
