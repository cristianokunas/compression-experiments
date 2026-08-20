#!/usr/bin/env python3
"""Motivating figure: per-frame compressibility of the TTI wavefield series."""
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter

frames, zf, lz4, z13, z6 = [], [], [], [], []
with open("/scratch/cakunas/hybrid-motivating/frame_analysis.csv") as f:
    for row in csv.DictReader(f):
        frames.append(int(row["frame"]))
        zf.append(float(row["zero_frac"]) * 100)
        lz4.append(float(row["lz4_ratio"]))
        z13.append(float(row["zfp_acc1e13_ratio"]))
        z6.append(float(row["zfp_acc1e6_ratio"]))

# validated reference palette, light mode, slots 1-3 in fixed order
C_LZ4, C_Z13, C_Z6 = "#2a78d6", "#eb6834", "#1baf7a"
INK, INK2, GRID = "#1a1a19", "#5f5e56", "#e8e7e0"

cross = next(i for i, v in enumerate(lz4) if v < 2.0)  # LZ4 stops paying off

fig, (ax1, ax2) = plt.subplots(
    2, 1, figsize=(8.0, 5.6), dpi=150, sharex=True,
    gridspec_kw={"height_ratios": [2.4, 1.0], "hspace": 0.12})

for ax in (ax1, ax2):
    ax.set_facecolor("white")
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(INK2)
    ax.grid(True, axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(colors=INK2, labelsize=9)

# -- top: compression ratio (log) --
ax1.plot(frames, lz4, color=C_LZ4, lw=2)
ax1.plot(frames, z13, color=C_Z13, lw=2)
ax1.plot(frames, z6, color=C_Z6, lw=2)
ax1.set_yscale("log")
ax1.set_ylabel("razão de compressão (log)", fontsize=10, color=INK)
ax1.yaxis.set_major_formatter(ScalarFormatter())
ax1.set_yticks([1, 2, 5, 10, 50, 200, 1000])
ax1.set_ylim(0.9, 20000)

ax1.axvspan(0, cross, color="#f4f3ee", zorder=0)
ax1.axvline(cross, color=INK2, lw=1, ls=(0, (4, 3)))
ax1.text(cross / 2, 6000, "regime esparso\n(LZ4 lossless rende)", ha="center",
         fontsize=8.5, color=INK2)
ax1.text(52, 6000,
         "regime denso (apenas lossy error-bounded rende)", ha="left",
         fontsize=8.5, color=INK2)

ax1.text(frames[-1] + 1, 0.98, f"LZ4 {lz4[-1]:.2f}×", color=C_LZ4,
         fontsize=9, fontweight="bold", va="center")
ax1.text(frames[-1] + 1, 1.9, f"ZFP 1e-13 {z13[-1]:.1f}×",
         color=C_Z13, fontsize=9, fontweight="bold", va="center")
ax1.text(frames[-1] + 1, 3.9, f"ZFP 1e-6 {z6[-1]:.1f}×",
         color=C_Z6, fontsize=9, fontweight="bold", va="center")
ax1.annotate(f"LZ4 cai abaixo de 2×\n(frame {cross})",
             xy=(cross, 2.0), xytext=(cross + 13, 1.35),
             fontsize=8.5, color=INK,
             arrowprops=dict(arrowstyle="-", color=INK2, lw=0.9))
leg = ax1.legend(["LZ4 (lossless, chunks 64 KiB)", "ZFP fixed-accuracy 1e-13",
            "ZFP fixed-accuracy 1e-6"],
           loc="upper right", bbox_to_anchor=(1.0, 0.88), fontsize=8.5,
           frameon=False, labelcolor=INK)

# -- bottom: zero fraction --
ax2.fill_between(frames, zf, color="#d6d5cc", alpha=0.6, lw=0)
ax2.plot(frames, zf, color=INK2, lw=2)
ax2.axvspan(0, cross, color="#f4f3ee", zorder=0)
ax2.axvline(cross, color=INK2, lw=1, ls=(0, (4, 3)))
ax2.set_ylabel("zeros na grid (%)", fontsize=10, color=INK)
ax2.set_xlabel("snapshot (dump a cada 10 passos de tempo)", fontsize=10,
               color=INK)
ax2.set_ylim(0, 105)
ax2.set_xlim(0, frames[-1] + 12)
ax2.text(frames[-1] * 0.72, zf[-1] + 12,
         f"platô: {zf[-1]:.1f}% (células de halo)", fontsize=8.5,
         color=INK2)

fig.suptitle("A compressibilidade do campo de onda muda de regime durante a "
             "simulação", fontsize=12, color=INK, x=0.02, ha="left",
             fontweight="bold")
ax1.set_title("Fletcher TTI 200³ (grid 240³ com bordas), 1000 passos, 101 "
              "snapshots — razão por snapshot", fontsize=9.5, color=INK2,
              loc="left", pad=8)

fig.savefig("/scratch/cakunas/hybrid-motivating/fig_motivadora.png",
            bbox_inches="tight", facecolor="white")
fig.savefig("/scratch/cakunas/hybrid-motivating/fig_motivadora.pdf",
            bbox_inches="tight", facecolor="white")
print("saved; crossover frame =", cross)
