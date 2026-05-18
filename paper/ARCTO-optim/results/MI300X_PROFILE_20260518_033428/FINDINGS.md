# MI300X kernel profiling -- root cause of the LZ4 perf gap

Profiled the three byte-level chunked compressors (LZ4, Snappy, Cascaded)
on `vianden-1` (Grid5000 MI300X, gfx942, ROCm 7.0.1) with rocprofv3.
Goal: confirm or invalidate the wave64-mismatch hypothesis we formed
after the MI300X cross-GPU sweep showed LZ4 running at **4.9 GB/s
compression** while Cascaded ran at **90 GB/s** on the SAME hardware.

Two-phase profiling, both inside the same `arcto_gfx942.sif`
(arcto@8599fbf, the `paper/arcto-optim-validated` tag):

1. `--kernel-trace --stats`: discover which kernels dominate total time.
2. `--pmc`: collect occupancy, VALU utilization, memory stall, and wave
   count for the hot kernels.

## Phase 1: kernel-trace -- where does the time go?

Per-call cost on medium TTI 100MB input (5 iterations each):

| Algo     | Hot compress kernel cost   | Hot decompress kernel cost   | Share of total |
|---|---:|---:|---:|
| LZ4      | **21.43 ms per call (4.67 GB/s)** | 1.46 ms per call (68.5 GB/s) | comp = **92.47%** |
| Snappy   | 1.75 ms per call (57.07 GB/s)     | 0.57 ms per call (176.4 GB/s) | comp = 66.48% |
| Cascaded | **1.16 ms per call (86.31 GB/s)** | 0.35 ms per call (287.3 GB/s) | comp = 64.41% |

**LZ4 compress is 18.5x slower than Cascaded compress per call on the
SAME 100 MB input.** Not 10% slower, not 2x slower -- 18.5x. This is
entirely a kernel-internal issue: not launch overhead, not H2D, not
memory copy. The LZ4 kernel itself is the slow path.

## Phase 2: PMC counters -- WHY is LZ4 compress 18.5x slower?

Collected `OccupancyPercent`, `VALUUtilization`, `MemUnitStalled`,
`GRBM_GUI_ACTIVE`, `SQ_BUSY_CYCLES`, `SQ_WAVES` for both LZ4 and
Cascaded compress/decompress kernels. Averaged across 5 dispatches per
kernel:

|  Metric              | LZ4 comp        | LZ4 decomp     | Cascaded comp   | Cascaded decomp |
|---|---:|---:|---:|---:|
| Grid_Size            | 102400          | 102400         | 204800          | 204800          |
| Workgroup_Size       | **64 (1 wave)** | 128 (2 waves)  | 128 (2 waves)   | 128 (2 waves)   |
| LDS_Block_Size       | 512 B           | 1024 B         | **13824 B**     | 13312 B         |
| VGPR_Count           | 68              | 68             | 72              | 76              |
| SGPR_Count           | 64              | 80             | 112             | 112             |
| SQ_WAVES (total)     | **1600**        | 1600           | **3200**        | 3200            |
| **OccupancyPercent** | **9.35%**       | **3.57%**      | **15.71%**      | 6.35%           |
| **VALUUtilization**  | **94.54%**      | **96.77%**     | 93.19%          | 75.47%          |
| MemUnitStalled       | 2.29%           | 5.36%          | 5.47%           | 5.21%           |
| GRBM_GUI_ACTIVE      | **344.98 M**    | 24.81 M        | **19.46 M**     | 6.01 M          |

**Five things this tells us:**

### 1. The hypothesis is correct: LZ4 launches 1 wave per block (64 threads on wave64)

`Workgroup_Size = 64` and `SQ_WAVES = 1600` confirms it: LZ4 compress
launches **exactly one wave per block, exactly one block per chunk**.
Cascaded launches two waves per block (128 threads), giving twice the
wave count for the same chunk count.

This matches what the source code says
(`src/LZ4Kernels.hiph:118` --
`LZ4_COMP_THREADS_PER_CHUNK = warpsize`, `assert(blockDim.x ==
warpsize)` at line 228).

### 2. But "more waves" isn't the WHOLE story -- LZ4 VALU is already pegged

`VALUUtilization = 94.54%` on LZ4 compress is **higher** than Cascaded's
93.19%. When a LZ4 wave is running, it's working hard -- the VALU is
nearly fully busy on every cycle. This is the opposite of what
"branch-divergence-bound" would look like.

So the bottleneck is NOT divergence, NOT scalar instructions, NOT
memory stalls (only 2.3% on LZ4 compress). The bottleneck is **wave
count itself**: there simply aren't enough waves to keep the GPU
busy.

### 3. Occupancy math: MI300X has ~9700 wave slots; LZ4 dispatches 1600

MI300X has **304 CUs x 4 SIMDs/CU x 8 max-waves-per-SIMD = 9728
wave-slots**. LZ4 dispatches **1600 waves total**, so even in the best
case we use 16.5% of wave-slot capacity on average. Measured 9.35%
means roughly half those waves are actually concurrent at any given
moment (with the rest stalled on serialization, scheduling, or
finishing up).

