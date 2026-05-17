# ZFP baseline benchmark on RX 7900 XT (lunaris)

First ZFP run after the canonical-wrap integration (`arcto` branch
`feature/zfp-canonical`, commit `557b0d8`). All numbers from `benchmark_zfp_single`,
mean of 10 iterations after 2 warmups, gfx1100, `USE_WARPSIZE_32=ON`.

The other three algorithm columns (LZ4 / Snappy / Cascaded) are quoted
from `results/RX7900XT_20260314_190340/results.csv` -- same hardware, same
input files, same iteration count -- and were measured before this ZFP
integration existed.

## TL;DR

ZFP solves a problem the other three compressors can't even attempt:
**float-data compression**. On the canonical 100 MB TTI checkpoint, the
byte-level compressors achieve essentially nothing (1.04-1.06x), while
ZFP delivers 2-22x depending on the quality knob -- at competitive
throughput.

## Head-to-head on TTI 100 MB (medium, RX 7900 XT)

| Algorithm                          | Ratio | Comp GB/s | Decomp GB/s | Notes |
|---|---|---|---|---|
| LZ4 (chunked, 64 KB)               | 1.06x |  5.98     | 92.75       | byte-level |
| Snappy (chunked, 64 KB)            | 1.05x | 24.09     | 107.64      | byte-level |
| Cascaded (chunked, 64 KB)          | 1.04x | 55.46     | 187.25      | byte-level |
| **ZFP FIXED_RATE 1D K=16**         | **2.00x** | 23.83 | 26.70   | apples-to-apples chunk-style |
| **ZFP FIXED_RATE 3D K=16**         | 1.97x | 22.18     | 24.82       | 448x448x130 cube |
| **ZFP FIXED_RATE 3D K=8**          | **3.94x** | **38.64** | **44.93** | visually lossy |
| **ZFP FIXED_PRECISION 3D p=12**    | **5.79x** | 28.95 | 43.98       | |
| **ZFP FIXED_PRECISION 3D p=20**    | 2.55x | 19.75     | 26.30       | "visually lossless" |
| **ZFP FIXED_ACCURACY 3D tol=1e-3** | **21.65x** | **36.81** | **72.18** | |
| **ZFP FIXED_ACCURACY 3D tol=1e-6** | **7.80x** | 30.89 | **52.49**   | |

Compared to LZ4/Snappy/Cascaded on the same input:

- **22x more compression** at `tol=1e-3` than the best byte compressor
- **7x more compression** at `tol=1e-6` (well below visualization noise)
- Compression THROUGHPUT is competitive: ZFP at 30-38 GB/s vs Snappy's 24
  and Cascaded's 55
- Decompression throughput is the only metric where ZFP currently trails
  (52-72 GB/s vs Cascaded's 187 / Snappy's 107) -- the obvious next
  optimization target

## Large TTI 686 MB (large 1024 MB tier, RX 7900 XT)

| Algorithm                          | Ratio | Comp GB/s | Decomp GB/s |
|---|---|---|---|
| LZ4                                | 1.04x | ~12.35    | ~305        |
| Snappy                             | 1.03x | ~84       | ~301        |
| Cascaded                           | 1.03x | ~127      | ~629        |
| ZFP FIXED_RATE 3D K=16             | 2.00x | 25.54     | 24.41       |
| ZFP FIXED_PRECISION 3D p=20        | 2.63x | 22.28     | 33.05       |
| ZFP FIXED_ACCURACY 3D tol=1e-6     | 7.28x | 36.40     | 68.49       |

Scaling from medium to large generally improves throughput on the byte
compressors (overhead amortization). ZFP's compression throughput
improves modestly (24 -> 27 GB/s), decompression stays flat (~25 GB/s)
-- another pointer to where the optimization budget should go.

## ZFP throughput is independent of data content (FIXED_RATE)

Same K=16 1D, four datasets:

