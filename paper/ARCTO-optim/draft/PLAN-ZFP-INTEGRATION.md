# Plan: ZFP integration + reference audit (review draft)

> Status: largely applied 2026-05-24 / 2026-05-25. The decisions block
> below records what actually got implemented; the original plan body
> follows for reference.
>
> **Applied:**
> - Sec.~3 reorganization (algorithm portfolio + optimization roadmap)
> - Sec.~3.1 framing fix (positive contribution-layer framing)
> - Sweep matrix refactor with explicit Block A / Block B split
> - Option 2 chosen for ZFP integration: byte-level chunked Block A,
>   ZFP whole-field single-call Block B (no chunked-template ZFP)
> - ZFP reversible mode **dropped from the paper campaign** after
>   `arctoZFPReversible3D` was found to break at >= 4 GB on gfx1100
>   (see `arcto/ISSUE_arctoZFPReversible3D_4GB_fails_gfx1100.md`).
>   Block B now sweeps the three canonical lossy modes
>   (fixed_accuracy + fixed_rate + fixed_precision) instead.
>
> **Open from the original plan:**
> - Reference audit of Sec.~4 / Sec.~5 (claims table at the end of
>   this file). Not yet applied.

---

## (a) Sec.~3 reorganization

### Current structure
1. Design constraints
2. Porting approach (3 phases)
3. Public API and integration model (mentions ZFP briefly as a submodule)
4. Repository structure and reproducibility

### Proposed structure
1. Design constraints                       *(unchanged)*
2. Porting approach                         *(unchanged)*
3. **Algorithm portfolio** *(new, promotes the algorithm enumeration)*
   - Three lossless byte-level codecs (LZ4, Snappy, Cascaded) inherited
     and hipified from the \nvcomp{} 2.2 baseline
   - ZFP with two modes: **reversible** (lossless, float-typed input)
     and **fixed-accuracy** (lossy, error-bounded), both backed by the
     upstream ZFP reference
   - Lossy mode framed as a deliberate offering, not a fallback:
     justified for seismic wavefields by `lindstrom2016f3dt`
     (bounded relative error does not affect the migrated image
     quality in F3DT) and grounded in the original ZFP design of
     `lindstrom2014zfp`
   - Forward pointer: byte-level codecs benefit from both
     optimizations of Sec.~4 and Sec.~5; ZFP-reversible benefits from
     Sec.~5 (transfer-side, algorithm-agnostic) and from a separately
     calibrated $W_{\text{sat}}$ in Sec.~4; ZFP-lossy is reported
     under a quality-vs-throughput lens in Sec.~6
4. Public API and integration model         *(slimmed: algorithm
   enumeration moves to §3.3 above; this stays about ABI, C-not-C++,
   Fortran reach)*
5. **Optimization roadmap** *(new, short)*
   - One paragraph naming the two contributions and where they sit:
     Sec.~4 reclaims kernel time via a wave-saturation chunk size,
     Sec.~5 reclaims transfer-pipeline time via an adaptive tiled
     pinned-staging window
   - Closes Sec.~3 by stating the substrate is in place and the next
     two sections add the research contributions on top of it
6. Repository structure and reproducibility *(unchanged)*

### Refs added by this reorganization
- `lindstrom2014zfp`  → algorithm core
- `lindstrom2016f3dt` → seismic-domain justification for lossy
- (no new refs to be added; both already in `bib/refs.bib`)

---

## (b) Sweep matrix changes (`sweep_canonical.sh`)

### Current matrix
```
DATA_TYPES = tti zeros random binary
SIZES      = 10mb 100mb 1gb 4gb 8gb 16gb
ALGOS      = lz4 snappy cascaded
MODES      = baseline pinned adaptive
```
$4 \times 6 \times 3 \times 3 = 216$ cells before VRAM filtering.

### Proposed matrix

