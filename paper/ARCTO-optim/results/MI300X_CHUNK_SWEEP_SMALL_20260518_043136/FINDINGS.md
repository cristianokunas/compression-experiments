# MI300X smaller-chunk sweep (8K-64K)

Follow-up to `MI300X_CHUNK_SWEEP_20260518_041914/` (which swept 64K-16M
and found that larger always loses). This sweep explores the OTHER
direction: chunk sizes smaller than the default 64K.

Same setup, same SIF (arcto@8599fbf), same TTI workloads, baseline +
pinned modes. Only the `-p chunk_size` flag varies.

Full results table + analysis is unified in the sibling directory's
`FINDINGS.md`. Headline copied here for self-contained reference:

| Algo (medium TTI) | 64K (default) | **8K**       | Speedup |
|---|---:|---:|---:|
| LZ4 compress      | 4.89  GB/s    | **14.02 GB/s** | **2.87x** |
| Snappy compress   | 59.82 GB/s    | 95.30 GB/s   | 1.59x   |
| Cascaded compress | 90.60 GB/s    | 123.73 GB/s  | 1.37x   |

Compression ratio unchanged (LZ4 1.06, Snappy 1.05) or slightly
reduced (Cascaded -3%).

Mechanism: at 8K chunks on 100MB input we generate 12800 chunks =
12800 waves, exceeding MI300X's ~9728 wave slots and saturating the
GPU. At 64K we generated only 1600 waves (16% wave-slot demand) --
left 84% of the GPU idle on every dispatch.

## Files

```
{baseline,pinned}_chunk{8192,16384,32768,65536}/MI300X_*/results.csv
```

The chunk=65536 entries are duplicates of the same chunk size in the
sibling dir (re-run as a sanity check that nothing drifted between
the two sweeps); they match within 1%.
