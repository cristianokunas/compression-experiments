# E1: input-size scaling sweep on RX 7900 XT

First measurement campaign for the dynamic-aggregation contribution of the
SBAC-PAD'26 paper. The goal is to characterize how the existing
single-shot `arctoHostBatch` optimization scales as the input grows from
the published ICCSA size range (up to 686 MB TTI) into the GB regime.

Run on `lunaris` (PCAD), RX 7900 XT (gfx1100, RDNA3), inside
`arcto_gfx1100_v3.sif` (ROCm 7.0.1). The benchmark binaries are from a
local build of `feature/scaling-instrumentation` (arcto@`8c4bae4`), with
the new `--report_phases` flag that desaggregates the host-side prep
into `t_alloc_ms`, `t_memcpy_h2h_ms`, and `peak_pinned_bytes`. See the
`_arcto_*.txt` and `_sif_sha256.txt` files in this directory for the
exact provenance.

## Setup

- **GPU**: AMD RX 7900 XT (gfx1100), 20 GB GDDR6, PCIe Gen4 x16
- **Host**: lunaris (Threadripper PRO 5965WX, 256 GB DDR4)
- **Stack**: ROCm 7.0.1 inside Singularity (`arcto_gfx1100_v3.sif`)
- **arcto**: branch `feature/scaling-instrumentation` @ `8c4bae4`,
  built locally and linked via `LD_LIBRARY_PATH`
- **Inputs**: TTI workload at 100 MB, 686 MB, 2 GB, 4 GB (truncated from
  `/ssd/cakunas/fletcher-io/original/run/large/TTI.rsf@`, the 67.3 GB
  TTI seismic wavefield from the large Fletcher run)
- **Algorithms**: LZ4, Snappy, Cascaded (the three byte-level
  compressors from the ICCSA paper)
- **Modes**: baseline (scattered pageable, current ICCSA path) and
  pinned (`--pinned_input=true`, current single-shot `arctoHostBatch`)
- **Protocol**: `-w 1 -i 5` (1 warmup, 5 timed iters); each (algo,
  size, mode) is a separate process invocation, so the pinned allocation
  cost is paid fresh each time (rather than amortized across the warmup
  by the static cache in the benchmark template)

## TL;DR

**The single-shot pinned-host optimization, when measured honestly against
its full lifecycle cost (alloc + h2h memcpy + h2d), is SLOWER than the
scattered-pageable baseline at every input size from 100 MB to 4 GB.**

The host-side preparation cost (`hipHostMalloc` + pageable->pinned
memcpy) dominates the end-to-end cost, accounting for 60-88% of the
total in the pinned path. The H2D bandwidth gain that the pinned path
provides (typically 3-4x on the bulk transfer alone) is overwhelmed by
the host-side prep that must happen first.

This is a **stronger result than expected** and reshapes the paper2
narrative. The existing "4.3x H2D speedup" claim (from
`RX7900XT_PCIe_*/FINDINGS.md` and `RX7900XT_BYTE_PINNED_*/FINDINGS.md`)
is correct *only when the pinned batch is reused across many calls*,
which the previous benchmark template did via a process-lifetime static
cache that paid the alloc once on warmup. The honest single-shot cost
exposes the issue.

This is exactly the motivation for the dynamic-tiled aggregation
contribution proposed for the SBAC-PAD'26 paper.

## Headline numbers: end-to-end speedup of pinned vs baseline

End-to-end means `comp_kernel + h2d` for baseline, and
`alloc + h2h + h2d + comp_kernel` for pinned (all measured this run,
no amortization).

| Algo     | Size   | Baseline (ms) | Pinned (ms) | Pinned / Baseline |
|----------|--------|--------------:|------------:|------------------:|
| LZ4      | 100 MB |          33.1 |        56.7 |          **0.58x** |
| LZ4      | 686 MB |         200.9 |       340.3 |          **0.59x** |
| LZ4      | 2 GB   |         346.5 |       762.9 |          **0.45x** |
| LZ4      | 4 GB   |         699.6 |      1779.3 |          **0.39x** |
| Snappy   | 100 MB |          19.7 |        43.3 |          **0.46x** |
| Snappy   | 686 MB |         131.1 |       279.6 |          **0.47x** |
| Snappy   | 2 GB   |         384.8 |       792.3 |          **0.49x** |
| Snappy   | 4 GB   |         792.3 |      1560.3 |          **0.51x** |
| Cascaded | 100 MB |          17.0 |        39.2 |          **0.43x** |
| Cascaded | 686 MB |         115.7 |       266.2 |          **0.43x** |
| Cascaded | 2 GB   |         322.0 |       736.5 |          **0.44x** |
| Cascaded | 4 GB   |         667.9 |      1454.7 |          **0.46x** |