**Block A: lossless transfer-side comparison** (existing story
extended to ZFP-reversible)
```
DATA_TYPES = tti zeros random binary
SIZES      = 10mb 100mb 1gb 4gb 8gb 16gb
ALGOS      = lz4 snappy cascaded zfp_reversible
MODES      = baseline pinned adaptive
```
$4 \times 6 \times 4 \times 3 = 288$ cells (vs 216) $\Rightarrow$
**+33 %**

**Block B: lossy ZFP quality-vs-throughput** (new)
```
DATA_TYPES   = tti                          (only float dataset)
SIZES        = 10mb 100mb 1gb 4gb 8gb 16gb
ALGO         = zfp
ACCURACIES   = 1e-3 1e-4 1e-5               (3 fixed-accuracy points)
MODE         = adaptive                     (best transfer mode only)
```
$1 \times 6 \times 1 \times 3 \times 1 = 18$ cells

**Total: $288 + 18 = 306$ cells (vs 216).** Net +42 % before
VRAM filtering.

### Per-cell outputs

For Block A (lossless): unchanged. CSV with `throughput`, `ratio`,
`chunk_size`, phase timings.

For Block B (lossy ZFP): CSV with the lossless fields **plus**
`max_abs_diff` and `PSNR` computed by the bench binary against the
original input. Needs a `--report_quality` flag on
`benchmark_zfp_chunked`.

### Script changes required
- Add `zfp_reversible` and `zfp` (lossy) cases in the algorithm
  dispatch. The binary `benchmark_zfp_chunked` already exists in
  `arcto/`; needs to accept `-a reversible` and `-a fixed_accuracy -e
  <tol>` flags (verify in the source before assuming).
- Quality computation: confirm whether `benchmark_zfp_chunked` already
  emits max\_abs\_diff/PSNR. If not, add a postprocess
  `compute_quality.py` that takes `original.bin` and `decompressed.bin`
  and emits a small CSV.
- Output naming: `${dtype}_${size}_${algo}_${mode}.csv` becomes
  `${dtype}_${size}_${algo}_${mode}${_acc}?.csv` (the `_acc` suffix
  appears only on lossy cells).
- VRAM cap: ZFP-reversible memory footprint per workload needs to be
  measured; provisionally apply the same `MAX_GB_FOR_GPU` caps as the
  byte-level codecs, then tighten if we hit OOM.

### Open ZFP-side question for ARCTO build
- The current `arctoBatchedZFP*` API needs to be confirmed against
  what `benchmark_zfp_chunked` exposes. If the chunked benchmark only
  drives the lossless path today, the lossy path needs to be wired up
  before Block~B can run.

---

## (c) Claims audit — Sec.~4 and Sec.~5

Three categories: $[$REF$]$ needs a citation, $[$MEAS$]$ needs our own
measurement to back it, $[$KEEP$]$ already well-supported.

### Sec.~4 (chunk-size formula)

| # | Claim | Status | Action |
|---|---|---|---|
| 4.1 | "nvCOMP default chunk size on the order of tens of kibibytes" | $[$REF$]$ | already `\cite{nvcomp}`; consider also citing the nvCOMP source-tree default to be precise |
| 4.2 | "32-lane RDNA~3 / 64-lane CDNA wavefronts" | $[$REF$]$ | `\cite{rocm}` |
| 4.3 | "ICCSA characterization observed AMD kernels at $\sim$50\,\% of attainable throughput" | $[$MEAS$]$ | confirm the exact number in `anon_iccsa2026`; rewrite to quote it precisely instead of approximate |
| 4.4 | $W_{\text{sat}}$ values $\{15, 52, 76, 48\}$ MiB | $[$MEAS$]$ | our preliminary sweep; need CSV in the results dir to point to (currently asserted without a figure) |
| 4.5 | "5-fold growth in CU count across CDNA generations" | $[$REF$]$ | AMD product spec or `\cite{rocm}` |
| 4.6 | "RDNA~3 exposes wave32 and wave64" | $[$REF$]$ | `\cite{rocm}` |
| 4.7 | "2.87$\times$ kernel speedup on gfx942 at 16 GiB" | $[$MEAS$]$ | from our sweep; needs the result CSV path in the eval section |
| 4.8 | "LZ4, Snappy, Cascaded within 1.3$\times$ of each other" | $[$MEAS$]$ | needs to be verified across the full matrix; if false, drop or weaken |
| 4.9 | "monotone improvements above $L = 2 \cdot W_{\text{sat}}$" | $[$MEAS$]$ | from our sweep; needs the curve in a figure |

