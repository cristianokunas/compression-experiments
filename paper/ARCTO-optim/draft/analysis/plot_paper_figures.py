#!/usr/bin/env python3
"""
Paper figures for the SBAC-PAD'26 ARCTO submission.

Reads campaigns from ../results/<TAG>/ and produces:

  fig01_speedup_cross_arch.pdf
      Block A: end-to-end speedup of adaptive (and pinned) over the
      pageable baseline, cascaded on TTI, across input sizes, per arch.

  fig02_throughput_cross_arch.pdf
      Block A: compression throughput (GB/s) across modes and input
      sizes, per arch. Shows that pinned and adaptive converge in
      steady-state throughput.

  fig03_alloc_reveal.pdf
      Block A: t_alloc_ms across modes and input sizes. Reveals the
      single-shot pinned-host trap (Sec.~5.1).

  fig04_zfp_ratio_vs_psnr.pdf
      Block B: ZFP fixed_accuracy / fixed_rate / fixed_precision
      compression ratio versus reconstruction PSNR on TTI 4 GiB,
      per arch.

  fig05_zfp_ratio_vs_throughput.pdf
      Block B: ZFP compression throughput versus ratio. Per mode,
      per arch.

  fig06_zfp_ratio_vs_max_abs_diff.pdf
      Block B: ZFP absolute reconstruction error (L_infinity) versus
      ratio. Companion to fig04.

Hardware is referred to by gfx<arch> only -- the paper is under
double-blind review.
"""

from __future__ import annotations

import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

# -----------------------------------------------------------------------
# Campaign registry: (label, gfx<arch>, results dir name)
# -----------------------------------------------------------------------

DRAFT = Path(__file__).resolve().parent.parent          # paper/ARCTO-optim/draft
RESULTS = DRAFT.parent / "results"                       # paper/ARCTO-optim/results
FIG = DRAFT / "figures"                                  # paper/ARCTO-optim/draft/figures
FIG.mkdir(parents=True, exist_ok=True)

CAMPAIGNS = [
    {"arch": "gfx1100", "dir": "lunaris_FULL_20260525_011052",
     "label": "RX 7900 XT (gfx1100)"},
    {"arch": "gfx90a",  "dir": "larochette_FULL_20260525_165539",
     "label": "MI210 (gfx90a)"},
]

# Drop campaigns whose dir is not present (lets the script run with
# partial cross-arch data).
CAMPAIGNS = [c for c in CAMPAIGNS if (RESULTS / c["dir"]).exists()]
print(f"campaigns: {[c['arch'] for c in CAMPAIGNS]}")

SIZE_ORDER = ["10mb", "100mb", "1gb", "4gb", "8gb", "16gb"]
SIZE_BYTES = {"10mb": 10 * 2**20, "100mb": 100 * 2**20,
              "1gb": 2**30, "4gb": 4 * 2**30,
              "8gb": 8 * 2**30, "16gb": 16 * 2**30}

# Colors per arch
ARCH_COLOR = {"gfx1100": "#377eb8", "gfx90a": "#e41a1c",
              "gfx942":  "#4daf4a", "gfx906":  "#984ea3"}

MODE_STYLE = {
    "baseline": dict(ls="-",  marker="o", lw=1.2, ms=4),
    "pinned":   dict(ls="--", marker="s", lw=1.2, ms=4),
    "adaptive": dict(ls=":",  marker="^", lw=1.5, ms=5),
}

plt.rcParams.update({
    "font.size": 9,
    "axes.titlesize": 10,
    "axes.labelsize": 9,
    "legend.fontsize": 8,
    "xtick.labelsize": 8,
    "ytick.labelsize": 8,
    "figure.dpi": 150,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.04,
})


# -----------------------------------------------------------------------
# Readers
# -----------------------------------------------------------------------

