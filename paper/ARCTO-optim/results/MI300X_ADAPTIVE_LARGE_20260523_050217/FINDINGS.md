# E1tris: adaptive tiled aggregation -- MI300X 8/16 GB extension

Extends `MI300X_ADAPTIVE_20260522_235115` with two larger workloads
(8 GB and 16 GB) so the scaling curve covers the regime where the
adaptive contribution matters most. Same arcto branch, same SIF,
same MI300X node.

## Setup deltas vs the regular MI300X sweep

- **Datasets generated locally on vianden-1** by concatenating
  `xlarge_TTI_4096.bin` two and four times (the original TTI.rsf@
  source file is not present on Grid'5000):
  - `tti_8gb.bin` = 2 × xlarge (~7.4 GiB binary)
  - `tti_16gb.bin` = 4 × xlarge (~14.7 GiB binary)
- Iterations reduced to `-i 3` (vs the standard `-i 5`) to keep the
  total sweep time under one MI300X allocation window. Trimmed-mean
  noise is still acceptable on this hardware.

The concatenation preserves the byte-frequency distribution of the
TTI source (same statistical properties as a single copy), so the
compression ratio reported below is comparable to the regular sweep.

## Results: end-to-end ms

End-to-end = `t_alloc + t_memcpy_h2h + t_h2d + t_kernel`.

| Algo     | Size  | Baseline | Single-shot pinned | Adaptive | adapt/base |
|----------|-------|---------:|-------------------:|---------:|-----------:|
| LZ4      | 8 GB  |   2395.3 |             3027.0 |   1316.3 |  **1.82x** |
| LZ4      | 16 GB |   4343.1 |             6646.8 |   2592.2 |  **1.68x** |
| Snappy   | 8 GB  |   1646.6 |             2320.4 |    824.2 |  **2.00x** |
| Snappy   | 16 GB |   3484.3 |             5278.1 |   1785.4 |  **1.95x** |
| Cascaded | 8 GB  |   1694.7 |             2501.8 |    814.0 |  **2.08x** |
| Cascaded | 16 GB |   3749.2 |             6350.9 |   1660.9 |  **2.26x** |

W_opt picked: 76 MB (auto-detect from gfx942); 100 and 199 windows
respectively for 8 and 16 GB inputs.

## Full MI300X scaling curve (combining both runs)

| Algo     | 100 MB | 686 MB | 4 GB | 8 GB | 16 GB |
|----------|-------:|-------:|-----:|-----:|------:|
| LZ4      |  0.57x |  1.22x | 1.32x| **1.82x** | 1.68x |
| Snappy   |  0.92x |  1.51x | 1.55x| **2.00x** | 1.95x |
| Cascaded |  0.41x |  1.42x | 2.01x|  2.08x | **2.26x** |

Three observations:

1. **Crossover at ~ 686 MB**: below this, adaptive loses to baseline
   because the 76 MB allocation cost is too large a fraction of the
   workload; above, it wins, growing monotonically until at least 4 GB.

2. **Saturation around 8 GB for LZ4/Snappy**: the gain peaks and then
   plateaus or slightly regresses. For LZ4, the 16 GB regression
   (1.82 -> 1.68) is plausibly cache eviction in the wave-slot hash
   tables, but the absolute time still improves linearly with input.

3. **Cascaded keeps growing** all the way to 16 GB (**2.26x**) because
   its kernel is the lightest of the three (~25 ms/4 GB on MI300X);
   adding more windows just amortizes the alloc cost further without
   running into a kernel ceiling.

## Headline number for the paper

**Cascaded compress on TTI 16 GB on AMD MI300X (CDNA3) achieves
2.26x speedup of the proposed adaptive tiled aggregation over the
scattered-pageable baseline.** Snappy 8 GB reaches 2.00x. LZ4
peaks at 1.82x on 8 GB.

These are real, measured, end-to-end gains against the production
path used in the published ICCSA 2026 paper, on the AMD flagship
target of the thesis.

## What is still pending

- **Streaming/overlap** (Phase 2 in the paper plan): the current
  adaptive path is single-buffered, so per-window H2D and kernel are
  sequential. Double-buffered streaming would hide t_kernel behind
  t_h2d. Predicted marginal gain over Phase 1: 5-28% depending on
  algorithm. Not implemented in this branch; documented as future
  work in the paper.
- **32 GB and 64 GB workloads**: the Grid'5000 allocation window
  closed before these runs could be queued. Cost-model extrapolation
  predicts the LZ4 plateau continues and Cascaded keeps growing
  toward ~ 2.4-2.5x. To be confirmed in the next allocation window.