### Sec.~5 (adaptive tiled aggregation)

| # | Claim | Status | Action |
|---|---|---|---|
| 5.1 | "pinned-host allocation $\sim$220 MB/s on the four platforms" | $[$MEAS$]$ | our measurement; could also cite the ROCm host-memory perf note if one exists |
| 5.2 | "single-shot pinned $0.39\times$ to $0.59\times$ baseline" | $[$MEAS$]$ | our sweep CSVs; needs explicit table in Sec.~6 to back this up |
| 5.3 | "literature glosses over allocation cost" | $[$REF$]$ or rewrite | risky claim without a concrete counter-example; either cite a specific paper that excludes setup from its timing window, or soften to "is commonly not reported in the measurement window" |
| 5.4 | "$R_{\text{h2h}} \approx 11$ GB/s, $R_{\text{pcie}} \approx 25$ GB/s" | $[$REF$]$+$[$MEAS$]$ | cite PCIe Gen~4 nominal ($32$ GB/s peak) and the corresponding ROCm bandwidth-test result; our own measurement confirms |
| 5.5 | "$W_{\text{pcie-amort}} \approx 4$ MiB on every target" | $[$MEAS$]$ | our measurement |
| 5.6 | EMA $\alpha = 0.3$ giving "half-life $\sim 2$ tiles" | $[$KEEP$]$ | derived from EMA properties; calculation is correct (half-life $= \ln 0.5 / \ln 0.7 \approx 1.94$) |
| 5.7 | "$\sqrt 2$ cap per refinement step" | $[$REF$]$ or rewrite | design choice; either justify briefly (prevents single noisy sample from doubling the window) or cite a similar online-controller design from the systems literature |
| 5.8 | "$1.32\times$ to $2.26\times$ end-to-end on gfx942" | $[$MEAS$]$ | our sweep CSVs |
| 5.9 | "EMA right-sizes around 80 MiB on gfx942" | $[$MEAS$]$ | our sweep CSVs (need per-call EMA trace, not just final $W$); confirm whether the bench binary emits this |
| 5.10 | "the two optimizations compose additively rather than multiplicatively" | $[$MEAS$]$ | strong claim; verify by comparing $(C_{\text{opt}} \times \text{adaptive})$ end-to-end against the sum of the individual gains; if false, rewrite honestly |

---

## Cross-cutting items

- **Reference audit policy:** new feedback rule worth capturing: every
  numeric or qualitative claim in this paper either cites a source or
  points to a result CSV in `results_archive/`. Apply this on the
  next pass over Sec.~1 and Sec.~2 as well.
- **Naming for ZFP-reversible in tables/figures:** "ZFP-R" for
  reversible, "ZFP-1e-3", "ZFP-1e-4", "ZFP-1e-5" for the fixed-accuracy
  points. Consistent across Sec.~3 enumeration, Sec.~6 results, and
  any captions.
- **Justification for picking $\{10^{-3}, 10^{-4}, 10^{-5}\}$ as the
  three accuracy points:** needs a sentence in Sec.~6 with a reference
  (likely back to `lindstrom2016f3dt` for the tolerance range that
  preserves migrated-image quality on seismic data).

---

## Apply order (suggested)

1. **Sec.~3 reorg** — text-only, low risk, no measurements blocked.
2. **Reference audit fixes in Sec.~4 and Sec.~5** — text-only,
   adds citations and softens the claims that we cannot yet back.
3. **`sweep_canonical.sh` update** — code change, blocked by ARCTO
   ZFP API verification; do once we have an MI300X allocation.
4. **Re-run sweep with new matrix** — once (3) is done.
5. **Sec.~6 (Evaluation) draft** — once the new CSVs are in.
