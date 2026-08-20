# Hybrid LZ4/ZFP snapshot compression — motivating data (negative result)

Raw sweep data, analysis and figures produced for the SSCAD 2026 paper on an
adaptive per-frame hybrid compressor that would pick LZ4 or ZFP according to the
sampled zero fraction of each wavefield frame.

**The paper was dropped on 2026-08-19: the hypothesis did not hold.** This
repository is kept because the negative result is what justifies the thesis's
move to error-bounded lossy ZFP for the wavefield.

## What the data shows

`frame_analysis.csv` — 101 TTI frames, per-frame zero fraction and compression
ratio for LZ4 and for ZFP at two accuracies:

| | min | median | max |
|---|---|---|---|
| `lz4_ratio` | 1.10 | 1.10 | 245.45 |
| `zfp_acc1e13_ratio` | 1.52 | 1.84 | 2048.00 |
| `zfp_acc1e6_ratio` | 3.36 | 6.92 | 2048.00 |

**LZ4 does not win a single frame — 0 of 101 — not even at the extreme.** Frame 0
is 100 % zeros, exactly the regime the hybrid was designed to hand to the lossless
branch, and LZ4 reaches 245x there while ZFP reaches 2048x. Once the wavefield
fills (zero fraction settles at ~0.097 from frame ~50 on), LZ4 flattens at 1.10
while ZFP holds 1.84 / 6.92.

So the adaptive selector has nothing to select: there is no zero-fraction
threshold at which the LZ4 branch is the right choice. Byte-level lossless does
not earn its place on this data even where the field is already zeroed — which
is the same conclusion ICCSA reached for the dense wavefield, now extended to
the sparse end too.

## Contents

| Path | What |
|---|---|
| `frame_analysis.csv` | per-frame zero fraction and LZ4/ZFP ratios (the table above) |
| `analyze_frames.c` | frame analyzer that produced the CSV |
| `plot_motivating.py` | plotting script for both figures |
| `fig_motivadora.{pdf,png}` | motivating figure |
| `fig_mecanismo.{pdf,png}` | mechanism figure |
| `sweep-mi210/` | MI210 sweep, hybrid thresholds 0/25/50/75/100 % (363 logs total with v2) |
| `sweep-mi210-v2/` | second MI210 sweep, adds `decode/` |

The working plan that drove this campaign is `PLANO-SSCAD2026-HIBRIDO.md` in the
workspace root; the compressor implementation is on the `feature/hybrid-compressor`
branch of `fletcher-modern`.