| Dataset           | Ratio | Comp GB/s | Decomp GB/s |
|---|---|---|---|
| medium zeros      | 2.00x | 22.63     | 25.28       |
| medium binary     | 2.00x | 21.52     | 23.56       |
| medium random     | 2.00x | 22.93     | 25.45       |
| medium TTI        | 2.00x | 23.83     | 26.70       |
| large zeros       | 2.00x | 26.58     | 25.61       |
| large binary      | 2.00x | 26.16     | 24.40       |
| large random      | 2.00x | 26.04     | 24.22       |
| large TTI         | 2.00x | 27.42     | 25.97       |

Ratio is deterministic (K bits per value, irrespective of content) and
throughput barely moves (+/- 1 GB/s) -- contrasts sharply with the byte
compressors whose ratios vary 1.00x-245x across the same datasets. For
ZFP this means: predictable behavior, but no "free lunch" on
high-entropy data. Variable-rate modes restore the content dependence
and are where the real compression value lives.

## What this enables for the paper

Everything we measured before "didn't really compress" the TTI workload
that the simulator actually produces. ZFP makes that workload
compressible at acceptable throughput. The paper narrative becomes:

> Existing ports of byte-level compressors to AMD GPUs (the LZ4 / Snappy
> / Cascaded path inherited from nvCOMP) achieve essentially zero
> compression on the float32 wavefield data that real seismic checkpoints
> consist of. We integrate the canonical LLNL/zfp HIP backend into
> ARCTO, with a thin C wrapper and a self-describing trailer for the
> variable-rate modes, and add a GPU-native lossless mode for the cases
> where bit-exact checkpoints are required. The result is 2-22x
> compression on real TTI data at competitive throughput, on AMD
> hardware that previously had no production-quality answer for this
> workload.

## Open optimization headroom (for the SBAC-PAD / Euro-Par paper)

The numbers above use the canonical HIP backend essentially out of the
box. Three targeted optimization paths for MI300X specifically:

1. **Local Data Store (LDS) staging of intermediate bit-planes** --
   ZFP's per-block coder writes bit-by-bit; tiling those writes through
   LDS instead of VRAM should help most on the decompress path (already
   the bottleneck).
2. **Wave64 retuning** -- canonical's HIP backend is written assuming
   wave32 (NVIDIA-derived); MI300X runs wave64 natively, so a code path
   that emits 64-wide work per warp may close the decomp gap vs the byte
   compressors. The earlier wave64 attempt (abandoned in feature/wave64)
   needs a fresh look with proper profiling.
3. **Portability check** -- verify the same ARCTO ZFP binary still hits
   acceptable throughput on MI50 / MI210 (the cross-platform comparison
   we did for LZ4/Snappy/Cascaded was the heart of the ICCSA paper;
   repeating it for ZFP would be a centerpiece of the SBAC-PAD paper).

Pre-optimization baseline (this run) gives us the "before" column for
those experiments.

## Reproducing this

Inside the `arcto_gfx1100.sif` (with `benchmark_zfp_single` -- requires
rebuilding the image now that the new source is in the repo):

```bash
TD=/path/to/testdata
singularity exec --rocm -B $TD:/data <sif> \
    benchmark_zfp_single -f /data/medium_TTI_100.bin -i 10 -w 2 \
                         -m fixed_accuracy -r 1e-6 -3 448,448,130 -c
```

`-c` emits one CSV row matching the existing `benchmark_*_chunked` format.
Drop into the same R / Python aggregation pipeline as before.

## Per-file CSV outputs in this directory

```
zfp_1d_fr16_{medium,large}_{zeros,binary,random,TTI}_{100,1024}.log  (8 files)
zfp_3d_<mode><param>_medium_TTI.log                                 (7 files)
zfp_3d_<mode><param>_large_TTI.log                                  (3 files)
```

Each is a 2-row CSV (header + measurement) directly ingestable as a
single-chunk record in the chunked-benchmark schema.