def read_blockA(path: Path) -> dict | None:
    if not path.exists():
        return None
    df = pd.read_csv(path)
    if len(df) == 0:
        return None
    r = df.iloc[0]
    return {
        "ratio":            float(r["Compression ratio"]),
        "comp_gbps":        float(r["Compression throughput (uncompressed) in GB/s"]),
        "comp_std_gbps":    float(r["Comp throughput stddev (GB/s)"]),
        "total_ms":         float(r["Total time (ms)"]),
        "comp_time_std_ms": float(r["Comp time stddev (ms)"]),
        "t_alloc_ms":       float(r["t_alloc_ms"]),
    }


def read_blockB(path: Path) -> dict | None:
    if not path.exists():
        return None
    df = pd.read_csv(path)
    if len(df) == 0:
        return None
    r = df.iloc[0]
    return {
        "ratio":        float(r["Compression ratio"]),
        "comp_gbps":    float(r["Compression throughput (uncompressed) in GB/s"]),
        "total_ms":     float(r["Total time (ms)"]),
        "max_abs_diff": float(r["Max abs diff"]),
        "psnr_db":      float(r["PSNR (dB)"]),
    }


# -----------------------------------------------------------------------
# Block A rows -> DataFrame
# -----------------------------------------------------------------------

rows_A = []
for c in CAMPAIGNS:
    for size in SIZE_ORDER:
        for mode in ("baseline", "pinned", "adaptive"):
            f = RESULTS / c["dir"] / f"tti_{size}_cascaded_{mode}.csv"
            rec = read_blockA(f)
            if rec is None:
                continue
            rec.update(arch=c["arch"], label=c["label"],
                       size=size, mode=mode, bytes_=SIZE_BYTES[size])
            rows_A.append(rec)
dfA = pd.DataFrame(rows_A)

# -----------------------------------------------------------------------
# Fig 01: speedup vs baseline (per arch, per mode), Cascaded TTI
# -----------------------------------------------------------------------

fig, ax = plt.subplots(figsize=(3.6, 2.6))
for arch in dfA["arch"].unique():
    sub = dfA[dfA["arch"] == arch]
    base = sub[sub["mode"] == "baseline"].set_index("size")["total_ms"]
    for mode in ("pinned", "adaptive"):
        ss = sub[sub["mode"] == mode].sort_values("bytes_")
        if ss.empty:
            continue
        speedup = ss.apply(
            lambda r: base.loc[r["size"]] / r["total_ms"], axis=1)
        style = MODE_STYLE[mode]
        ax.plot(ss["bytes_"] / 2**20, speedup,
                color=ARCH_COLOR[arch], **style,
                label=f"{arch} / {mode}")
ax.axhline(1.0, color="gray", lw=0.5, ls="-")
ax.set_xscale("log")
ax.set_xlabel("Input size (MiB)")
ax.set_ylabel("End-to-end speedup vs.\\ baseline")
ax.set_title("Cascaded on TTI: speedup over pageable baseline")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="upper left", frameon=False, ncol=1)
fig.savefig(FIG / "fig01_speedup_cross_arch.pdf")
fig.savefig(FIG / "fig01_speedup_cross_arch.png")
plt.close(fig)
print("wrote fig01_speedup_cross_arch")

# -----------------------------------------------------------------------
# Fig 02: throughput across modes, sizes, archs (Cascaded TTI)
# -----------------------------------------------------------------------

fig, ax = plt.subplots(figsize=(3.6, 2.6))
for arch in dfA["arch"].unique():
    sub = dfA[dfA["arch"] == arch]
    for mode in ("baseline", "pinned", "adaptive"):
        ss = sub[sub["mode"] == mode].sort_values("bytes_")
        if ss.empty:
            continue
        style = MODE_STYLE[mode]
        ax.errorbar(ss["bytes_"] / 2**20, ss["comp_gbps"],
                    yerr=ss["comp_std_gbps"],
                    color=ARCH_COLOR[arch], **style,
                    capsize=2, label=f"{arch} / {mode}")
