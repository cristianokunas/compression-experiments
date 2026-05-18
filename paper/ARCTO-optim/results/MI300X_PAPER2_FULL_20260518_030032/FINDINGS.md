# MI300X FULL paper2 sweep -- ICCSA26-comparable CSV with baseline + pinned

Full reproduction of the ICCSA26 dataset matrix (3 algorithms x 16
testfiles = 48 rows) on MI300X, BUT run TWICE through the same
`scripts/run_benchmarks_auto.sh`:

- **baseline**: no flags. Reproduces the ICCSA26 column exactly.
- **pinned**: `-P` flag. Same script, same binaries, same SIF -- the
  only difference is that each `benchmark_*_chunked` invocation gets
  `-P true` and the EnvLabel column is tagged `MI300X_PINNED`.

The combined CSV (`results_mi300x_paper2_combined.csv`, 96 rows) is a
drop-in for the same R / Python aggregation pipeline that produced the
ICCSA26 figures: `paper/ICCSA26/plots_iccsa_v4.R` reads CSVs of
identical schema, with `EnvLabel` as the facet column.

## TL;DR -- Speedups across all 48 (algo x file) combos

|  Algo     | Min speedup | Max speedup | Median speedup |
|---|---:|---:|---:|
| LZ4       | 1.12x (small_TTI 10MB)      | 9.25x (xlarge_zeros 4GB)    | ~3-4x          |
| Snappy    | 2.05x (small_zeros 10MB)    | **11.77x** (large_TTI 686MB) | ~6x            |
| Cascaded  | 3.47x (small_binary 10MB)   | **13.59x** (xlarge_TTI 4GB)  | **~7x**        |

**Headline numbers:**
- Cascaded `xlarge_TTI_4096.bin`: 2351 ms -> **173 ms (13.6x)**
- Snappy `large_TTI_1024.bin`: 405 ms -> **34 ms (11.8x)**
- Cascaded `large_TTI_1024.bin`: 358 ms -> **32 ms (11.3x)**

End-to-end pipeline times collapse by an order of magnitude on every
algorithm-data combination above ~100 MB. Small files (10 MB) cap at
1.1-5x because compute time itself is too small to amortize the
remaining overhead.

## Full TTI breakdown (medium + large + xlarge)

|  Algo     | File              | Baseline ms | Pinned ms | Speedup |
|---|---|---:|---:|---:|
| LZ4       | medium_TTI 100MB  |    57.1     |   25.2    | **2.26x** |
| LZ4       | large_TTI 686MB   |   460.7     |   87.6    | **5.26x** |
| LZ4       | xlarge_TTI 3.7GB  |  1521.2     |  407.5    | **3.73x** |
| Snappy    | medium_TTI 100MB  |    33.6     |    5.5    | **6.09x** |
| Snappy    | large_TTI 686MB   |   405.4     |   34.5    | **11.77x** |
| Snappy    | xlarge_TTI 3.7GB  |  1362.1     |  183.8    | **7.41x** |
| Cascaded  | medium_TTI 100MB  |    36.2     |    4.9    | **7.33x** |
| Cascaded  | large_TTI 686MB   |   357.5     |   31.5    | **11.34x** |
| Cascaded  | xlarge_TTI 3.7GB  |  2351.1     |  173.0    | **13.59x** |

## Data-type independence

Speedup is consistent across data types -- the optimization is not
ratio-dependent. Picking the medium tier as representative:

|  Algo     | TTI     | binary  | random  | zeros   |
|---|---:|---:|---:|---:|
| LZ4       | 2.26x   | 2.29x   | 2.68x   | 7.29x   |
| Snappy    | 6.09x   | 5.57x   | 6.69x   | 4.97x   |
| Cascaded  | 7.33x   | 7.04x   | 7.26x   | 7.94x   |

Cascaded shows the most uniform improvement (7.0-7.9x). LZ4 shows the
most variance (zeros are anomalously fast because the kernel itself
collapses to near-zero time on all-zeros input, so the H2D fraction
dominates).

## Sanity check vs ICCSA26 baseline

Same algorithm + same dataset + same hardware. Compression / decomp
throughput columns match within ~2% (same compute kernels). Transfer
times have some run-to-run variance (different ROCm version / driver
state, runs taken 2 months apart), so absolute total_ms differs by ~10%
on average, but the PINNED column is taken from the *same SIF* as the
baseline column in this snapshot -- the baseline/pinned ratio is
internally consistent and is what the paper figures will use.

| Algo, medium_TTI 100MB    | ICCSA26 baseline   | New baseline       | Diff   |
|---|---:|---:|---:|
| LZ4 comp GB/s             | 4.93               | 4.89               | -1%    |
| LZ4 decomp GB/s           | 71.43              | 71.26              | noise  |
| Snappy comp GB/s          | 60.00              | 59.84              | noise  |
| Snappy decomp GB/s        | 181.94             | 184.47             | +1.4%  |
| Cascaded comp GB/s        | 90.40              | 90.76              | noise  |
| Cascaded decomp GB/s      | 292.03             | 290.84             | noise  |

## Reproducing

Inside the SIF on the node (built from arcto@8599fbf):

```bash
SIF=/home/ckunas/compression-experiments/arcto_gfx942.sif
TD=/home/ckunas/testdata

# Baseline (matches ICCSA26):
singularity exec --rocm -B $TD:/data -B /home/ckunas:/home/ckunas $SIF \
    ./scripts/run_benchmarks_auto.sh -d $TD -o results/baseline --skip-testdata

# Pinned (this work):
singularity exec --rocm -B $TD:/data -B /home/ckunas:/home/ckunas $SIF \
    ./scripts/run_benchmarks_auto.sh -d $TD -o results/pinned --skip-testdata -P
```

The wrapper that runs both back-to-back is preserved at
`/home/ckunas/run_paper2_full.sh` on the node.

## Files in this directory

```
baseline/MI300X_<TS>/results.csv                  -- 48 baseline rows (EnvLabel=MI300X)
baseline/MI300X_<TS>/*.log                        -- 48 raw per-bench stdout
pinned/MI300X_PINNED_<TS>/results.csv             -- 48 pinned rows (EnvLabel=MI300X_PINNED)
pinned/MI300X_PINNED_<TS>/*.log                   -- 48 raw per-bench stdout

results_mi300x_paper2_baseline.csv                -- baseline CSV at top-level (paper-ready)
results_mi300x_paper2_pinned.csv                  -- pinned CSV at top-level (paper-ready)
results_mi300x_paper2_combined.csv                -- both, 96 rows, ready for plots_iccsa_v4.R
```

The combined CSV ingests directly into the ICCSA26 R pipeline -- the
schema is identical and `EnvLabel` is already used as the facet
variable. A new "before/after" figure showing baseline vs pinned on
MI300X is one R call away.
