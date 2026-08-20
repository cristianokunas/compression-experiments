# Hash-table sizing campaign — lunaris, 2026-08-19

Raw output of the campaign that produced the hash-table finding, rescued from
lunaris on 2026-08-20. Until then it existed only as untracked files on that one
node, alongside an uncommitted patch.

This is a **partial run of Phase 1 and Phase 5** of `../DESIGN.md`, taken before
that design was written. Read it as the evidence that motivated the experiment,
not as the experiment.

## Provenance

| | |
|---|---|
| Node | lunaris, RX 7900 XT (gfx1100, RDNA3, wave32, 84 CUs, 32 waves/CU, L1 32 KB) |
| ROCm | 7.2.3, **bare metal** — not the 7.0.1 Singularity image the methodology chapter declares |
| ARCTO | `61218f5` (`feature/kernel-opt`) plus the `MAX_HASH_TABLE_SIZE` override, now committed as `feat/ht-size-override` |
| Guard | the runner aborts unless a minimal `hipMalloc`+kernel program passes, so a wedged driver cannot produce empty CSVs |

Each result directory carries its own `provenance.txt` with the git HEAD, the
full dirty-state listing, the ROCm path, the device and the input size.
`results_ratio2/` is missing one — its configuration is recoverable from the file
names and from `scripts/run_ratio2.sh`.

## What was measured

| Directory | Grid | Purpose |
|---|---|---|
| `results_htsweep/` | 8 table sizes (128 … 16384 entries) × 2 chunk sizes (8 KiB, 64 KiB) × 5 repetitions, on `large_TTI_1024.bin` (719 MB) | **Decouples table size from chunk size.** This is the measurement that shows the chunk sweep was crediting the wrong variable. |
| `results_ratio/` | the 1 MB compressibility ladder at the inherited 16384-entry table, 3 repetitions | ratio baseline |
| `results_ratio2/` | the same ladder at the small tables | **Checks in exact bytes that a smaller table costs no compression ratio** — the objection that has to be closed before the throughput gain means anything |

The ratio runs consume `tests/data/*_1mb.bin` from the ARCTO repository —
`synth_{zeros,binary,random}`, `tti_rsf_{t000,t050}`, `tti_mid`. Those fixtures
are not used by ctest; this is what they are for.

## Phase 5 result: the smaller table costs no ratio

Verified in exact compressed bytes on MI210, across the compressibility ladder,
comparing every table size against the inherited 16384-entry baseline at chunk
64 KiB:

| Dataset | Ratio | Worst cost, 16384 -> 128 entries |
|---|---|---|
| `synth_binary` | 3.26x | **+0.0075 %** |
| `tti_rsf_t000` (sparse) | 245x | **+0.0000 %** — byte-identical output at every table size |
| `tti_rsf_t050` (dense) | 0.996x | **+0.0003 %** |

The large table was buying nothing on this data. Note also that the dense
wavefield compresses to **0.9961x** — LZ4 slightly *expands* it — which is the
regime where the thesis argues byte-level lossless does not pay, measured here
rather than asserted.

This closes the objection that the throughput gain trades ratio for speed. It
does not settle *why* the gain exists; see `../DESIGN.md`.

## Known gaps against `../DESIGN.md`

- Only two chunk sizes, so the surface is two lines rather than the 8 × 4 grid
  Phase 1 asks for.
- **No hardware counters.** Throughput alone cannot separate "the table fits in
  cache" from any other explanation; the L1 miss traffic that would settle it was
  never collected. Phase 2 exists precisely because this campaign could not
  answer it.
- One architecture. The cross-architecture falsification of Phase 4 is what turns
  the cache explanation from a story into a prediction.
- Aggregated CSVs (mean + stddev per run) rather than per-repetition rows. The
  repetitions are separate files here, which is coarser than the protocol wants
  but recoverable.

## Reproducing

```bash
./scripts/build_ht.sh          # one build per table size
./scripts/run_ht.sh            # REPS / CHUNKS / HTS overridable
./scripts/run_ratio.sh         # ratio ladder, baseline table
./scripts/run_ratio2.sh        # ratio ladder, small tables
```

The scripts hardcode `/ssd/cakunas/arcto` and expect the build directories beside
it; they were written for one node and have not been generalized.
