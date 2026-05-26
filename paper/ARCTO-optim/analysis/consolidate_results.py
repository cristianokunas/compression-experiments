#!/usr/bin/env python3
"""
Consolidate per-cell CSVs from one or more ARCTO sweep campaigns into a
single long-format CSV. Output schema is intentionally aligned with the
ICCSA26 paper's per-GPU results CSVs (Algorithm, TestFile, FileSizeBytes,
FileSizeMB, ChunkSize, CompressionRatio, CompThroughputGBs/DecompThroughputGBs,
CompTimeMs, DecompTimeMs, TransferH2DMs, TransferD2HMs, TotalTimeMs,
AvgChunkTimeMs, the *_StdDev columns, NodeName, GPU, GPUArch, EnvLabel,
Iterations, Warmup, Timestamp) so the existing plots_iccsa_v4.R can read
this CSV with minimal changes (only the new Mode/ZfpParam/fidelity
columns need handling).

The input is one or more results directories, each containing per-cell
CSVs produced by `sweep_canonical.sh`:

    <dtype>_<size>_<algo>_<mode>.csv         (lossless byte-level codecs)
    <dtype>_<size>_zfp_<modetag>.csv         (ZFP backend)

Each input CSV has exactly two lines: header + a single data row.

The campaign directory prefix (lunaris/larochette/vianden) is mapped
to GPUArch (gfx*) and EnvLabel (MI50/MI210/MI300X/RX7900XT), and the
NodeName is anonymised to a fixed string to keep the consolidated CSV
double-blind-friendly.

Usage:
    consolidate_results.py <results_dir> [<results_dir> ...] -o all_results.csv
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

# Campaign prefix -> (GPUArch, EnvLabel, GPU marketing name)
ARCH_MAP = {
    "lunaris":    ("gfx1100", "RX7900XT", "AMD Radeon RX 7900 XT"),
    "larochette": ("gfx90a",  "MI210",    "AMD Instinct MI210"),
    "vianden":    ("gfx942",  "MI300X",   "AMD Instinct MI300X"),
}

# ARCTO size label -> (ICCSA26 size word, size in MB, size in bytes)
SIZE_INFO = {
    "10mb":  ("small",   10,    10  * 1024**2),
    "100mb": ("medium",  100,   100 * 1024**2),
    "1gb":   ("large",   1024,  1   * 1024**3),
    "4gb":   ("xlarge",  4096,  4   * 1024**3),
    "8gb":   ("xxlarge", 8192,  8   * 1024**3),
    "16gb":  ("huge",    16384, 16  * 1024**3),
}

# Dataset name in the synthesised TestFile (ICCSA26 used TTI uppercase
# and the synthetics lowercase).
DATASET_TF = {
    "tti":    "TTI",
    "zeros":  "zeros",
    "random": "random",
    "binary": "binary",
}

LOSSLESS_PAT = re.compile(
    r"^(?P<dtype>tti|zeros|random|binary)_"
    r"(?P<size>\d+mb|\d+gb)_"
    r"(?P<algo>lz4|snappy|cascaded)_"
    r"(?P<mode>baseline|pinned|adaptive)\.csv$"
)
ZFP_PAT = re.compile(
    r"^(?P<dtype>tti|zeros|random|binary)_"
    r"(?P<size>\d+mb|\d+gb)_"
    r"zfp_(?P<zfp_mode>acc|prec|rate)(?P<zfp_value>[A-Za-z0-9]+)\.csv$"
)

# Source CSV column indices (0-based). See benchmark_template_chunked.cuh
# and benchmark_zfp_single.cu for the canonical row layout.
COL_LOSSLESS = {
    "ratio":             8,
    "comp_gbps":         9,
    "decomp_gbps":       10,
    "comp_ms":           11,
    "decomp_ms":         12,
    "h2d_ms":            13,
    "d2h_ms":            14,
    "total_ms":          15,
    "avg_chunk_ms":      16,
    "comp_gbps_std":     17,
    "decomp_gbps_std":   18,
    "comp_ms_std":       19,
    "decomp_ms_std":     20,
    "t_alloc_ms":        21,
    "t_memcpy_h2h_ms":   22,
    "peak_pinned_bytes": 23,
    "adaptive_window":   24,
    "adaptive_nwin":     25,
}
COL_ZFP = {
    "ratio":             8,
    "comp_gbps":         9,
    "decomp_gbps":       10,
    "comp_ms":           11,
    "decomp_ms":         12,
    "h2d_ms":            13,
    "d2h_ms":            14,
    "total_ms":          15,
    "avg_chunk_ms":      16,
    "comp_gbps_std":     17,
    "decomp_gbps_std":   18,
    "comp_ms_std":       19,
    "decomp_ms_std":     20,
    "max_abs_diff":      21,
    "rmse":              22,
    "psnr_db":           23,
    "max_rel_err":       24,
    "amplitude_range":   25,
}

OUT_COLS = [
    # ICCSA26-aligned identity & per-cell info
    "Algorithm", "TestFile", "FileSizeBytes", "FileSizeMB", "ChunkSize",
    "CompressionRatio",
    "CompThroughputGBs", "DecompThroughputGBs",
    "CompTimeMs", "DecompTimeMs",
    "TransferH2DMs", "TransferD2HMs", "TotalTimeMs", "AvgChunkTimeMs",
    "CompThroughputStdDev", "DecompThroughputStdDev",
    "CompTimeStdDevMs", "DecompTimeStdDevMs",
    "NodeName", "GPU", "GPUArch", "EnvLabel",
    "Iterations", "Warmup", "Timestamp",
    # ARCTO-specific extras
    "Mode", "ZfpParam",
    "AllocMs", "MemcpyH2HMs",
    "PeakPinnedBytes", "AdaptiveWindowBytes", "AdaptiveNumWindows",
    "MaxAbsDiff", "RMSE", "PSNR", "MaxRelErr", "AmplitudeRange",
    "Campaign",
]

# Defaults for ICCSA26 cols that ARCTO doesn't capture per-cell.
# ChunkSize: ARCTO uses the default 64 KiB unless explicitly overridden
# by the harness; the sweep_canonical.sh passes no -p flag, so 65536.
DEFAULT_CHUNK_SIZE = 65536
DEFAULT_ITERATIONS = 30   # sweep_canonical.sh default
DEFAULT_WARMUP     = 5
ANON_NODE = "anon-host"   # hide hostname for double-blind sharing


def detect_gpu(campaign_name: str) -> tuple[str, str, str]:
    for prefix, (arch, env, gpu) in ARCH_MAP.items():
        if campaign_name.lower().startswith(prefix):
            return arch, env, gpu
    return "unknown", "unknown", "unknown"


def synth_testfile(dataset: str, size_label: str) -> str:
    if size_label not in SIZE_INFO:
        return f"unknown_{dataset}_{size_label}.bin"
    size_word, size_mb, _ = SIZE_INFO[size_label]
    return f"{size_word}_{DATASET_TF.get(dataset, dataset)}_{size_mb}.bin"


def read_data_row(path: Path) -> list[str] | None:
    try:
        with open(path) as f:
            reader = csv.reader(f)
            _header = next(reader, None)
            row = next(reader, None)
        if row is None or len(row) < 16:
            return None
        return row
    except Exception:  # noqa: BLE001
        return None


def _common_fields(gpu_id, campaign, dataset, size_label, ts_hint=""):
    arch, env, gpu_name = gpu_id
    size_word, size_mb, size_bytes = SIZE_INFO.get(size_label, ("", 0, 0))
    return {
        "TestFile":     synth_testfile(dataset, size_label),
        "FileSizeBytes": size_bytes,
        "FileSizeMB":   float(size_mb),
        "ChunkSize":    DEFAULT_CHUNK_SIZE,
        "NodeName":     ANON_NODE,
        "GPU":          gpu_name,
        "GPUArch":      arch,
        "EnvLabel":     env,
        "Iterations":   DEFAULT_ITERATIONS,
        "Warmup":       DEFAULT_WARMUP,
        "Timestamp":    ts_hint,
        "Campaign":     campaign,
    }


def make_lossless_row(filename, row, gpu_id, campaign, ts_hint):
    m = LOSSLESS_PAT.match(filename)
    if not m:
        return None
    d = m.groupdict()
    rec = _common_fields(gpu_id, campaign, d["dtype"], d["size"], ts_hint)
    rec.update({
        "Algorithm":              d["algo"],
        "Mode":                   d["mode"],
        "ZfpParam":               "",
        "CompressionRatio":       row[COL_LOSSLESS["ratio"]],
        "CompThroughputGBs":      row[COL_LOSSLESS["comp_gbps"]],
        "DecompThroughputGBs":    row[COL_LOSSLESS["decomp_gbps"]],
        "CompTimeMs":             row[COL_LOSSLESS["comp_ms"]],
        "DecompTimeMs":           row[COL_LOSSLESS["decomp_ms"]],
        "TransferH2DMs":          row[COL_LOSSLESS["h2d_ms"]],
        "TransferD2HMs":          row[COL_LOSSLESS["d2h_ms"]],
        "TotalTimeMs":            row[COL_LOSSLESS["total_ms"]],
        "AvgChunkTimeMs":         row[COL_LOSSLESS["avg_chunk_ms"]],
        "CompThroughputStdDev":   row[COL_LOSSLESS["comp_gbps_std"]],
        "DecompThroughputStdDev": row[COL_LOSSLESS["decomp_gbps_std"]],
        "CompTimeStdDevMs":       row[COL_LOSSLESS["comp_ms_std"]],
        "DecompTimeStdDevMs":     row[COL_LOSSLESS["decomp_ms_std"]],
        "AllocMs":                row[COL_LOSSLESS["t_alloc_ms"]],
        "MemcpyH2HMs":            row[COL_LOSSLESS["t_memcpy_h2h_ms"]],
        "PeakPinnedBytes":        row[COL_LOSSLESS["peak_pinned_bytes"]],
        "AdaptiveWindowBytes":    row[COL_LOSSLESS["adaptive_window"]],
        "AdaptiveNumWindows":     row[COL_LOSSLESS["adaptive_nwin"]],
        "MaxAbsDiff": "", "RMSE": "", "PSNR": "",
        "MaxRelErr": "", "AmplitudeRange": "",
    })
    return rec


def make_zfp_row(filename, row, gpu_id, campaign, ts_hint):
    m = ZFP_PAT.match(filename)
    if not m:
        return None
    d = m.groupdict()
    rec = _common_fields(gpu_id, campaign, d["dtype"], d["size"], ts_hint)
    rec.update({
        "Algorithm":              "zfp",
        "Mode":                   d["zfp_mode"],
        "ZfpParam":               d["zfp_value"],
        "CompressionRatio":       row[COL_ZFP["ratio"]],
        "CompThroughputGBs":      row[COL_ZFP["comp_gbps"]],
        "DecompThroughputGBs":    row[COL_ZFP["decomp_gbps"]],
        "CompTimeMs":             row[COL_ZFP["comp_ms"]],
        "DecompTimeMs":           row[COL_ZFP["decomp_ms"]],
        "TransferH2DMs":          row[COL_ZFP["h2d_ms"]],
        "TransferD2HMs":          row[COL_ZFP["d2h_ms"]],
        "TotalTimeMs":            row[COL_ZFP["total_ms"]],
        "AvgChunkTimeMs":         row[COL_ZFP["avg_chunk_ms"]],
        "CompThroughputStdDev":   row[COL_ZFP["comp_gbps_std"]],
        "DecompThroughputStdDev": row[COL_ZFP["decomp_gbps_std"]],
        "CompTimeStdDevMs":       row[COL_ZFP["comp_ms_std"]],
        "DecompTimeStdDevMs":     row[COL_ZFP["decomp_ms_std"]],
        "AllocMs": "", "MemcpyH2HMs": "",
        "PeakPinnedBytes": "", "AdaptiveWindowBytes": "", "AdaptiveNumWindows": "",
        "MaxAbsDiff":      row[COL_ZFP["max_abs_diff"]],
        "RMSE":            row[COL_ZFP["rmse"]],
        "PSNR":            row[COL_ZFP["psnr_db"]],
        "MaxRelErr":       row[COL_ZFP["max_rel_err"]],
        "AmplitudeRange":  row[COL_ZFP["amplitude_range"]],
    })
    return rec


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="+", help="campaign result directories")
    ap.add_argument("-o", "--output", default="-",
                    help="output CSV path; '-' for stdout (default)")
    args = ap.parse_args()

    out = sys.stdout if args.output == "-" else open(args.output, "w", newline="")
    writer = csv.DictWriter(out, fieldnames=OUT_COLS)
    writer.writeheader()

    total = 0
    skipped = 0

    for d in args.dirs:
        p = Path(d)
        if not p.is_dir():
            print(f"warning: {d} is not a directory, skipping", file=sys.stderr)
            continue
        gpu_id = detect_gpu(p.name)
        campaign = p.name
        # Use the timestamp suffix of the campaign dir as a timestamp hint
        ts_hint = "_".join(campaign.split("_")[-2:])

        n_dir = 0
        for csv_path in sorted(p.glob("*.csv")):
            row = read_data_row(csv_path)
            if row is None:
                skipped += 1
                continue
            rec = (make_lossless_row(csv_path.name, row, gpu_id, campaign, ts_hint)
                   or make_zfp_row(csv_path.name, row, gpu_id, campaign, ts_hint))
            if rec is None:
                skipped += 1
                continue
            writer.writerow(rec)
            n_dir += 1
            total += 1
        print(f"  {campaign}: {n_dir} rows ({gpu_id[0]}, {gpu_id[1]})",
              file=sys.stderr)

    print(f"total rows: {total}  skipped files: {skipped}", file=sys.stderr)

    if args.output != "-":
        out.close()
        print(f"wrote {args.output}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
