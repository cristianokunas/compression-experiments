#!/usr/bin/env python3
"""
Aggregate LOSSLESS-compression comparison: LZ4 (generic byte) vs
ZFP-Reversible (float-aware) on the same workloads.

Output paper/ARCTO-optim/results_paper2_lossless_comparison.csv with
columns: GPU, Dataset, Algo, ChunkSize, Ratio, CompGBs, DecompGBs,
TotalMs.

Where Algo is one of:
  LZ4-pinned     -- LZ4 in chunked-batched mode with -P at the per-arch
                    optimal chunk size (16K on gfx1100, 8K on gfx942)
  ZFP-Reversible -- arctoZFPReversible3D (GPU-native lossless float
                    compressor, our addition on top of canonical ZFP)

Both are lossless. The point of the comparison is to show which one wins
when the user requires bit-exact recovery -- generic byte compression
vs float-aware lossless transform.

Tells different stories per data type:
  - TTI (real seismic):    LZ4 wins ratio (1.06x), Reversible wins comp speed (5x)
  - zeros:                 Reversible wins both ratio (42x) and comp speed (300+ GB/s)
  - random/binary:         Reversible wins comp speed; ratio depends on data
"""

import csv, os
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
RESULTS = BASE / "paper" / "ARCTO-optim" / "results"
OUT = BASE / "paper" / "ARCTO-optim" / "results_paper2_lossless_comparison.csv"


def read_results_csv(path, expected_algo=None):
    rows = []
    if not path.exists(): return rows
    for r in csv.DictReader(open(path)):
        if r.get("CompressionRatio") in ("FAILED", "PARSE_ERROR", "DRY"): continue
        if expected_algo and r["Algorithm"] != expected_algo: continue
        try:
            rows.append({
                "algo":  r["Algorithm"],
                "file":  r["TestFile"],
                "chunk": int(r["ChunkSize"]),
                "ratio": float(r["CompressionRatio"]),
                "comp":  float(r["CompThroughputGBs"]),
                "decomp":float(r["DecompThroughputGBs"]),
                "total": float(r["TotalTimeMs"]),
            })
        except (ValueError, KeyError): pass
    return rows


# -- Data sources --
# RX 7900 XT LZ4 at optimal chunk size (16K, pinned)
rx_lz4 = read_results_csv(
    RESULTS / "RX7900XT_PAPER2_FULL_20260518_010004" /
    "pinned_16K_lz4" / "RX7900XT_PINNED_20260518_010559" / "results.csv",
    expected_algo="lz4")

# RX 7900 XT ZFP-Reversible
rx_rev = read_results_csv(
    RESULTS / "RX7900XT_REVERSIBLE_20260518_010855" / "results_reversible.csv")

# MI300X LZ4 at optimal chunk size (8K, pinned)
mi_lz4 = read_results_csv(
    RESULTS / "MI300X_PAPER2_FULL_OPTIM_20260518_052839" /
    "MI300X_PINNED_20260518_052841" / "results.csv",
    expected_algo="lz4")

# MI300X ZFP-Reversible: not yet collected (only RX 7900 XT for now)
# Placeholder: report nothing on MI300X reversible side.


out_rows = []
for gpu, lz4_rows, rev_rows in [
    ("RX7900XT", rx_lz4, rx_rev),
    ("MI300X",   mi_lz4, []),
]:
    lz4_by_file = {r["file"]: r for r in lz4_rows}
    rev_by_file = {r["file"]: r for r in rev_rows}
    all_files = sorted(set(lz4_by_file) | set(rev_by_file))
    for fname in all_files:
        if "TTI" not in fname and not any(x in fname for x in ("zeros", "random", "binary")):
            continue
        l = lz4_by_file.get(fname)
        rv = rev_by_file.get(fname)
        if l is not None:
            out_rows.append({
                "GPU": gpu, "Dataset": fname, "Algo": "LZ4-pinned",
                "ChunkSize": l["chunk"], "Ratio": l["ratio"],
                "CompGBs": l["comp"], "DecompGBs": l["decomp"],
                "TotalMs": l["total"],
            })
        if rv is not None:
            out_rows.append({
                "GPU": gpu, "Dataset": fname, "Algo": "ZFP-Reversible",
                "ChunkSize": 0, "Ratio": rv["ratio"],
                "CompGBs": rv["comp"], "DecompGBs": rv["decomp"],
                "TotalMs": rv["total"],
            })

# Write CSV
fields = ["GPU", "Dataset", "Algo", "ChunkSize", "Ratio", "CompGBs", "DecompGBs", "TotalMs"]
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    for r in out_rows:
        w.writerow({
            **r,
            "Ratio":    f"{r['Ratio']:.3f}",
            "CompGBs":  f"{r['CompGBs']:.2f}",
            "DecompGBs":f"{r['DecompGBs']:.2f}",
            "TotalMs":  f"{r['TotalMs']:.2f}",
        })
print(f"wrote {len(out_rows)} rows -> {OUT.relative_to(BASE)}")
print()

# Pretty-print: pair LZ4 and Reversible per dataset
print("=" * 110)
print("LOSSLESS COMPARISON -- LZ4-pinned (best chunk per arch) vs ZFP-Reversible (GPU-native float-aware)")
print("=" * 110)
print(f"{'GPU':<10} {'Dataset':<26} {'Algo':<16} {'Chunk':>7} {'Ratio':>7} {'Comp GB/s':>10} {'Decomp GB/s':>12} {'Total ms':>9}")
print("-" * 110)
prev_key = None
for r in out_rows:
    key = (r["GPU"], r["Dataset"])
    if prev_key is not None and prev_key != key:
        print()
    prev_key = key
    chunk_label = f"{r['ChunkSize']//1024}K" if r["ChunkSize"] else "-"
    print(f"{r['GPU']:<10} {r['Dataset']:<26} {r['Algo']:<16} "
          f"{chunk_label:>7} {r['Ratio']:>7.3f} "
          f"{r['CompGBs']:>10.2f} {r['DecompGBs']:>12.2f} {r['TotalMs']:>9.2f}")
