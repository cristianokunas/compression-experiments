#!/usr/bin/env python3
"""
Consolidate the historical chunk-sweep campaigns
(MI300X_CHUNK_SWEEP*, RX7900XT_CHUNK_SWEEP*) into a single long CSV
where each row is one (GPU, algorithm, chunk_size, dataset, size, mode)
measurement. Used by plots_presentation.R to plot the kernel
throughput vs chunk size curve per (algo, GPU).

Each campaign has subdirectories like baseline_chunk<bytes> or
pinned_chunk<bytes>; inside, a results.csv aligned with the ICCSA26
schema (Algorithm, TestFile, FileSizeBytes, FileSizeMB, ChunkSize,
CompressionRatio, CompThroughputGBs, DecompThroughputGBs, CompTimeMs,
DecompTimeMs, TransferH2DMs, TransferD2HMs, TotalTimeMs).

MI300X campaigns add an extra nesting level (MI300X_<ts>/results.csv).
"""

import csv, re, sys
from pathlib import Path

CAMPAIGNS = {
    "RX7900XT_CHUNK_SWEEP_20260517_235720":      ("gfx1100", "RX7900XT"),
    "MI300X_CHUNK_SWEEP_20260518_041914":        ("gfx942",  "MI300X"),
    "MI300X_CHUNK_SWEEP_SMALL_20260518_043136":  ("gfx942",  "MI300X"),
    "MI210_CHUNK_SWEEP_20260527_051510":         ("gfx90a",  "MI210"),
}

CHUNK_DIR_PAT = re.compile(r"^(baseline|pinned)_chunk(\d+)$")
TF_PAT = re.compile(r"^(small|medium|large|xlarge)_(TTI|zeros|random|binary)_\d+\.bin$")

OUT_COLS = [
    "GPUArch", "EnvLabel", "Campaign", "Mode",
    "ChunkSize", "ChunkSizeKiB",
    "Algorithm", "Dataset", "Size", "FileSizeMB",
    "CompressionRatio", "CompThroughputGBs", "DecompThroughputGBs",
    "CompTimeMs", "DecompTimeMs", "TransferH2DMs", "TransferD2HMs", "TotalTimeMs",
]

def find_results_csv(chunk_dir: Path):
    """Return the results.csv path inside a chunk_<N> dir. MI300X campaigns
    nest one more level (MI300X_<ts>/results.csv)."""
    direct = chunk_dir / "results.csv"
    if direct.exists():
        return direct
    for sub in chunk_dir.iterdir():
        if sub.is_dir():
            cand = sub / "results.csv"
            if cand.exists():
                return cand
    return None

def parse_testfile(tf: str):
    m = TF_PAT.match(tf)
    if not m:
        return None, None
    return m.group(2).lower(), m.group(1)  # dataset (lower), size_word

def main():
    base = Path("/ssd/cakunas/compression-experiments/paper/ARCTO-optim/results")
    out = sys.stdout if len(sys.argv) < 2 else open(sys.argv[1], "w", newline="")
    writer = csv.DictWriter(out, fieldnames=OUT_COLS)
    writer.writeheader()

    total = 0
    for campaign, (arch, env) in CAMPAIGNS.items():
        camp_dir = base / campaign
        if not camp_dir.is_dir():
            print(f"warning: missing {camp_dir}", file=sys.stderr)
            continue
        n_camp = 0
        for sub in sorted(camp_dir.iterdir()):
            m = CHUNK_DIR_PAT.match(sub.name)
            if not m:
                continue
            mode = m.group(1)
            chunk = int(m.group(2))
            csv_path = find_results_csv(sub)
            if csv_path is None:
                continue
            with open(csv_path) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    ds, sz = parse_testfile(row["TestFile"])
                    if ds is None:
                        continue
                    rec = {
                        "GPUArch": arch, "EnvLabel": env, "Campaign": campaign,
                        "Mode": mode,
                        "ChunkSize": chunk, "ChunkSizeKiB": chunk // 1024,
                        "Algorithm": row["Algorithm"].lower(),
                        "Dataset": ds, "Size": sz,
                        "FileSizeMB": row.get("FileSizeMB", ""),
                        "CompressionRatio":     row.get("CompressionRatio", ""),
                        "CompThroughputGBs":    row.get("CompThroughputGBs", ""),
                        "DecompThroughputGBs":  row.get("DecompThroughputGBs", ""),
                        "CompTimeMs":           row.get("CompTimeMs", ""),
                        "DecompTimeMs":         row.get("DecompTimeMs", ""),
                        "TransferH2DMs":        row.get("TransferH2DMs", ""),
                        "TransferD2HMs":        row.get("TransferD2HMs", ""),
                        "TotalTimeMs":          row.get("TotalTimeMs", ""),
                    }
                    writer.writerow(rec)
                    n_camp += 1
        print(f"  {campaign}: {n_camp} rows ({arch}, {env})", file=sys.stderr)
        total += n_camp

    print(f"total: {total} rows", file=sys.stderr)
    if out is not sys.stdout:
        out.close()

if __name__ == "__main__":
    main()