ax.set_xscale("log")
ax.set_xlabel("Input size (MiB)")
ax.set_ylabel("Compression throughput (GB/s)")
ax.set_title("Cascaded on TTI: throughput")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="lower right", frameon=False, ncol=2, fontsize=6.5)
fig.savefig(FIG / "fig02_throughput_cross_arch.pdf")
fig.savefig(FIG / "fig02_throughput_cross_arch.png")
plt.close(fig)
print("wrote fig02_throughput_cross_arch")

# -----------------------------------------------------------------------
# Fig 03: t_alloc reveal (pinned trap), Cascaded TTI
# -----------------------------------------------------------------------

fig, ax = plt.subplots(figsize=(3.6, 2.6))
for arch in dfA["arch"].unique():
    sub = dfA[(dfA["arch"] == arch)]
    for mode in ("pinned", "adaptive"):
        ss = sub[sub["mode"] == mode].sort_values("bytes_")
        if ss.empty:
            continue
        # Treat zeros as a tiny floor so log axis can plot them
        y = ss["t_alloc_ms"].where(ss["t_alloc_ms"] > 0.5, 0.5)
        style = MODE_STYLE[mode]
        ax.plot(ss["bytes_"] / 2**20, y,
                color=ARCH_COLOR[arch], **style,
                label=f"{arch} / {mode}")
ax.set_xscale("log")
ax.set_yscale("log")
ax.set_xlabel("Input size (MiB)")
ax.set_ylabel("$t_{\\mathrm{alloc}}$ (ms, log)")
ax.set_title("Pinned-host allocation cost (the single-shot trap)")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="upper left", frameon=False, ncol=1, fontsize=6.5)
fig.savefig(FIG / "fig03_alloc_reveal.pdf")
fig.savefig(FIG / "fig03_alloc_reveal.png")
plt.close(fig)
print("wrote fig03_alloc_reveal")


# -----------------------------------------------------------------------
# Block B rows -> DataFrame
# -----------------------------------------------------------------------

ZFP_RE = re.compile(r"^tti_(\w+)_zfp_(acc|rate|prec)([0-9e]+)\.csv$")

rows_B = []
for c in CAMPAIGNS:
    for f in sorted((RESULTS / c["dir"]).glob("tti_*_zfp_*.csv")):
        m = ZFP_RE.match(f.name)
        if not m:
            continue
        size, short, raw = m.groups()
        if size not in SIZE_BYTES:
            continue
        if short == "acc":
            mode = "fixed_accuracy"
            param = float(f"{raw[0]}e-{raw[2:]}")
        elif short == "rate":
            mode = "fixed_rate"
            param = int(raw)
        else:
            mode = "fixed_precision"
            param = int(raw)
        rec = read_blockB(f)
        if rec is None:
            continue
        rec.update(arch=c["arch"], label=c["label"],
                   size=size, bytes_=SIZE_BYTES[size],
                   mode=mode, param=param)
        rows_B.append(rec)
dfB = pd.DataFrame(rows_B)

# Restrict to the headline 4-GiB Pareto for the trade-off figures (more
# sizes would overplot). The full per-size matrix is available in the
# CSVs; per-size facets can be added later.
HEAD_SIZE = "4gb"
dfB4 = dfB[dfB["size"] == HEAD_SIZE].copy()

MODE_COLOR_B = {"fixed_accuracy": "#377eb8",
                "fixed_rate":     "#e41a1c",
                "fixed_precision":"#4daf4a"}
MODE_MARKER_B = {"fixed_accuracy": "o", "fixed_rate": "s",
                 "fixed_precision": "^"}


def label_zfp_point(row):
    if row["mode"] == "fixed_accuracy":
        return f"$\\tau$={row['param']:.0e}"
    if row["mode"] == "fixed_rate":
        return f"R={int(row['param'])} b/v"
    return f"p={int(row['param'])}"


