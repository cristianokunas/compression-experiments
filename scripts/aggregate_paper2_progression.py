#!/usr/bin/env python3
"""
Aggregate the paper2 optimization-progression matrix.

For each (GPU x algo x dataset) tuple, walks the committed results.csv
files and builds one row per optimization stage:

  baseline:      pageable H2D + 64K chunks (= ICCSA26 default config)
  +pinned:       coalesce + pinned H2D + 64K chunks (paper2 host-side win)
  +chunk_optim:  pinned + per-algo optimal chunk size (kernel-side win)

Outputs paper/ARCTO-optim/results_paper2_progression.csv with columns:
  GPU, Algo, TestFile, Stage, ChunkSize, CompGBs, DecompGBs, TotalMs,
  Ratio, Speedup_vs_baseline.

The CSV is a drop-in for the same R/Python pipeline that consumes
results_mi300x.csv etc -- one row per (algo, dataset, stage) triple, no
EnvLabel re-encoding needed.
"""

import csv, os, sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
RESULTS = BASE / "paper" / "ARCTO-optim" / "results"
OUT = BASE / "paper" / "ARCTO-optim" / "results_paper2_progression.csv"


def read_csv(path):
    """Return list of dicts, one per data row."""
    rows = []
    if not path.exists():
        return rows
    for r in csv.DictReader(open(path)):
        # Skip FAILED rows
        if r.get("CompressionRatio") in ("FAILED", "PARSE_ERROR", "DRY"):
            continue
        try:
            rows.append({
                "algo": r["Algorithm"],
                "file": r["TestFile"],
                "chunk": int(r["ChunkSize"]),
                "ratio": float(r["CompressionRatio"]),
                "comp": float(r["CompThroughputGBs"]),
                "decomp": float(r["DecompThroughputGBs"]),
                "total": float(r["TotalTimeMs"]),
            })
        except (ValueError, KeyError):
            pass
    return rows


# -- MI300X data sources ------------------------------------------------------

mi300x_baseline = (
    RESULTS / "MI300X_PAPER2_FULL_20260518_030032" /
    "baseline" / "MI300X_20260518_030034" / "results.csv"
)
mi300x_pinned_64k = (
    RESULTS / "MI300X_PAPER2_FULL_20260518_030032" /
    "pinned" / "MI300X_PINNED_20260518_030652" / "results.csv"
)
mi300x_pinned_8k = (
    RESULTS / "MI300X_CHUNK_SWEEP_SMALL_20260518_043136" /
    "pinned_chunk8192" / "MI300X_PINNED_20260518_043229" / "results.csv"
)


# -- RX7900XT data sources ----------------------------------------------------
# All from the same lunaris chunk sweep (single SIF + single build).
# Per-algo optimal chunk: LZ4=16K, Snappy=32K, Cascaded=64K (default).

rx_baseline_64k = RESULTS / "RX7900XT_CHUNK_SWEEP_20260517_235720" / "baseline_chunk65536" / "results.csv"
rx_pinned_64k   = RESULTS / "RX7900XT_CHUNK_SWEEP_20260517_235720" / "pinned_chunk65536" / "results.csv"
rx_pinned_per_algo = {
    "lz4":      RESULTS / "RX7900XT_CHUNK_SWEEP_20260517_235720" / "pinned_chunk16384" / "results.csv",
    "snappy":   RESULTS / "RX7900XT_CHUNK_SWEEP_20260517_235720" / "pinned_chunk32768" / "results.csv",
    "cascaded": RESULTS / "RX7900XT_CHUNK_SWEEP_20260517_235720" / "pinned_chunk65536" / "results.csv",
}


# -- Build progression rows ---------------------------------------------------