Values < 1 mean pinned is **slower**.

## Where the time goes: pinned-path decomposition

The total of the pinned path is the sum of four phases: `t_alloc_ms`
(hipHostMalloc / arctoHostBatchCreate), `t_memcpy_h2h_ms` (pageable to
pinned copy), `Transfer H2D (ms)` (single bulk hipMemcpyAsync), and
`Compression time (ms)` (the actual kernel).

| Algo     | Size   |  alloc | h2h memcpy |     h2d |    kernel |   TOTAL | host_share |
|----------|--------|-------:|-----------:|--------:|----------:|--------:|-----------:|
| LZ4      | 100 MB |   24.8 |        9.4 |     4.4 |      18.2 |    56.7 |        60% |
| LZ4      | 686 MB |  158.1 |       58.1 |    26.5 |      97.6 |   340.3 |        64% |
| LZ4      | 2 GB   |  460.3 |      187.0 |    79.0 |      36.7 |   762.9 |        85% |
| LZ4      | 4 GB   |  929.0 |      365.6 |   426.0 |      58.6 |  1779.3 |        73% |
| Snappy   | 100 MB |   24.5 |        9.2 |     4.3 |       5.3 |    43.3 |        78% |
| Snappy   | 686 MB |  163.1 |       62.3 |    26.8 |      27.4 |   279.6 |        81% |
| Snappy   | 2 GB   |  457.6 |      181.2 |    79.0 |      74.6 |   792.3 |        81% |
| Snappy   | 4 GB   |  897.5 |      354.2 |   158.7 |     149.9 |  1560.3 |        80% |
| Cascaded | 100 MB |   23.6 |        8.5 |     4.3 |       2.7 |    39.2 |        82% |
| Cascaded | 686 MB |  164.7 |       63.5 |    26.5 |      11.6 |   266.2 |        86% |
| Cascaded | 2 GB   |  459.0 |      186.5 |    78.5 |      12.5 |   736.5 |        88% |
| Cascaded | 4 GB   |  900.9 |      371.1 |   157.0 |      25.7 |  1454.7 |        87% |

`host_share = (alloc + h2h) / TOTAL`. All values in milliseconds.

## Three observations

### 1. `t_alloc_ms` scales linearly with input size, at roughly 220 MB/s

Picking the LZ4 column (the others are within noise):
100 MB -> 24.8 ms, 686 MB -> 158.1 ms, 2 GB -> 460.3 ms, 4 GB -> 929.0 ms.
That is `hipHostMalloc` at an effective rate of roughly 4.5 ms per
100 MB, equivalent to **220 MB/s** of pinned allocation throughput on
gfx1100. This is the dominant per-call cost. It is consistent with
`hipHostMalloc` going through page-locking on every byte (kernel
mmap + page-lock), which is fundamentally not the path PCIe takes
during the actual transfer.

### 2. `t_memcpy_h2h_ms` scales linearly at 11-12 GB/s, the DRAM ceiling

Pageable to pinned is a host-to-host memcpy through socket DRAM.
Picking Cascaded (least sensitive to encoder cost): 100 MB -> 8.5 ms
(~11.8 GB/s), 686 MB -> 63.5 ms (~10.8 GB/s), 2 GB -> 186.5 ms
(~11 GB/s), 4 GB -> 371.1 ms (~11.0 GB/s). Stable at the socket DRAM
bandwidth, which is independent of any GPU optimization the library
might do.

### 3. The bulk H2D itself IS faster on pinned (3-4x), which is the
already-published 4.3x result -- the gain just gets eaten by phases 1
and 2 above.

Comparing the `h2d` column of pinned to baseline (`baseline h2d` from
the `comp_ms` + `h2d_ms` table; not shown but trivial to read off):
the bulk pinned hipMemcpyAsync runs at ~26 GB/s on small inputs
(consistent with PCIe peak, see `RX7900XT_PCIe_*/FINDINGS.md`), and at
~25 GB/s on large inputs. Baseline scattered runs at ~6 GB/s
regardless. So the underlying H2D gain is intact; it is the host-side
*setup* that the single-shot pinned design has to do, that the
scattered baseline does not, which makes the lifecycle uncompetitive.

