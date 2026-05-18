# MI300X PMC counters -- LZ4 vs Cascaded hot-kernel occupancy

Phase 2 of the profiling sequence started in
`MI300X_PROFILE_20260518_033428/`. PMC counters (OccupancyPercent,
VALUUtilization, MemUnitStalled, GRBM_GUI_ACTIVE, SQ_BUSY_CYCLES,
SQ_WAVES) collected via `rocprofv3 --pmc` for the hot compress and
decompress kernels of LZ4 and Cascaded on the same medium TTI 100MB
workload.

See `../MI300X_PROFILE_20260518_033428/FINDINGS.md` for the full
analysis and what-it-means-for-paper2 discussion. This directory holds
the raw PMC CSVs.

## Headline numbers

| Metric            | LZ4 comp  | Cascaded comp | LZ4 decomp | Cascaded decomp |
|---|---:|---:|---:|---:|
| Workgroup_Size    | **64**    | 128           | 128        | 128             |
| SQ_WAVES          | **1600**  | **3200**      | 1600       | 3200            |
| OccupancyPercent  | **9.35%** | **15.71%**    | 3.57%      | 6.35%           |
| VALUUtilization   | **94.54%**| 93.19%        | 96.77%     | 75.47%          |
| MemUnitStalled    | 2.29%     | 5.47%         | 5.36%      | 5.21%           |
| LDS_Block_Size    | 512 B     | 13824 B       | 1024 B     | 13312 B         |

## Diagnosis (1-paragraph)

LZ4 compress launches one wave per block (workgroup=64 on wave64
MI300X), giving 1600 total waves vs Cascaded's 3200. With MI300X
offering ~9700 wave slots, both kernels are wave-count-starved, but
LZ4 cuts the deficit in half. VALU utilization is already 94%+ on LZ4
when a wave runs -- the issue is not what the wave does, it's that not
enough waves exist to keep the GPU full. Fix: pack N chunks per block
(blockDim.x = N x warpsize) so the same 1600 chunks dispatch N x 1600
waves.

## Files

```
lz4/pmc_1/lz4_pmc_counter_collection.csv          -- one row per (dispatch, counter)
lz4/pmc_1/lz4_pmc_agent_info.csv                  -- GPU agent enumeration
cascaded/pmc_1/cascaded_pmc_counter_collection.csv
cascaded/pmc_1/cascaded_pmc_agent_info.csv
```

To parse the per-counter aggregates, the CSV has commas inside quoted
template kernel names so use a real CSV reader:

```python
import csv, statistics
from collections import defaultdict
metrics = defaultdict(list)
for r in csv.DictReader(open("lz4/pmc_1/lz4_pmc_counter_collection.csv")):
    if "lz4CompressBatch" in r["Kernel_Name"]:
        metrics[r["Counter_Name"]].append(float(r["Counter_Value"]))
for m, vs in sorted(metrics.items()):
    print(f"{m:20s} = {statistics.mean(vs):.4f}  (n={len(vs)})")
```
