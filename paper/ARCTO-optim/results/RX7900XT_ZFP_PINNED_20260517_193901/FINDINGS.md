# ARCTO ZFP -- pinned-host buffer optimization

RX 7900 XT (lunaris), `feature/zfp-canonical`, post-baseline. Same hardware
and inputs as `RX7900XT_ZFP_20260517_175421/` (the pre-optimization baseline);
the only change is **how the compressed bytes get back to the host**.

## What changed

The canonical LLNL/zfp HIP backend (used unmodified through ARCTO's thin C
wrapper) allocates its own device staging buffer for the compressed payload,
runs the encode kernel, then issues an implicit D2H to copy that payload into
the user's host buffer. On a 100 MB input compressed 2x, the D2H is ~52 MB --
non-trivial on PCIe Gen4 x16 (~32 GB/s peak).

Baseline `arctoZFPCompress` had the user pass a **pageable** host buffer,
which forces the HIP runtime to stage through a pinned bounce buffer before
the D2H -- you eat the bandwidth of the bounce copy on top of the actual D2H.

The optimization is a single line of change at the call site (the benchmark's
`--device-buffer` flag): allocate the user's host buffer with `hipHostMalloc`
instead of `std::vector<unsigned char>`. The canonical's HIP backend still
sees a host pointer and takes its normal code path, but the D2H now runs at
close to PCIe peak.

No changes to the canonical's source. No changes to ARCTO's library code (the
existing host API call sites already work; the user just has to pass a pinned
buffer). The wrapper functions `arctoZFPCompressToDevice` /
`arctoZFPDecompressFromDevice` introduced earlier in this experiment were
abandoned -- they hang on non-zero data, because the canonical's HIP backend
does not actually support a device-resident output stream despite the
`is_gpu_ptr()` check; the bitstream-layer writes (`stream_open`,
`zfp_write_header`) are CPU-only and dereferencing a device pointer from the
host loops forever waiting for a sync that never arrives.

## Head-to-head: pageable vs pinned (RX 7900 XT, medium TTI 100 MB)

|  Mode                          | Ratio | Comp pageable | Comp pinned | Speedup | Decomp pageable | Decomp pinned | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|
| `fixed_rate K=16`              | 1.97x | 19.62 GB/s | **32.46 GB/s** | **+65%** | 20.88 GB/s | **32.25 GB/s** | **+54%** |
| `fixed_precision p=12`         | 5.79x | 27.95 GB/s | 34.83 GB/s | +25% | 39.41 GB/s | **64.83 GB/s** | **+64%** |
| `fixed_precision p=20`         | 2.55x | 19.75 GB/s | 27.49 GB/s | +39% | 26.30 GB/s | 43.36 GB/s | +65% |
| `fixed_accuracy tol=1e-3`      | 21.65x| 36.72 GB/s | 40.20 GB/s | +9% | 69.51 GB/s | **95.78 GB/s** | +38% |
| `fixed_accuracy tol=1e-6`      | 7.80x | 30.18 GB/s | 34.48 GB/s | +14% | 50.84 GB/s | 66.35 GB/s | +30% |

Largest gains on `fixed_rate` (predictable: largest compressed payload =
largest D2H). Decompression always benefits because the same pinned path is
hit on the H2D of the compressed payload at the start of decompress.

## Large TTI 686 MB (large 1024 MB tier)

|  Mode                          | Ratio | Comp pageable | Comp pinned | Speedup | Decomp pageable | Decomp pinned | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|
| `fixed_rate K=16`              | 2.00x | 25.97 GB/s | **39.85 GB/s** | **+53%** | 24.59 GB/s | **35.03 GB/s** | **+42%** |
| `fixed_precision p=20`         | 2.63x | 20.16 GB/s | 27.35 GB/s | +36% | 28.65 GB/s | **47.17 GB/s** | **+65%** |
| `fixed_accuracy tol=1e-6`      | 7.28x | 32.06 GB/s | 37.05 GB/s | +16% | 57.21 GB/s | **75.67 GB/s** | +32% |

Gains hold up at 6.5x the input size -- not just a small-payload artifact.

## Where this lands vs the byte compressors

The original baseline (`RX7900XT_ZFP_20260517_175421/FINDINGS.md`) already
showed ZFP **compresses TTI 7x more** than LZ4/Snappy/Cascaded but is
slightly slower on decompression than Cascaded. The pinned-host optimization
narrows that gap further:

|  Algorithm (medium TTI)         | Ratio | Comp GB/s | Decomp GB/s |
|---|---:|---:|---:|
| Cascaded                       | 1.04x | 55.46     | 187.25      |
| Snappy                         | 1.05x | 24.09     | 107.64      |
| LZ4                            | 1.06x |  5.98     |  92.75      |
| **ZFP `acc=1e-6` (pageable)**  | **7.80x** | 30.18 | 50.84 |
| **ZFP `acc=1e-6` (pinned)**    | **7.80x** | **34.48** | **66.35** |
| **ZFP `acc=1e-3` (pinned)**    | **21.65x**| **40.20** | **95.78** |

ZFP `acc=1e-3` pinned is now **within ~10% of Snappy on decompression** while
delivering **20x more compression** on the data type the byte compressors
literally cannot handle.

## What's NOT optimized yet

The canonical's HIP backend still does a `hipMalloc` + `hipFree` of the
compressed staging buffer on **every** call. On a 100 MB input that is a
~52 MB allocation per compression, and per `rocm-smi` profiling these account
for ~1 ms of the per-call overhead. Two further optimizations to chase next:

1. **Persistent staging buffer** inside ARCTO (allocated once, reused across
   calls). Would require a small patch to the canonical's `hip/interface.h`
   to accept a user-supplied pre-allocated staging pointer -- a clean
   upstream-worthy change.
2. **Wave64 retuning** of the encode/decode kernels for gfx942 (MI300X).
   The canonical's HIP backend was originally written for wave32 (NVIDIA-
   derived), and a fresh, profile-driven attempt is the headline experiment
   for the SBAC-PAD'26 / Euro-Par'27 paper.

## Reproducing

Same recipe as the baseline. The pinned variant is enabled by appending
`--device-buffer` (or `-D`) to the command line:

```bash
TD=/path/to/testdata
singularity exec --rocm -B $TD:/data <sif> \
    benchmark_zfp_single -f /data/medium_TTI_100.bin -i 10 -w 2 \
                         -m fixed_accuracy -r 1e-6 -3 448,448,130 \
                         --device-buffer
```

## Files in this directory

```
zfp_3d_<mode><param>_<medium|large>_TTI_<pageable|pinned>.log   (16 files)
```

Each is a single-row CSV directly comparable against the baseline run's
files of the same name (without the `_pageable` / `_pinned` suffix). Drop
into the same R / Python aggregation pipeline used for the ICCSA26 figures.
