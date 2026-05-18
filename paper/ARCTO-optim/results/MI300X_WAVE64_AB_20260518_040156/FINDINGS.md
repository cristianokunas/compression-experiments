# MI300X wave64 A/B -- NEGATIVE RESULT, hypothesis refined

A/B benchmark of the `feature/wave64-mi300x` branch (arcto@fe9e3ca,
LZ4 with `LZ4_COMP_CHUNKS_PER_BLOCK = 4`) against the baseline
`paper/arcto-optim-validated` tag (arcto@8599fbf,
`LZ4_COMP_CHUNKS_PER_BLOCK = 1` implicit) on MI300X.

**Result: no measurable improvement, all deltas in noise.** The
hypothesis as originally stated -- "pack more chunks per block to
raise wave count" -- was insufficient. The patch DOES change the
launch geometry, but does NOT actually add waves.

## What we measured

### LZ4 throughput (TTI workload, 3 sizes x 2 modes x 2 SIFs)

| File          | Mode             | baseline GB/s | wave64 GB/s | delta  |
|---|---|---:|---:|---:|
| small_TTI 10MB  | comp (no pin)  | 0.51          | 0.52        | noise  |
| small_TTI 10MB  | comp (pinned)  | 0.51          | 0.51        | noise  |
| medium_TTI 100MB| comp (no pin)  | 4.77          | 4.79        | noise  |
| medium_TTI 100MB| comp (pinned)  | 4.78          | 4.88        | +2%    |
| large_TTI 686MB | comp (no pin)  | 12.11         | 11.83       | -2%    |
| large_TTI 686MB | comp (pinned)  | 12.10         | 12.11       | noise  |
| medium_TTI 100MB| decomp (no pin)| 71.23         | 71.64       | noise  |
| large_TTI 686MB | decomp (pinned)| 305.83        | 306.21      | noise  |

Total-time (H2D + comp) is also unchanged in any meaningful direction.

### PMC: the geometry change DID land, but wave count was unaffected

LZ4 compress kernel on the new wave64 SIF (medium_TTI 100MB, 5 dispatches):

|  Metric              | Baseline SIF | Wave64 SIF (N=4) | Delta            |
|---|---:|---:|---|
| Workgroup_Size       | 64           | **256**          | 4x (geometry change confirmed)  |
| LDS_Block_Size       | 512 B        | 1024 B           | 2x (per-chunk slice, expected)  |
| Grid_Size            | 102400       | 102400           | unchanged                       |
| **SQ_WAVES (total)** | **1600**     | **1600**         | **UNCHANGED**                   |
| OccupancyPercent     | 9.35%        | 9.30%            | noise                           |
| VALUUtilization      | 94.54%       | 94.54%           | identical                       |
| GRBM_GUI_ACTIVE      | 344.98 M     | 343.59 M         | identical                       |
| MemUnitStalled       | 2.29%        | 3.01%            | noise                           |

## What I got wrong

The original analysis (in
`MI300X_PROFILE_20260518_033428/FINDINGS.md`) said:

> "LZ4 needs to launch with N waves per block. Packing N chunks per
> block multiplies total wave count by N, lifting occupancy linearly."

The first half is right; the second half is wrong. Packing 4 chunks
per block **regroups** the existing waves -- it does NOT add new ones:

- Baseline: 1600 blocks x 1 wave/block = **1600 waves total**
- Wave64 patch: 400 blocks x 4 waves/block = **1600 waves total**

Same wave count, different block structure. The GPU sees the same
total work and produces the same total cycles (344M vs 345M --
identical to within noise).

What would have actually added waves: **more threads PER CHUNK**, i.e.
parallelizing the per-chunk compress work across multiple waves. That
is a fundamental algorithmic change (LZ4's byte-stream parsing is
inherently serial within a chunk), not a launch geometry tweak.

## What the patch DOES legitimately give us

Even though the throughput delta is zero, the patch is not entirely
wasted. It establishes the infrastructure for an eventual real
optimization:

1. **`LZ4_COMP_CHUNKS_PER_BLOCK` is now a tunable constant** -- mirrors
   the existing `LZ4_DECOMP_CHUNKS_PER_BLOCK` for symmetry.
2. **`warpMatchAny` fallback now supports `blockDim.y > 1`** via
   per-chunk shared-memory slices. The legacy `blockDim.y == 1` assert
   was a barrier to any future multi-chunk experiment.
3. **The compress kernel has a bounds guard** for tail blocks, which a
   future "real" multi-wave-per-chunk launch will also need.

So the *plumbing* is correct. What's wrong is the *hypothesis* that
plumbing was meant to test.

## The real fix would require restructuring `compressStream`

Cascaded's compress kernel uses Workgroup_Size = 128 (2 waves) for ONE
chunk -- meaning the algorithm parallelizes one chunk's work across
two waves. That's why Cascaded has SQ_WAVES = 3200 (2 x batch_size)
and LZ4 baseline has only 1600 (1 x batch_size).

The 18.5x kernel-time gap between LZ4 and Cascaded is NOT purely a
wave-count gap. Even at 3200 waves (Cascaded's level), LZ4 would still
have an inherently more expensive per-byte algorithm (hash-table
lookups + match search vs Cascaded's RLE + delta + bitpack). A rough
upper-bound estimate from the occupancy delta alone: ~9 GB/s vs
Cascaded's 86 GB/s.

For the SBAC-PAD paper this becomes a different (cleaner) story:

> "We profiled the LZ4 compress kernel on MI300X and identified its
> 1-wave-per-chunk launch geometry as one of two compounding
> bottlenecks: low total wave count (1600 vs the GPU's ~9700 wave
> slots) and inherently serial per-chunk computation. Adjusting block
> packing alone gives no improvement; the algorithm itself would need
> intra-chunk parallelization. We report the negative result alongside
> the host-side optimization, which delivers 1.1-9.3x end-to-end
> speedup on the same workload without touching kernel code."

## What to do next

Two reasonable paths:

A) **Revert the patch**. It provides no benefit and adds complexity.
   The negative result is captured in this directory.

B) **Keep the patch as plumbing infrastructure** + investigate
   parallelizing `compressStream` across 2 waves per chunk (mirror what
   Cascaded does). This is significant kernel-algorithm work, not a
   one-line change. Estimated effort: 1-2 weeks of focused kernel
   work + profiling. May or may not pay off given the inherent
   algorithmic serialism.

For the paper we don't NEED LZ4 to be fast on MI300X -- the host-side
story alone (5-13x total-time speedup across all 48 dataset combos)
is a strong contribution. LZ4 lagging at 12 GB/s on large_TTI while
Cascaded does 126 GB/s on the same GPU is a fair characterization of
where the byte-compressor port stands today.

## Files in this directory

```
lz4_{small,medium,large}_TTI_*_{baseline,wave64}{,_PINNED}.csv  (12 files)
profile_wave64/
    lz4_wave64_trace_*.csv                  -- kernel-trace from the wave64 SIF
    pmc_1/lz4_wave64_pmc_*.csv              -- PMC counters from the wave64 SIF
```

Direct apples-to-apples comparison against `MI300X_PROFILE_*/` and
`MI300X_PMC_*/` (the baseline-SIF profiles).