## What this means for the SBAC-PAD'26 paper

The dynamic-tiled aggregation contribution (Optimization 3 in the
outline) is *necessary*, not optional. Its function is to amortize the
two host-side costs (alloc and h2h memcpy) over many tiles by reusing
a single fixed-size pinned buffer across all tiles. Specifically:

- `t_alloc` is paid ONCE per process (window_size, not input_size).
- `t_memcpy_h2h` is paid per tile, but each tile is fixed size, so
  the marginal cost per byte stays at the DRAM ceiling without growing
  with input.
- `t_h2d` is paid per tile, and tiles small enough to overlap with
  compute (Optimization 4, double-buffered) hide all of this behind
  the kernel.

This sweep is the empirical motivation for that design. It also
implies a stronger claim for the paper: the *current* pinned-host
optimization is only a *micro-benchmark* win, not a production win,
unless the caller can reuse the batch across many compress calls. The
dynamic-tiled design recovers the gain in the single-call case.

## What is NOT in this sweep, and why

- **8 GB and larger.** RX 7900 XT has 20 GB VRAM; an 8 GB input
  needs the device input buffer (8 GB) + device output buffer
  (~8 GB at TTI ratio 1.04) + transfer scratch + compress temp,
  which approaches the VRAM ceiling and risks failure. This sweep
  stops at 4 GB. Sizes from 8 GB to 64 GB should be run on MI300X
  (192 GB HBM3) on the Grid'5000 vianden-1 node, using the same
  branch and the same `--report_phases` flag.
- **Cross-architecture.** Same caveat: the next campaign should be a
  mirror sweep on MI300X with sizes 1 GB, 4 GB, 16 GB, 32 GB, 64 GB.
- **Other compressors.** ZFP was not included here because the
  scaling story is the same regardless of compressor (the host-side
  cost dominates either way) and the three byte-level compressors
  span the relevant cost range (Cascaded ~25 ms/4GB kernel; LZ4 ~58
  ms/4GB kernel; Snappy ~150 ms/4GB kernel).
- **Decompression.** Same comment: the host-side prep story is
  symmetric, but the decompression has different ratios on the D2H side.
  Worth a follow-up but not needed to motivate Optimization 3.

## Next steps

The MI300X mirror sweep is gated on Grid'5000 allocation, which is not
currently available. The work below proceeds independently on
RX 7900 XT and is the critical path for the paper.

1. Derive the dynamic-tiled cost model from the linear fits above
   (`t_alloc(W) ~ 220 MB/s`, `t_memcpy_h2h(W) ~ 11 GB/s`,
   `t_h2d(W) ~ 25 GB/s pinned`, `t_kernel(W) ~ algorithm-specific`),
   and predict `W_opt`.
2. Implement `arctoHostBatchTiled` as the MVP of Optimization 3
   (single-buffered, fixed window, reuse of pinned buffer across tiles).
3. Re-run this same sweep with tiled mode to validate the predicted
   `W_opt` and quantify the recovered gain on RX 7900 XT.
4. (Deferred) Mirror everything on MI300X (vianden-1, Grid'5000) when
   the allocation is back, extended to 8 GB through 64 GB inputs.

## Reproducing

```bash
# in lunaris, with the SIF and arcto checkout in /ssd/cakunas/arcto
RUN_DIR=results/RX7900XT_SCALING_$(date +%Y%m%d_%H%M%S)
mkdir -p $RUN_DIR
for size in 100mb 686mb 2gb 4gb; do
  for algo in lz4 snappy cascaded; do
    for mode in baseline pinned; do
      pinned=$([ "$mode" = "pinned" ] && echo "true" || echo "false")
      singularity exec -B /ssd/cakunas:/ssd/cakunas --rocm \
          /ssd/cakunas/arcto_gfx1100_v3.sif \
          bash -c "LD_LIBRARY_PATH=/ssd/cakunas/arcto/build_canon/lib:\$LD_LIBRARY_PATH \
              /ssd/cakunas/arcto/build_canon/bin/benchmark_${algo}_chunked \
              -f /path/to/tti_${size}.bin -c true -P $pinned -R true -w 1 -i 5" \
          > $RUN_DIR/${algo}_${size}_${mode}.csv \
          2> $RUN_DIR/${algo}_${size}_${mode}.csv.stderr
    done
  done
done
```

Combined CSV: `results_combined.csv` in this directory (24 rows, one
per algo x size x mode combination, 27 columns including the three
new phase columns).
