# ARCTO optimization paper -- working folder

Working name for paper #2 in the PhD timeline: **ARCTO: Efficient
Compression for AMD GPUs** (target venue: SBAC-PAD'26 or Euro-Par'27,
not yet committed -- folder named `ARCTO-optim` to stay venue-neutral).

The ICCSA26 paper established the cross-architecture baseline of three
byte-level compressors (LZ4 / Snappy / Cascaded) ported from nvCOMP to
HIP. This paper takes the next step: **closing the AMD performance gap**
through compressor-specific optimization, including the LLNL/zfp HIP
backend integration that ICCSA26 did not cover.

## What is here so far

```
paper/ARCTO-optim/
├── README.md                                this file
└── results/
    ├── RX7900XT_ZFP_20260517_175421/        ZFP baseline (pre-optimization)
    │   └── FINDINGS.md + 18 CSV logs
    └── RX7900XT_ZFP_PINNED_20260517_193901/ ZFP pinned-host optimization
        └── FINDINGS.md + 16 CSV logs
```

Both result directories are paired -- the PINNED dir's `FINDINGS.md`
references the baseline dir as the "before" column in every comparison
table. Always keep them together when promoting or pruning.

## Story so far (post-pinned-host run on RX 7900 XT)

- ZFP `fixed_rate K=16` on 100 MB TTI: pageable 19.6 GB/s -> pinned 32.5 GB/s
  compression (**+65%**); decomp +54%.
- ZFP `fixed_accuracy tol=1e-3` on 100 MB TTI: pinned at 95.8 GB/s decomp --
  within ~10% of Snappy while delivering 20x more compression on the data
  type Snappy/LZ4/Cascaded literally cannot compress.
- The change is one line at the call site (`hipHostMalloc` instead of
  `std::vector`), zero changes inside the canonical's HIP backend.

## What is missing for the paper

Numbered in rough priority order:

1. **Cross-GPU portability of the pinned-host gain.** RX 7900 XT is one
   data point; need MI50 / MI210 / MI300X to repeat the comparison and
   verify the gain reproduces (or to find architectures where it does
   not). The ICCSA26 paper's strength was the cross-architecture matrix --
   repeating that pattern for ZFP would carry the SBAC-PAD narrative.
2. **Persistent staging buffer.** The canonical's HIP backend still does
   a per-call `hipMalloc` + `hipFree` of the compressed staging buffer
   (~52 MB per call on a 100 MB input). A patch that lets ARCTO pass a
   pre-allocated, reused buffer would eliminate that overhead entirely.
   Upstream-worthy change.
3. **Wave64 retuning of the encode/decode kernels.** Canonical's HIP
   backend was written for wave32 (NVIDIA-derived); MI300X runs wave64
   natively. Earlier ARCTO branch `feature/wave64` was abandoned before
   profiling -- a fresh, profile-driven attempt is the headline experiment.
4. **Generalize the pinned-host optimization across all four
   compressors.** LZ4 / Snappy / Cascaded already run device-resident
   inside the compute path; the win there is on the H2D of the source
   data and the D2H of the compressed payload at the API boundary. May
   produce a smaller but uniform improvement across the matrix.

## How to add a new result snapshot

Same convention as `paper/ICCSA26/`: each run is its own
`paper/ARCTO-optim/results/<GPU>_<TAG>_<TIMESTAMP>/` directory with a
`FINDINGS.md` (one-paragraph TL;DR + comparison tables + reproducer
command) and one CSV per (mode, dataset, [variant]) combination. The
CSV schema matches `benchmark_*_chunked` exactly so the same R / Python
aggregation pipeline ingests it without changes.

Day-to-day benchmark runs land in `compression-experiments/results/`
(gitignored). Promote to this directory only when the run becomes a
referenced data point for the paper.
