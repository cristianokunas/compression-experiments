#!/usr/bin/env python3
"""
Pilot figures for the SBAC-PAD'26 paper, from the lunaris (gfx1100) campaign.

Produces two figures into ../figures/:

  1. modes_cascaded_tti_gfx1100.pdf
     Block A headline: Cascaded compression end-to-end time across input
     sizes for the three transfer modes (baseline / pinned / adaptive),
     on TTI / gfx1100. Annotated with the t_alloc-ms cost per mode at
     4 GiB to expose the single-shot pinned-host trap.

  2. zfp_quality_4gb_gfx1100.pdf
     Block B headline: ZFP compression ratio vs reconstruction PSNR for
     all eleven lossy configs (fixed_accuracy x 4, fixed_rate x 4,
     fixed_precision x 3) at 4 GiB TTI on gfx1100.

Hardware is referred to by gfx<arch> only, never by hostname or testbed
name -- the paper is under double-blind review.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

THIS = Path(__file__).resolve().parent
RESULTS_DIR = THIS.parent.parent / "results" / "lunaris_FULL_20260525_011052"
FIG_DIR = THIS.parent / "figures"
FIG_DIR.mkdir(parents=True, exist_ok=True)

SIZE_ORDER = ["10mb", "100mb", "1gb", "4gb"]
SIZE_BYTES = {"10mb": 10 * 2**20, "100mb": 100 * 2**20,
              "1gb": 2**30, "4gb": 4 * 2**30}

# Common matplotlib style: paper-friendly, no heavy decoration
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


def read_blockA_csv(path: Path) -> dict:
    """Block A CSV (chunked codecs) has 26 columns ending with adaptive_*.
    Reads the single data row (NR==2) and returns key fields."""
    df = pd.read_csv(path)
    r = df.iloc[0]
    return {
        "ratio":             r["Compression ratio"],
        "comp_gbps":         r["Compression throughput (uncompressed) in GB/s"],
        "comp_std_gbps":     r["Comp throughput stddev (GB/s)"],
        "total_ms":          r["Total time (ms)"],
        "comp_time_std_ms":  r["Comp time stddev (ms)"],
        "t_alloc_ms":        r["t_alloc_ms"],
        "peak_pinned_bytes": r["peak_pinned_bytes"],
        "adaptive_windows":  r["adaptive_num_windows"],
    }


def read_blockB_csv(path: Path) -> dict:
    """Block B CSV (zfp_single) emits fidelity metrics."""
    df = pd.read_csv(path)
    r = df.iloc[0]
    return {
        "ratio":         r["Compression ratio"],
        "comp_gbps":     r["Compression throughput (uncompressed) in GB/s"],
        "total_ms":      r["Total time (ms)"],
        "max_abs_diff":  r["Max abs diff"],
        "rmse":          r["RMSE"],
        "psnr_db":       r["PSNR (dB)"],
    }


# ---------------------------------------------------------------------
# Figure 1: modes comparison on Cascaded / TTI
# ---------------------------------------------------------------------

modes      = ["baseline", "pinned", "adaptive"]
mode_color = {"baseline": "#888888", "pinned": "#d95f02", "adaptive": "#1b9e77"}
mode_marker = {"baseline": "o", "pinned": "s", "adaptive": "^"}

rows = []
for size in SIZE_ORDER:
    for mode in modes:
        f = RESULTS_DIR / f"tti_{size}_cascaded_{mode}.csv"
        rec = read_blockA_csv(f)
        rec.update(size=size, mode=mode, bytes=SIZE_BYTES[size])
        rows.append(rec)
df = pd.DataFrame(rows)

fig, ax = plt.subplots(figsize=(3.4, 2.6))
for mode in modes:
    sub = df[df["mode"] == mode].sort_values("bytes")
    ax.errorbar(
        sub["bytes"] / 2**20,
        sub["total_ms"],
        yerr=sub["comp_time_std_ms"],
        marker=mode_marker[mode], color=mode_color[mode],
        markersize=4, linewidth=1.2, capsize=2,
        label=mode,
    )
ax.set_xscale("log")
ax.set_yscale("log")
ax.set_xlabel("Input size (MiB)")
ax.set_ylabel("End-to-end time (ms)")
ax.set_title(r"Cascaded on TTI, gfx1100 (n=30, mean$\pm$stddev)")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="upper left", frameon=False)

# Annotation: alloc-cost reveal at 4 GiB
sub4 = df[df["size"] == "4gb"].set_index("mode")
ann = (f"At 4 GiB:\n"
       f"  baseline t_alloc = 0 ms\n"
       f"  pinned   t_alloc = {sub4.loc['pinned','t_alloc_ms']:.0f} ms\n"
       f"  adaptive t_alloc = {sub4.loc['adaptive','t_alloc_ms']:.0f} ms")
ax.text(0.55, 0.04, ann, transform=ax.transAxes, ha="left", va="bottom",
        fontsize=7, family="monospace",
        bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="gray",
                  alpha=0.85, linewidth=0.5))

out1 = FIG_DIR / "modes_cascaded_tti_gfx1100.pdf"
fig.savefig(out1)
fig.savefig(out1.with_suffix(".png"))
print(f"wrote {out1}")
plt.close(fig)


# ---------------------------------------------------------------------
# Figure 2: ZFP quality scatter at 4 GiB TTI
# ---------------------------------------------------------------------

# Discover ZFP cells at 4gb and parse mode/param from filename
zfp_csv_re = re.compile(r"^tti_4gb_zfp_(acc|rate|prec)([0-9e]+)\.csv$")
zrows = []
for f in sorted(RESULTS_DIR.glob("tti_4gb_zfp_*.csv")):
    m = zfp_csv_re.match(f.name)
    if not m:
        continue
    short, param_raw = m.group(1), m.group(2)
    if short == "acc":
        # acc1e3 -> 1e-3
        mode = "fixed_accuracy"
        param = float(f"{param_raw[0]}e-{param_raw[2:]}")
        label = f"$\\tau$={param:.0e}"
    elif short == "rate":
        mode = "fixed_rate"
        param = int(param_raw)
        label = f"R={param} b/v"
    else:
        mode = "fixed_precision"
        param = int(param_raw)
        label = f"p={param}"
    rec = read_blockB_csv(f)
    rec.update(mode=mode, param=param, label=label)
    zrows.append(rec)
zdf = pd.DataFrame(zrows)

mode_color2 = {"fixed_accuracy": "#377eb8",
               "fixed_rate":     "#e41a1c",
               "fixed_precision":"#4daf4a"}
mode_marker2 = {"fixed_accuracy": "o", "fixed_rate": "s", "fixed_precision": "^"}

fig, ax = plt.subplots(figsize=(3.4, 2.6))
for mode, grp in zdf.groupby("mode"):
    g = grp.sort_values("ratio")
    ax.plot(g["ratio"], g["psnr_db"],
            color=mode_color2[mode], marker=mode_marker2[mode],
            markersize=5, linewidth=0.8, label=mode.replace("_", " "))
    # label each point
    for _, row in g.iterrows():
        ax.annotate(row["label"], (row["ratio"], row["psnr_db"]),
                    xytext=(3, 3), textcoords="offset points",
                    fontsize=6, color=mode_color2[mode])

ax.set_xscale("log")
ax.set_xlabel("Compression ratio (log)")
ax.set_ylabel("PSNR (dB)")
ax.set_title("ZFP quality vs. ratio, TTI 4 GiB, gfx1100")
ax.grid(True, which="both", alpha=0.25, linewidth=0.4)
ax.legend(loc="lower left", frameon=False)

out2 = FIG_DIR / "zfp_quality_4gb_gfx1100.pdf"
fig.savefig(out2)
fig.savefig(out2.with_suffix(".png"))
print(f"wrote {out2}")
plt.close(fig)

print("done")
