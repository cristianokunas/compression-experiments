# ARCTO SBAC-PAD'26 paper draft

Working draft of *ARCTO: A Profile-Driven Compression Library for AMD GPUs*.

## Structure

```
draft/
├── README.md            this file
├── main.tex             top-level (IEEEtran conference class)
├── sections/
│   ├── 1-introduction.tex   ✓ first pass
│   ├── 2-background.tex     ✓ first pass
│   ├── 3-arcto-library.tex      TODO
│   ├── 4-optim-chunk-size.tex   TODO
│   ├── 5-optim-adaptive-tiled.tex  TODO
│   ├── 6-evaluation.tex          TODO
│   ├── 7-related-work.tex        TODO
│   └── 8-conclusion.tex          TODO
├── figures/             (empty, to be populated)
└── bib/refs.bib         (empty, to be populated)
```

## Canonical workload sizes for all sweeps

All experiments in this paper use TTI seismic input at the same six
sizes (extracted from the middle timesteps of the Fletcher 448^3
simulation):

  **10 MB, 100 MB, 1 GB, 4 GB, 8 GB, 16 GB**

VRAM viability matrix (see Table II in section 2.4):

| GPU        | 10 MB | 100 MB | 1 GB | 4 GB | 8 GB | 16 GB |
|------------|------:|-------:|-----:|-----:|-----:|------:|
| MI50 (32 GB) | y     | y      | y    | y    | ~    | --    |
| MI210 (64 GB)| y     | y      | y    | y    | y    | ~     |
| MI300X (192) | y     | y      | y    | y    | y    | y     |
| RX 7900 (20) | y     | y      | y    | y    | --   | --    |

Note: RX 7900 XT 8 GB tested empirically and fails with
`hipErrorOutOfMemory`: peak device allocation = 2x input
(input buffer + worst-case compress output buffer held
simultaneously during the kernel) plus per-chunk scratch
> 16 GB at 8 GB input, exceeds the 20 GB VRAM ceiling.

## Source data on disk

Currently the campaign uses:
  - `medium_TTI_100.bin` (100 MB, OK)
  - `large_TTI_1024.bin` (actually 686 MB, needs regen)
  - `xlarge_TTI_4096.bin` (4 GB, OK)
  - `tti_scaling/tti_{2,4,8}gb.bin` (truncated head-of-file, not
    extracted from middle; needs regen for paper-quality data)

For the paper-quality sweep, regenerate all six sizes (10 MB, 100 MB,
1 GB, 4 GB, 8 GB, 16 GB) from the middle of TTI.rsf@ using the same
extraction script as the ICCSA paper. See
`paper/ICCSA26/extract_middle_timesteps.sh` (or recreate).

## Sequence to complete the paper

1. (done) Introduction
2. (done) Background and Experimental Setup
3. Regenerate canonical datasets at the six sizes above
4. Re-run sweep on RX 7900 XT and MI300X (and MI50, MI210 if access)
   with the canonical datasets
5. Draft Section 3 (ARCTO library)
6. Draft Section 4 (chunk-size formula) -- pulls from MI300X_CHUNK_SWEEP_*
7. Draft Section 5 (adaptive tiled) -- pulls from RX7900XT_SCALING_*,
   RX7900XT_ADAPTIVE_*, MI300X_ADAPTIVE_*, MI300X_ADAPTIVE_LARGE_*
8. Draft Section 6 (evaluation) with the final figures
9. Draft Section 7 (related work) -- can reuse from phd thesis
10. Draft Section 8 (conclusion)
11. Abstract last
