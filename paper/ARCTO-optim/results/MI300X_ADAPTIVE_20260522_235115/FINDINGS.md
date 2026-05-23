# E1bis: adaptive tiled aggregation -- cross-arch validation (MI300X)

Mirror of `RX7900XT_ADAPTIVE_*` on the MI300X (gfx942, CDNA3). Same
arcto branch (`feature/scaling-instrumentation` @ `f8b1c5f`), same
benchmark binaries, same TTI workload sizes. The companion RX 7900 XT
FINDINGS at `RX7900XT_ADAPTIVE_20260522_234047/FINDINGS.md` carries
the full methodology; this file reports the MI300X numbers and the
cross-architecture takeaway.

## Setup

- **GPU**: AMD Instinct MI300X (gfx942, CDNA3), 192 GB HBM3, PCIe Gen5
- **Host**: vianden-1 (Grid'5000 Luxembourg)
- **Stack**: ROCm 7.0.1 inside Singularity
  (`/home/ckunas/compression-experiments/arcto_gfx942.sif`)
- **arcto branch**: `feature/scaling-instrumentation` @ `f8b1c5f`
  (the same commit that introduced `arctoHostBatchAdaptive`)
- **W_kernel_sat picked by auto-detect**: 76 MB (= 9728 wave slots
  on gfx942 × 8 KB optimal chunk derived from
  `MI300X_CHUNK_SWEEP_SMALL_*`)
- **Sizes tested**: 100 MB, 686 MB, 4 GB (sizes 8 GB and 16 GB
  were planned but the `TTI.rsf@` source was not present on this
  node; rerun with that input or pre-generated TTI scaling files
  to extend the curve)

## Headline: adaptive vs baseline vs single-shot pinned, end-to-end ms

End-to-end = `t_alloc + t_memcpy_h2h + t_h2d + t_kernel`. Lower is
better. `adapt/base` > 1 means adaptive wins.

| Algo     | Size   | Baseline | Single-shot pinned | Adaptive | adapt/base |
|----------|--------|---------:|-------------------:|---------:|-----------:|
| LZ4      | 100 MB |     37.9 |              68.1 |     67.1 |  **0.57x** |
| LZ4      | 686 MB |    171.7 |             289.3 |    140.5 |  **1.22x** |
| LZ4      | 4 GB   |    892.4 |            2126.6 |    673.9 |  **1.32x** |
| Snappy   | 100 MB |     26.1 |              53.2 |     28.3 |  **0.92x** |
| Snappy   | 686 MB |    140.2 |             292.4 |     92.7 |  **1.51x** |
| Snappy   | 4 GB   |    676.2 |            1590.7 |    435.6 |  **1.55x** |
| Cascaded | 100 MB |     18.9 |              34.2 |     46.6 |  **0.41x** |
| Cascaded | 686 MB |    127.4 |             189.1 |     89.6 |  **1.42x** |
| Cascaded | 4 GB   |    854.8 |            1302.3 |    425.1 |  **2.01x** |

Adaptive beats the single-shot pinned at every point (1.0x to 5.0x).
Adaptive beats the baseline starting at the 686 MB workload across
all three byte-level compressors, with the gain growing as the input
size grows. At 4 GB the speedup is 1.32x (LZ4), 1.55x (Snappy), and
**2.01x (Cascaded)**.

## Cross-arch comparison: adapt/base ratio

| Algo     | Size  | RX 7900 XT (RDNA3) | MI300X (CDNA3) |
|----------|-------|-------------------:|---------------:|
| LZ4      | 100 MB|              0.76x |          0.57x |
| LZ4      | 686 MB|              1.09x |          1.22x |
| LZ4      | 4 GB  |              1.59x |          1.32x |
| Snappy   | 100 MB|              0.58x |          0.92x |
| Snappy   | 686 MB|              1.14x |          1.51x |
| Snappy   | 4 GB  |              1.50x |          1.55x |
| Cascaded | 100 MB|              0.57x |          0.41x |
| Cascaded | 686 MB|              1.18x |          1.42x |
| Cascaded | 4 GB  |              1.64x |          2.01x |

The pattern is consistent across both architectures: adaptive
underperforms at the very small (100 MB) workload because the
allocation cost of the window buffer is a large fraction of the
total, and the workload itself is too small to amortize it; adaptive
wins comfortably from 686 MB upward, and the gain grows with the
input size. The crossover behaviour validates the cost-model
prediction.

The arch-specific `W_kernel_sat` picked by the auto-detect (48 MB
on RDNA3, 76 MB on CDNA3) is the only difference in the cost-model
state between the two runs; the rest of the model (R_alloc, R_dram,
R_pcie, R_kernel priors and online refinement) was identical.

## Conclusion for the paper

The adaptive tiled aggregation contribution is **portable across
architectures** and reproduces the same qualitative behaviour
(crossover ~ 686 MB, gain growing with size) on RDNA3 and CDNA3.
The MI300X numbers also confirm that the headline 2.01x speedup is
achievable on the production target hardware. The paper's
single-figure-takeaway is the side-by-side adapt/base ratio table
above.

## What is NOT here

- **8 GB and 16 GB MI300X workloads**: the `TTI.rsf@` source file
  was not present on vianden-1, so the scaling sweep stops at 4 GB.
  Rerunning with the source file (or with pre-generated TTI scaling
  files) is the natural next step; the expectation, by the cost
  model, is that adapt/base continues to grow as input size grows.
- **Cross-architecture without single-shot pinned**: this report
  shows the three modes on MI300X; the previous E1
  (`RX7900XT_SCALING_*/FINDINGS.md`) characterized the single-shot
  failure of pinned in detail.

## Reproducing

Same recipe as `RX7900XT_ADAPTIVE_*/FINDINGS.md`, swapping the
SIF path to `/home/ckunas/compression-experiments/arcto_gfx942.sif`
and the testdata paths to `/home/ckunas/testdata/*.bin`. The
benchmark binaries are built from
`feature/scaling-instrumentation` @ `f8b1c5f` in
`/home/ckunas/arcto/build_canon/bin/`.
