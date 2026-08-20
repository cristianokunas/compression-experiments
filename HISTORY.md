# What was removed, and how to get it back

This repository is where the campaign history lives. Material that was cleaned
out of the paper artifact repositories during the 2026-08-19 reorganization is
still reachable here, so nothing below is lost — but none of it should be read
as a current result.

The last commit in which everything still existed at its original path is
**`674fe50`**. Everything below is under `paper/ARCTO-optim/` or
`paper/ICCSA26/` at that commit.

```bash
# see what a directory held
git show 674fe50 --stat -- paper/ARCTO-optim/results/<name>
git ls-tree -r 674fe50 --name-only paper/ARCTO-optim/results/<name>

# restore one into the working tree
git checkout 674fe50 -- paper/ARCTO-optim/results/<name>

# read a single file without restoring it
git show 674fe50:paper/ARCTO-optim/analysis/chunk_sweeps.csv
```

## Removed because the conclusions are wrong

Do not restore these to build on. If either line is revisited, start from
scratch — that is the whole reason they were removed rather than archived in
place.

| What | Why |
|---|---|
| ZFP reversible (`RX7900XT_REVERSIBLE_*`, the `*_zfp_reversible*` files inside the `*_FULL_*` campaigns, `results_paper2_lossless_comparison.csv`) | `arctoZFPReversible3D` produced non-lossless output. Worse, the fidelity `FINDINGS.md` concluded reversible *was* lossless, so the material held two opposite conclusions about the same feature. |
| c\* chunk sizing (`*_CHUNK_SWEEP_*`, `cstar_*`, `plot_cstar.R`, `cstar_reframing.md`) | The sweep moved two variables at once — `LZ4Types.h` welds the hash table to the chunk via `HT = min(roundUpPow2(chunk), MAX_HASH_TABLE_SIZE)` — and credited the chunk for what the table was doing. Counters show wave starvation, not the per-chunk cost floor the result claimed. |

## Removed because nothing carries the thread

These measurements are **correct**. They were dropped because the thesis does not
pursue host-side staging: it only pays when the data already sits on disk or on
the host, the aggregation is not free, and it is not the result the work sets out
to deliver.

| What | Notes |
|---|---|
| `*_PINNED_*`, `*_ADAPTIVE_*`, `*_PCIe_*`, `*_SCALING_*`, `*_W16MIB_*` | ten campaigns |
| `*_FULL_*`, `*_PAPER2_*` | cross-node matrices of baseline / pinned / adaptive across three codecs, ~4300 files |
| `microbench/pcie/` | H2D and D2H bandwidth sweep, pageable vs pinned, on three nodes |
| `analysis/plots_presentation/`, `plots_output*`, `plots_paper2_output` | generated figures, including the adaptive and pinned ones |

The headline numbers of this thread do **not** depend on restoring any of it:
they are recorded in the annotations of the `arcto` tags
`paper/arcto-optim-zfp-pinned` (ZFP fixed_rate 19.6 → 32.5 GB/s) and
`paper/arcto-optim-coalesce-pin` (per-codec H2D and total-time speedup tables at
100 MB and 686 MB).

## Removed as superseded tooling

| What | Superseded by |
|---|---|
| `plots_arcto{,_v2,_v3}.R`, `plots_presentation.R`, `plots_paper2_exploratory.R` | their outputs are gone; nothing reads them |
| `consolidate_chunk_sweeps.py`, `consolidate_results.py` | produced CSVs that no surviving script consumes |
| `paper/ARCTO-optim/draft/` | an abandoned SBAC-PAD'26 draft; the maintained manuscript is elsewhere and is a different, narrower document |

## What is still live, and where

| | |
|---|---|
| ICCSA 2026 artifact | `github.com/cristianokunas/iccsa-2026` — paper at [10.1007/978-3-032-30491-9_23](https://doi.org/10.1007/978-3-032-30491-9_23) |
| Optimization paper artifact | `github.com/cristianokunas/arcto-optim` — four campaigns: three profiling, one ZFP fidelity |
| Abandoned but *valid* results | `negative-results/` in this repository |
