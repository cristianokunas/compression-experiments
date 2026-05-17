# ICCSA 2026 — paper assets

Source data, R scripts, generated figures, and LaTeX manuscript for:

> **Mind the Gap: Characterizing GPU Data Compression Performance Across
> AMD Architectures** — ICCSA 2026.

The paper compares ARCTO's HIP port of nvCOMP (LZ4, Snappy, Cascaded)
across four AMD GPUs (MI50, MI210, RX 7900 XT, MI300X). Numbers in the
figures come from the runs frozen under `results/` here.

## Directory layout

```
paper/ICCSA26/
├── plots_iccsa.R          v1 -- initial figure set (kept for history)
├── plots_iccsa_v2.R       v2 -- iteration on facets / palette
├── plots_iccsa_v3.R       v3 -- adds heatmaps + asymmetry view
├── plots_iccsa_v4.R       v4 -- CURRENT, used to generate the camera-ready PDFs
├── results_mi50.csv       aggregated per-GPU CSVs read directly by the
├── results_mi210.csv      R scripts (one row per algo × dataset × size,
├── results_rx7900xt.csv   averaged across the 10 benchmark iterations)
├── results_mi300x.csv
├── results/               raw per-run output (one subdir per GPU+timestamp)
│   ├── MI50_20260314_231140/
│   ├── MI210_20260317_193810/
│   ├── RX7900XT_20260311_151030/
│   ├── RX7900XT_20260314_190340/
│   └── MI300X_20260314_230555/
├── plots_output/          camera-ready figures (.pdf + .png) + LaTeX table
├── iccsa2026/             paper LaTeX source (v2 + v3 + CHANGELOG)
└── ICCSA_2026_cristiano.pdf   final submitted PDF
```

## Regenerating the figures

The R scripts were developed and executed inside RStudio with the working
directory set to this folder. They read the four `results_<gpu>.csv`
files at this level and write into `plots_output/`.

### Interactive (RStudio, the original workflow)

1. Open RStudio.
2. `setwd("paper/ICCSA26")` (or open the folder as a project).
3. `source("plots_iccsa_v4.R")`.
4. Figures land in `plots_output/`.

### Headless (Rscript, for CI / re-runs from the shell)

The script header lists the CSV arguments. From inside this directory:

```bash
Rscript plots_iccsa_v4.R \
    results_mi50.csv \
    results_mi210.csv \
    results_rx7900xt.csv \
    results_mi300x.csv
```

R dependencies: `tidyverse`, `scales`.

## Where do the `results_<gpu>.csv` files come from?

Each is the aggregated form of one or more raw runs in `results/`. The
raw runs were produced by `scripts/run_benchmarks_auto.sh` inside the
Singularity image (`build_singularity.sh` → `defhip_benchmark.def`) and
each run yields one CSV per (algorithm, dataset) plus a summary CSV.

To regenerate `results_<gpu>.csv` from scratch:

1. Re-run the benchmark for that GPU through `scripts/run_singularity.sh`
   (or `scripts/deploy_benchmarks.sh` for the multi-host case).
2. Aggregate using `scripts/summarize_results.py` (or the `compare_*`
   helpers in this folder, depending on what column layout the R script
   expects -- inspect the `read_csv` call near the top of `plots_iccsa_v4.R`
   for the exact schema).

## Why are the raw runs tracked in git?

The repo's top-level `.gitignore` excludes `results/` (so day-to-day
benchmark runs do not bloat the repo), but explicitly re-allows
`paper/**/results/` so that the paper's frozen snapshot is reproducible
without external storage. Total size is small (a few MB of CSV + logs).

The aggregated `results_<gpu>.csv` files are tracked unconditionally
because they are the direct inputs to the figures.

## Notes on script versions

- `plots_iccsa.R` (v1) and `plots_iccsa_v2.R`, `_v3.R` are kept as
  historical reference -- you can `diff` against them to see how each
  figure evolved between submission rounds.
- `plots_iccsa_v4.R` is the single source of truth for the camera-ready
  figures. If you need to regenerate a single figure, the section
  comments in the script index them by figure number.
- The four older Python visualization scripts that used to live in
  `scripts/` (`compare_features_mi300x.py`, `compare_two_features.py`,
  `complete_viz_suite.py`, `visualize_feature2_rsf.py`) were
  exploratory and never fed the published figures. They were removed
  alongside the move to this folder.