Cascaded dispatches **3200 waves** (2 waves per block x 1600 blocks),
gets **15.71%** occupancy -- closer to the 32.9% theoretical max.

### 4. Cascaded uses 27x more LDS per block

LDS_Block_Size: Cascaded 13824 B vs LZ4 512 B. Cascaded packs more
per-chunk state into LDS, doing more useful work per kernel launch.
LZ4's `LDS_Block_Size = 512 B` is essentially nothing -- one cache
line of staging space. This is consistent with the "1 wave handles
one chunk linearly" pattern.

### 5. Total cycle count tells the same story 18.5x over

`GRBM_GUI_ACTIVE` (total GPU cycles where the GUI is busy with the
kernel) is **344.98 M cycles for LZ4 compress vs 19.46 M for Cascaded
compress** -- a **17.7x ratio**, matching the **18.5x time ratio** to
within noise. The slowdown isn't an artifact of measurement
inflation -- it's real cycles spent.

## What this means for the wave64 retuning frontier

The fix is NOT "switch to wave64" (already done -- USE_WARPSIZE_32 is
OFF for gfx942 builds). The fix is **pack multiple chunks per block**:

- Change `LZ4_COMP_THREADS_PER_CHUNK = warpsize` (currently 64 on
  wave64) to keep ONE wave per chunk but launch N chunks per block,
  giving `blockDim.x = N * warpsize` threads.
- With N=4 we'd have 6400 total waves on a 100 MB / 1600-chunk input,
  pushing theoretical occupancy from 16.5% to 66% -- and at 94% VALU
  utilization, that should translate roughly linearly to ~4x kernel
  speedup.

Empirical estimate: **LZ4 compress could go from 4.67 GB/s to
~18-20 GB/s** on MI300X with this single-line code change.

That doesn't catch Cascaded's 86 GB/s (Cascaded does fundamentally
fewer instructions per byte), but it would close the *most embarrassing*
gap in the ARCTO benchmark suite and add a clean section to the SBAC-PAD
paper:

> "The original chunked-compressor kernels were ported from nvCOMP
> assuming NVIDIA's 1 warp = 1 chunk = 1 block pattern, where a
> warp is 32 threads. On AMD CDNA architecture (MI300X, gfx942) with
> 64-thread waves, this pattern leaves 84% of available wave slots
> unused on the GPU even at peak occupancy. We restructure the LZ4
> kernel to dispatch 4 chunks per block (4 waves), raising hardware
> utilization from 9.35% to N% and end-to-end compression throughput
> from 4.67 GB/s to N GB/s on TTI workload."

## What this also rules out

| Suspected bottleneck    | Verdict                              | Evidence            |
|---|---|---|
| Wave32 vs wave64 mode   | NOT the issue, wave64 already enabled | `Workgroup_Size = 64` confirms wave64 |
| Branch divergence       | NOT the issue                         | VALUUtilization 94.54% |
| Memory bandwidth        | NOT the issue                         | MemUnitStalled 2.29% (vs 5.47% for Cascaded) |
| Register pressure       | NOT the issue                         | VGPR 68 (similar to Cascaded 72), well under MI300X's 65536/CU |
| Scratch / spill         | NOT the issue                         | Scratch_Size = 0 |

## Decompress: same pattern, more dramatic

LZ4 decompress runs with Workgroup_Size=128 (2 waves) -- better than
compress -- but ONLY 3.57% occupancy because the kernel is shorter and
needs even more parallelism to fill the GPU. Same fix would help:
launch more chunks per block.

## Reproducing

The two profiling phases are scripted at:

```
scripts/profile_arcto_kernels.sh                -- phase 1: kernel-trace
```

Phase 2 (PMC) is bespoke -- the rocprofv3 invocation is documented
inline at the top of this directory in `pmc_set.txt`-style. To re-run:

```bash
echo "pmc: OccupancyPercent VALUUtilization MemUnitStalled GRBM_GUI_ACTIVE SQ_BUSY_CYCLES SQ_WAVES" > pmc.txt
singularity exec --rocm -B testdata:/data SIF rocprofv3 \
    -i pmc.txt -d out_dir -o lz4_pmc -f csv -- \
    /opt/arcto/build/bin/benchmark_lz4_chunked -f /data/medium_TTI_100.bin -i 5 -w 2 -c true
```

## Files in this directory

```
{lz4,snappy,cascaded}_kernel_trace/
    *_trace_kernel_stats.csv     -- per-kernel aggregates (the headline data above)
    *_trace_hip_api_stats.csv    -- per-HIP-API aggregates
    *_trace_hip_api_trace.csv    -- raw timeline
    *_trace_agent_info.csv       -- GPU agent enumeration
    *_trace_domain_stats.csv     -- per-domain summary
```

PMC data lives in a sibling directory `MI300X_PMC_20260518_033827/` --
this split is intentional so the kernel_trace phase (cheap, full
coverage) is separable from the PMC phase (expensive, focused on hot
kernels only).