# -----------------------------------------------------------------------
# Fig 04: ZFP ratio vs PSNR Pareto, 4 GiB
# -----------------------------------------------------------------------

fig, ax = plt.subplots(figsize=(3.6, 2.6))
for (arch, mode), grp in dfB4.groupby(["arch", "mode"]):
    g = grp.sort_values("ratio")
    color = MODE_COLOR_B[mode]
    marker = MODE_MARKER_B[mode]
    # Distinguish arch with linestyle (solid for first arch, dashed for second)
    ls = "-" if arch == "gfx1100" else "--"
    ax.plot(g["ratio"], g["psnr_db"], color=color, marker=marker,
            linestyle=ls, ms=5, lw=0.9,
            label=f"{mode.replace('_', ' ')} ({arch})")
ax.set_xscale("log")
ax.set_xlabel("Compression ratio (log)")
ax.set_ylabel("PSNR (dB)")
ax.set_title(f"ZFP quality vs.\\ ratio, TTI {HEAD_SIZE.upper()}")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="lower left", frameon=False, fontsize=6.5)
fig.savefig(FIG / "fig04_zfp_ratio_vs_psnr.pdf")
fig.savefig(FIG / "fig04_zfp_ratio_vs_psnr.png")
plt.close(fig)
print("wrote fig04_zfp_ratio_vs_psnr")

# -----------------------------------------------------------------------
# Fig 05: ZFP ratio vs compression throughput, 4 GiB
# -----------------------------------------------------------------------

fig, ax = plt.subplots(figsize=(3.6, 2.6))
for (arch, mode), grp in dfB4.groupby(["arch", "mode"]):
    g = grp.sort_values("ratio")
    color = MODE_COLOR_B[mode]
    marker = MODE_MARKER_B[mode]
    ls = "-" if arch == "gfx1100" else "--"
    ax.plot(g["ratio"], g["comp_gbps"], color=color, marker=marker,
            linestyle=ls, ms=5, lw=0.9,
            label=f"{mode.replace('_', ' ')} ({arch})")
ax.set_xscale("log")
ax.set_xlabel("Compression ratio (log)")
ax.set_ylabel("Compression throughput (GB/s)")
ax.set_title(f"ZFP throughput vs.\\ ratio, TTI {HEAD_SIZE.upper()}")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="upper left", frameon=False, fontsize=6.5)
fig.savefig(FIG / "fig05_zfp_ratio_vs_throughput.pdf")
fig.savefig(FIG / "fig05_zfp_ratio_vs_throughput.png")
plt.close(fig)
print("wrote fig05_zfp_ratio_vs_throughput")

# -----------------------------------------------------------------------
# Fig 06: ZFP ratio vs max_abs_diff (L_infinity error), 4 GiB
# -----------------------------------------------------------------------

fig, ax = plt.subplots(figsize=(3.6, 2.6))
for (arch, mode), grp in dfB4.groupby(["arch", "mode"]):
    g = grp.sort_values("ratio")
    color = MODE_COLOR_B[mode]
    marker = MODE_MARKER_B[mode]
    ls = "-" if arch == "gfx1100" else "--"
    ax.plot(g["ratio"], g["max_abs_diff"], color=color, marker=marker,
            linestyle=ls, ms=5, lw=0.9,
            label=f"{mode.replace('_', ' ')} ({arch})")
ax.set_xscale("log")
ax.set_yscale("log")
ax.set_xlabel("Compression ratio (log)")
ax.set_ylabel("$L_\\infty$ reconstruction error (log)")
ax.set_title(f"ZFP error vs.\\ ratio, TTI {HEAD_SIZE.upper()}")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="lower right", frameon=False, fontsize=6.5)
fig.savefig(FIG / "fig06_zfp_ratio_vs_max_abs_diff.pdf")
fig.savefig(FIG / "fig06_zfp_ratio_vs_max_abs_diff.png")
plt.close(fig)
print("wrote fig06_zfp_ratio_vs_max_abs_diff")

print("done")