def gather_gpu(gpu, baseline_csv, pinned_csv, optim_per_algo):
    """
    optim_per_algo can be a single Path (same for all algos) or a dict {algo: Path}.
    """
    base_rows = {(r["algo"], r["file"]): r for r in read_csv(baseline_csv)}
    pinn_rows = {(r["algo"], r["file"]): r for r in read_csv(pinned_csv)}
    if isinstance(optim_per_algo, dict):
        opt_rows = {}
        for algo, path in optim_per_algo.items():
            for r in read_csv(path):
                if r["algo"] == algo:
                    opt_rows[(r["algo"], r["file"])] = r
    else:
        opt_rows = {(r["algo"], r["file"]): r for r in read_csv(optim_per_algo)}

    out = []
    for key, base in sorted(base_rows.items()):
        algo, fname = key
        # Filter to TTI files only (we have both medium+large there; the full
        # MI300X sweep has 16 files, but for cross-GPU comparison only TTI
        # exists on the lunaris side)
        if "TTI" not in fname:
            continue
        base_total = base["total"]
        for stage_name, src in [
            ("baseline", base_rows),
            ("+pinned",  pinn_rows),
            ("+chunk_optim", opt_rows),
        ]:
            r = src.get(key)
            if not r:
                continue
            spd = base_total / r["total"] if r["total"] > 0 else 0.0
            out.append({
                "GPU": gpu, "Algo": algo, "TestFile": fname,
                "Stage": stage_name, "ChunkSize": r["chunk"],
                "CompGBs": r["comp"], "DecompGBs": r["decomp"],
                "TotalMs": r["total"], "Ratio": r["ratio"],
                "Speedup_vs_baseline": spd,
            })
    return out


rows = []
rows += gather_gpu("MI300X",   mi300x_baseline,   mi300x_pinned_64k, mi300x_pinned_8k)
rows += gather_gpu("RX7900XT", rx_baseline_64k,   rx_pinned_64k,     rx_pinned_per_algo)

# Restrict MI300X to TTI medium + large for direct cross-GPU comparison
# (lunaris sweep is TTI-only)
rows = [r for r in rows if r["TestFile"] in ("medium_TTI_100.bin", "large_TTI_1024.bin")]

# -- Write CSV ----------------------------------------------------------------
fields = ["GPU", "Algo", "TestFile", "Stage", "ChunkSize", "CompGBs",
          "DecompGBs", "TotalMs", "Ratio", "Speedup_vs_baseline"]
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in rows:
        w.writerow({
            **r,
            "CompGBs": f"{r['CompGBs']:.2f}",
            "DecompGBs": f"{r['DecompGBs']:.2f}",
            "TotalMs": f"{r['TotalMs']:.2f}",
            "Ratio": f"{r['Ratio']:.3f}",
            "Speedup_vs_baseline": f"{r['Speedup_vs_baseline']:.2f}",
        })

print(f"wrote {len(rows)} rows -> {OUT.relative_to(BASE)}")

# -- Pretty-print summary table -----------------------------------------------
print()
print("=" * 110)
print("PROGRESSION MATRIX -- speedup is total-time(baseline) / total-time(stage)")
print("=" * 110)
print(f"{'GPU':<10} {'Algo':<10} {'File':<22} {'Stage':<14} {'Chunk':>7} {'Comp':>8} {'Decomp':>8} {'Total':>8} {'vs base':>8}")
print("-" * 110)
prev_key = None
for r in rows:
    key = (r["GPU"], r["Algo"], r["TestFile"])
    if prev_key is not None and prev_key != key:
        print()  # blank line between algo/dataset groups
    prev_key = key
    chunk_label = f"{r['ChunkSize']//1024}K" if r["ChunkSize"] < 1048576 else f"{r['ChunkSize']//1048576}M"
    print(f"{r['GPU']:<10} {r['Algo']:<10} {r['TestFile']:<22} "
          f"{r['Stage']:<14} {chunk_label:>7} "
          f"{r['CompGBs']:>8.2f} {r['DecompGBs']:>8.2f} "
          f"{r['TotalMs']:>8.2f} {r['Speedup_vs_baseline']:>7.2f}x")
