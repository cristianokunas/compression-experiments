# Experiment log — LZ4 compress path on AMD

Every attempt at optimizing the ARCTO compression kernels, kept or reverted, with
the hypothesis that motivated it and what the measurement actually said.

**Reverted attempts stay in this log.** A loop that records only its successes
cannot tell you which ground has already been walked, and this project has
already paid for that twice: the chunk-packing attempt was implemented, measured
neutral and archived in a tag message, then months later described as still
pending; and the `c*` result was carried as complete long after the variable it
credited had been shown to be confounded.

Protocol, branch and commit rules, and the correctness gate are in
[`OPTIMIZATION-LOOP.md`](OPTIMIZATION-LOOP.md).

## Verdict vocabulary

| Verdict | Meaning |
|---|---|
| `KEPT` | measured a gain, correctness held, merged |
| `REVERTED` | no gain or a regression on the target architecture; change backed out |
| `SUPERSEDED` | the measurement stands but the explanation was wrong, so the result no longer supports what it was cited for |
| `OPEN` | designed, not yet measured |

---

## E01 — `__launch_bounds__` tied to real block sizes

| | |
|---|---|
| Commit | `a3967f3` |
| Verdict | **KEPT** |

**Hypothesis.** Declared launch bounds that do not match the block the kernel is
actually launched with make the compiler reserve registers for a wider block than
exists, costing occupancy for nothing.

**Post-mortem.** Held. Cheap, architecture-neutral.

**Revisit in the loop.** Confirm with `rocprofv3 --kernel-trace` that the VGPR
count per kernel actually dropped, rather than inferring it from the source
change. This was landed before the counter discipline existed, so the mechanism
is assumed rather than measured.

---

## E02 — `__restrict__` on kernel and stream pointer parameters

| | |
|---|---|
| Commit | `cf40a20` |
| Verdict | **KEPT** |

**Hypothesis.** Without `__restrict__` the compiler must assume the input and
output buffers may alias, forcing reloads it could otherwise hoist.

**Revisit in the loop.** Same gap as E01: verify against the generated assembly
that loads were actually hoisted. The ROCm case study treats reading the emitted
`.s` as a first-class check that a source change reached the binary, and neither
E01 nor E02 was validated that way.

---

## E03 — Runtime wavefront-size guard in the batched entry points

| | |
|---|---|
| Commit | `9ced960` |
| Verdict | **KEPT** (correctness, not performance) |

**Hypothesis.** `USE_WARPSIZE_32` is a build-time switch with no runtime check, so
a library built for wave32 and run on a wave64 part fails silently rather than
loudly.

**Revisit in the loop.** Not a performance attempt. Keep as a guard; it protects
every measurement that follows from a whole class of silent wrong answers.

---

## E04 — Drop `warpMatchAny` from the compress hot loop

| | |
|---|---|
| Commit | `2e2b74e` |
| Verdict | **KEPT** |

**Hypothesis.** The emulation of `__match_any` is an O(wavesize) loop in LDS with
two `syncwarp` per hash insertion, and the compress path does not need its full
generality.

**Revisit in the loop.** This is the change the `archive/wave64-n4-neutral` tag
points at as "the real fix" after chunk packing failed (see E06). Its interaction
with E08 is unmeasured: if the clear loop dominates, the gain from removing
`match_any` may be masked, and the two should be measured together as well as
apart.

---

## E05 — Pin compress kernel to the 64-VGPR occupancy step on wave64

| | |
|---|---|
| Commit | `e3293a1` |
| Verdict | **KEPT** (wave64) |

**Hypothesis.** CDNA occupancy moves in discrete VGPR steps; sitting just above a
step boundary costs a whole wave slot per SIMD for a handful of registers.

**Revisit in the loop.** Re-read `OccupancyPercent` before and after on the
current source. Several later changes touched register pressure, so the kernel
may no longer sit where this commit placed it.

---

## E06 — Pack N chunks per block to lift wave count (`N=4`)

| | |
|---|---|
| Commit | `84423b4`, tagged `archive/wave64-n4-neutral` |
| Verdict | **REVERTED** |

**Hypothesis.** Profiling on MI300X measured `OccupancyPercent` at 9.35 % against
roughly 9728 wave slots, with `VALUUtilization` already at 94.54 %. The kernel
launched one wave per block, so the deficit looked like wave count, not wave
efficiency. Predicted effect of `N=4`: occupancy 9.35 % to about 37 %, throughput
4.67 to 18-20 GB/s.

**Measurement.** Neutral on MI300X. `rocprofv3` confirmed the geometry change took
effect and the kernel time was unchanged at about 21.8 ms. Sanity-validated on
gfx1100 with ratio and throughput preserved.

**Post-mortem.** The tag concluded that compress is VALU-bound per CU and that the
wave-starvation hypothesis was refuted. Under E08 the neutral result is expected
for a different reason: initialization work is per chunk, so changing the launch
geometry cannot reduce it. Two accounts predict the same null result here, which
is why this experiment alone does not decide between them.

**Revisit in the loop.** Re-run `N=4` **on top of** a build where the clear loop
has been removed (E08). If the clear loop was masking the occupancy gain, `N=4`
stops being neutral. If it stays neutral, occupancy genuinely is not the lever and
E08's prediction narrows.

---

## E07 — Wave32-only copy vectorization, hybrid repeat, warp LSIC

| | |
|---|---|
| Commits | `df13f11` (LDS claim table, wave64), `61218f5` (wave32 set) |
| Verdict | **KEPT, architecture-gated** |

**Measurement.** LDS 256-bucket claim table replacing the 64-wide all-to-all
intra-warp twin scan: MI300X 4.85 to 11.7 GB/s at 64K. gfx1100 decompression of
zeros about +20 %.

**Post-mortem.** The central lesson of that session: **wave64 and CDNA3 rejected
every vectorized-copy, doubling and warp-LSIC variant in decompression**, from
−5 % to −43 %, to the point that even function indirection over an identical loop
regressed. The wave64 decompress path kept the original loops verbatim.

**Revisit in the loop.** This is the standing reason every attempt must be measured
on both wave widths before being generalized. Treat any single-architecture gain
as provisional until the other width is measured.

---

## E08 — Hash table sizing, decoupled from chunk size

| | |
|---|---|
| Commit | `f3e70b7` (branch `feat/ht-size-override`, the build-time knob) |
| Data | `ht-occupancy/campaign-2026-08-19/` |
| Verdict | **KEPT** as a measured effect; the **explanation is OPEN** |

**Hypothesis.** `LZ4Types.h` computes `HT = min(roundUpPow2(chunk), MAX_HASH_TABLE_SIZE)`,
welding table size to chunk size. Decoupling them should show which of the two the
earlier chunk sweeps were actually measuring.

**Measurement.** At a fixed 64 KiB chunk, shrinking only the table:

| GPU | inherited (16384) | tuned | gain |
|---|---|---|---|
| gfx1100 | 6.88 GB/s | 12.74 GB/s | +85 % |
| gfx90a (MI210) | 2.40 GB/s | 44.28 GB/s | **+1745 %** |

Ratio cost verified in exact bytes across the compressibility ladder: worst case
+0.0075 %, and byte-identical output on the sparse TTI.

**Revisit in the loop.** The effect is solid; the cause is not. See E10.

---

## E09 — Cache-residency explanation for E08

| Attempt | Commit | Verdict |
|---|---|---|
| formula test on rescued cross-arch data | (analysis only) | wrongly called SUPERSEDED on 2026-08-20 |
| re-validation via marginal gains | (analysis only) | **REOPENED — core prediction supported on 3/3 architectures** |
| A4 — probe-footprint discriminator | `34e623e` | **VALIDATED on gfx1100**: line locality confirmed, collision account refuted. **wave64 first run INVALIDATED** — the knobs hijacked the LDS claim-table hash (58-byte deviation caught by the gate) |
| A5 — knobs moved to a table-only slot function | `28891df` | **VALIDATED**: byte-identity restored on wave64; medians unchanged, so the wave64 findings stand |
| A4 clean replay on wave64 | `28891df` builds | **verdict is per-architecture** — see below |

**Hypothesis.** Each wave carries its own table, so the governing quantity is the
aggregate footprint of concurrently resident waves against the per-CU vector
cache, predicting a knee at `table_bytes ≈ L1_bytes / waves_per_CU`.

**First reading (wrong).** The optimum never turned over on gfx1100 or gfx906 —
throughput kept rising to the smallest size tested — and this was read as "no
knee, therefore refuted". That treated the knee as a plateau. The observable a
residency model actually predicts in a multi-level hierarchy is the collapse of
the **marginal gain per halving**, not a hard flat.

**Re-validation (2026-08-20, prompted by the user).** Marginal gain per halving,
chunk 64 KiB, dense TTI:

| GPU | predicted knee | measured inflection |
|---|---|---|
| gfx1100 | 512 | gain **rises** to 1.49x/halving into 1024→512, then collapses to 1.11x and 1.09x. Exact. |
| gfx90a (MI210) | 256 | accelerates into **3.89x** at 512→256. Exact — but 256 is the smallest size the sweep measured. |
| gfx906 (MI50) | ~205 | peaks at 1.40x at 512→256, decays to 1.21x below. Prediction inside the interval. |

The occupancy assumption in the denominator also holds here: these inputs
oversubscribe the wave slots 3.5–4x (10,974 chunks vs 2,688 slots on gfx1100),
unlike the wave-starved 100 MB MI300X case. Self-consistent.

**Current state.** The core quantitative prediction locates the inflection on all
three architectures. What the strict model does not explain, and remains open:

1. the **sub-knee residual**, a real 9–20 % per halving below the knee on gfx1100
   and gfx906;
2. **MI210 below 256 entries was never measured** — "optimum at 256" is partly a
   sweep-range artifact; ht128 and ht64 are missing there;
3. no cache **hit rate** has ever been measured directly (PMC dead on gfx1100
   bare metal; possible on CDNA).

**Attempt A4 result** (`34e623e`, `results_a4/`, 30 reps). The gate passed
perfectly: contig128, spread128 and real ht128 emit **byte-identical output** on
all six ladder files, so the three builds do identical algorithmic work and only
the memory layout of the probes differs. Throughput:

| variant | touched lines/wave | median |
|---|---|---|
| contig128 (allocated 16384) | 4 | **30.75 GB/s** ≈ real ht128 (30.94) |
| spread128 (allocated 16384) | 128 | **14.63 GB/s** |

The collision-age account predicted spread ≈ contig and is **refuted**: a 2.1x
gap with byte-identical work. The line-residency account predicted the 8 KB-line
footprint range and is **confirmed**: 14.63 lands between ht2048 (12.74) and
ht1024 (17.16). And contig ≈ real ht128 shows the **allocated** size is
irrelevant — the **touched** line set is the governing quantity, above and below
the knee. Together with the inflection match on 3/3 architectures, E09 now
stands as: probe cache-line footprint per wave against the per-CU cache governs
LZ4 compress throughput on this data, with the knee at L1/waves and a smooth
line-count effect below it.

The A4 knob stays on the campaign branch; it compiles to the original behavior
exactly when the mask is 0, so it is instrumentation, not a code change to merge.

**Wave64 replay (2026-08-20, MI50 `results_a5_mi50/`, MI210 `results_mi210_loop/`,
container-first on std-env nodes, no kadeploy).** The touched-lines account does
**not** transfer to wave64 as-is. With byte-identical output across all variants:

| GPU | real ht128 | contig128 (4 lines, 32 KiB-aligned tables) | spread128 (128 lines) |
|---|---|---|---|
| gfx1100 (wave32) | 30.94 | 30.75 | 14.63 |
| gfx90a MI210 | 58.79 | 28.52 | 3.26 |
| gfx906 MI50 | 6.94 | **0.82** | 2.47 |

On gfx906 contig is 8.5x slower than the identically-working packed ht128, and
slower than the full table; on gfx90a it costs half. The per-wave touched set
cannot explain this; the **global address layout across concurrent waves** can,
and E12/A6 confirmed it. The mechanism therefore has two separable layers:
**footprint/residency** (the L1/waves knee, dominant on wave32 and for large
tables everywhere) and **channel/bank conflicts from power-of-two-aligned
strides** (GCN/CDNA, dominant when probes concentrate on same-offset lines).

**MI210 below 256, closed.** This lineage's full curve (30 reps, dense TTI
513 MB, chunk 64K): 16384 → 2.43, 512 → 12.04, 256 → 45.96, 128 → 58.79,
64 → **63.92 GB/s** (26x over inherited). The old "optimum at 256" was a
sweep-range artifact, as suspected; marginal gains collapse right after the
predicted knee (3.82x → 1.28x → 1.09x), the same post-knee tail shape as the
other two architectures. Anchors replicate the old campaign (2.43≈2.40,
45.96≈44.28) across lineages and across the container-first flow.

---

## E12 — Allocation-stride channel conflicts (A6)

| Attempt | Commit | Verdict |
|---|---|---|
| A6 — `ARCTO_LZ4_TABLE_PAD_ENTRIES` stride-pad knob | `ca26a31` | **mechanism VALIDATED on gfx906; production-neutral on gfx90a small tables** |

**Hypothesis.** On GCN/CDNA the contig128 anomaly is memory-channel or bank
conflict: per-chunk tables sit at power-of-two-aligned strides, so thousands of
concurrent waves hammer address-congruent lines. Padding the stride by one cache
line (32 entries, 64 B) breaks the congruence without touching the table.

**Measurement (MI50, `results_a6_mi50/`).** Both predictions registered before
the run landed:

| build | without pad | with pad |
|---|---|---|
| contig128 | 0.82 GB/s | **8.20** — a 10x jump, above real ht128 (6.94) |
| ht16384 | 1.77 | 1.78 — nothing, the full-table cost is footprint |

Output bytes unchanged. On MI210, pad over the packed small tables is neutral
(ht64 63.92 → 64.26; ht128 58.79 → 58.01): dense packing already decorrelates
the channels, so the conflict layer does not bite the production layout there.

**gfx1100 preliminary (smoke conditions).** The tooling smoke test doubled as
the wave32 pad probe: ht128 vs ht128+pad32 at 65 MB input, 5 reps, measured
0.93x — a slight regression rather than the predicted neutrality, under
undersubscribed conditions (1040 chunks vs 2688 slots). Needs the standard
protocol (513 MB, 30 reps) before a verdict; recorded in
`results_smoke_gfx1100_pad/`, which also carries the first automatic
node-snapshot.

**Counter confirmation (2026-08-20, neowise-10, sudo-g5k, GPU 1,
`results_pmc_matrix_mi50/`).** The discovery that unlocked it: `sudo-g5k` on a
std-env node collects real PMC values — no kadeploy needed — and the RDNA
counter names were the wrong ones for GCN: on Vega the L2 block is `TCC_*`, not
`GL2C_*` (`--list-avail` stays empty even as root; use known names). The matrix
on six builds, identical work (`SQ_WAVES` = 3,120 in every one):

| build | TCC_HIT | TCC_MISS | miss | kernel t |
|---|---|---|---|---|
| ht128 (packed) | 132.2 M | 11.5 M | 8 % | 297 ms |
| ht16384 | 128.2 M | **462.2 M** | 78 % | 1636 ms |
| contig128 (aligned 32 KiB) | 66.9 M | 32.9 M | 33 % | **3073 ms** |
| spread128 | 196.3 M | 168.9 M | 46 % | 1225 ms |
| contig128+pad | 88.0 M | 12.1 M | 12 % | **245 ms** |
| ht16384+pad | 128.4 M | 462.1 M | 78 % | 1628 ms |

Both layers now have their **direct hardware signature**:

- **Footprint** (E09): misses scale with table size, 11.5 M to 462 M (40x), and
  time follows. The pad leaves the full table's counters untouched, a third
  confirmation that the large-table cost is footprint alone.
- **Conflict** (E12): contig128 has **14x fewer misses than ht16384 yet runs
  1.9x slower** — misses cannot explain it; and one cache line of stride padding
  makes it 12.5x faster at a similar access pattern. Serialization without
  misses is exactly the predicted conflict signature, now measured.

**Pad on production layouts, final:** standard protocol on gfx906 gives
ht128+pad at 0.95x (6.54 vs 6.86 GB/s, `results_pad_mi50_std/`, first real use
of `commit-sweep.sh`), gfx1100 smoke gave 0.93x, MI210 gave 1.00x. Verdict:
**the pad is a mechanism probe, not an optimization** — not adopted.

**Open nuance, quantified but unexplained:** contig+pad reaches the L2 *less*
than packed ht128 (100 M vs 143.7 M accesses) and beats it (245 vs 297 ms;
throughput 8.20 vs 6.94). Candidate: L1 set-aliasing between 256 B-packed
tables. Worth one dedicated attempt if the packed small-table layout becomes
the production default on GCN.

**Replication note:** ht128 measured 6.94 on neowise-9 and 6.86 on neowise-10,
different nodes, same protocol.

**CDNA2 counter matrix (larochette-1, sudo-g5k, `results_pmc_matrix_mi210/`).**
The per-CU L1 evidence E09 was missing, now measured directly on the
architecture where the knee hit exactly. `TCP_TCC_READ_REQ` (L1 misses to L2),
same input, identical `SQ_WAVES`:

| build | L1→L2 reads | TCC_MISS (L2) | profiled kernel t |
|---|---|---|---|
| ht64 | 12.2 M | — | 5.98 ms/disp-set |
| ht128 | 20.1 M | 4.39 M | 193 ms |
| ht256 | 61.3 M | 4.40 M | 196 ms |
| ht512 | 118.3 M | 4.47 M | 202 ms |
| ht16384 | 315.4 M | **389.4 M** | 2515 ms |
| contig128 | 20.1 M | 5.2 M | 199 ms |
| spread128 | 158.2 M | 107.7 M | 1570 ms |

Three readings:

1. **L1 misses scale with table size**, 12 M to 315 M — the footprint layer
   measured at the per-CU cache itself, not inferred from L2.
2. **The knee moves with occupancy, exactly as the denominator says.** This
   matrix ran at `-x 64` (about 10 concurrent waves per CU instead of 32), and
   the model then predicts the knee at 16 KB / 10 ≈ 800 entries — and indeed
   ht512 is still flat here (202 ms, L2 misses unchanged) while the production
   run at full saturation put the cliff between 512 and 256. Same silicon, same
   code, knee position tracking `L1 / concurrent_waves`. An unplanned second
   confirmation with the denominator actually varied.
3. **Conflicts are a contention phenomenon**: contig128 shows no penalty at low
   concurrency (199 ms ≈ ht128) yet costs 2x at production saturation — the
   serialization needs many waves hammering the aligned channels.

## E13 — L1 set-aliasing of packed tables (gfx906)

| Attempt | Commit | Verdict |
|---|---|---|
| A7 — stride sweep on real ht128, pads {0, 32, 8160, 16288} | `ca26a31` builds | **REFUTED, and the production question closed** |

**Measurement** (`results_e13_mi50/`, 30 reps, 513 MB, plus TCC counters per
stride): throughput 6.81 / 6.54 / 6.47 / 6.48 GB/s — packed (pad 0) is best,
every pad slightly negative; and L2 accesses are **flat at ~143.5 M across all
strides**, refuting the aliasing account (packing costs no extra L1 traffic).

Production verdict for gfx906: the plain packed small table stands. The
contig+pad 8.20 GB/s anomaly does **not** transfer to the real path
(ht128 at the identical 32 KiB + 64 B stride gives 6.48) and remains open as a
curiosity confined to the masked-hash instrumentation build; deprioritized, no
production relevance.

---

## E10 — Per-chunk hash-table clear loop as the real cost

| Attempt | Commit | Verdict |
|---|---|---|
| A1 — clear loop removed outright | `b9671c5` | **FAILED THE GATE** on gfx1100: illegal memory access, refined into A2 |
| A2 — A1 plus a stale-entry guard in `isValidHash` | `b48397c` | **REVERTED** on gfx1100 (`422ec6f`): gate passed, gain 1.00x |

**E10 verdict: REFUTED on gfx1100** (2026-08-20, 30 reps, TTI 719 MB, both chunk
sizes, `results_a2_ab/`). With the clear loop gone: ht16384 6.84 GB/s against a
6.87 baseline; ht128 30.08 against 30.94. Ratio byte-identical across the ladder
and round-trip bit-exact, so the removal is *sound* — it just does not pay. And
table size still governs with no clearing on either side (6.84 vs 30.08), so the
monotone cost is not the initialization stores.

**What survives the refutation.** The cost must live on the **read path**, where
it is per position rather than per table entry: the probe load `hashTable[hashPos]`
scatters over a working set proportional to the table, and a larger table retains
older candidates that pass the null and window checks and then force a far
`readWord(data + offset)` that misses. With E10 gone, E09 in read-side form is
the lead hypothesis — and its re-validation (see E09) shows the marginal-gain
inflection landing at the predicted knee on all three architectures.

**Also settled in passing:** the byte-identical output between cleared and
never-cleared builds means stale entries never survive validation on this data.
Clearing is semantically unnecessary; it was never the bottleneck either.

**A3 — the counter measurement (run 2026-08-20, `results_a3_pmc/` and
`results_a3b_pmc/`).** Two facts landed and one wall was hit.

- **The cost is kernel-internal, confirmed twice.** Compress-kernel time per call:
  baseline 23.1 ms at ht128 vs 104.8 ms at ht16384 (4.53x, matching the 4.50x
  throughput ratio); on the A2 no-clear builds, 95.65 ms vs 417.76 ms total
  (4.37x). Not launch overhead, not transfers, and once more not the clear loop.
- **One wave per chunk, confirmed by hardware count.** `SQ_WAVES` = 43,904 over
  4 dispatches = 10,974 chunks x 4, exactly the 719 MB / 64 KiB decomposition.
- **Platform wall: PMC value collection is non-functional on this node.** Every
  block counter — `GL2C_HIT`/`GL2C_MISS` (and `_sum` variants), `SQ_INSTS_VALU`,
  `SQ_WAVE_CYCLES`, `GRBM_GUI_ACTIVE`, `MemUnitBusy`, `VALUInsts` — returns zero
  under `rocprofv3 --pmc` on gfx1100 bare metal at ROCm 7.2.3, across two counter
  sets and both builds. Legacy `rocprof` aborts outright (SIGABRT). Only
  dispatch-derived values (`SQ_WAVES`, kernel time) come through.

**Consequence.** The discriminator between probe locality and failed-candidate
validation cannot run on this node. It moves to the CDNA replay — MI210/MI300X
expose `TCP_*` and demonstrably produced real PMC values in the May campaign
(ROCm 7.0.1, Singularity) — which was the planned next stage anyway, and this is
one more argument for the container re-measurement. Per the stop criteria, the
gfx1100 pass ends here with the verdicts above.

**A1 post-mortem.** The hypothesis that `isValidHash` re-validates everything was
wrong in one specific way. Its window check is total only for entries written
within the current chunk. In the first `OFFSET_SIZE` window, a stale entry at or
ahead of the current position underflows `convertIdx` — the `assert(offset <= pos)`
that would catch it is compiled out in Release — and the wrapped offset slips past
the `MAX_OFFSET` window check (pos 100, stale entry 200: `decomp_idx - offset`
comes out 65436, inside the window) and is dereferenced at a wild address. The
clear loop was not just a performance artifact; it was silently upholding an
invariant the validation depends on.

**A2.** One guard before `convertIdx`: in the first window, reject any entry at or
ahead of the current position. Legitimate entries there always sit strictly
behind it, so nothing valid is lost, and every throughput and ratio prediction
from A1 carries over unchanged.

**Why A1 needs no generation tag.** Reading the code showed the tag is
unnecessary: every reader already goes through `isValidHash`, which rejects a
stale entry via the `NULL_OFFSET` check, the `MAX_OFFSET` window check, and a
byte-level comparison against the actual data at the decoded offset. A leftover
entry can only propose a match that is then verified against the current chunk's
own bytes. The insert path's own comment says races are tolerated for exactly
this reason. So the simplest possible edit — delete the loop — is the experiment.

**Hypothesis.** `LZ4Kernels.hiph:941` opens `compressStream` with

```cpp
for (position_type i = threadIdx.x; i < hash_table_size;
     i += LZ4_COMP_THREADS_PER_CHUNK) {
  hashTable[i] = NULL_OFFSET;
}
SYNCWARP1();
```

One wave clears the whole table, in global memory
(`LZ4CompressionKernels.hip:103`), once per chunk. At the inherited default with a
64 KiB chunk that is 32 KB of global stores for every 64 KiB of input, before a
single byte is compressed. The cost is linear in table size and paid per chunk.

**Why it fits what E06, E08 and E09 measured.** It is monotone in table size with
no knee, which is what gfx1100 and gfx906 show. It is per chunk, so launch
geometry cannot reduce it, which is why E06 was neutral. It is store-bound VALU
work, which is what the E06 tag concluded when it called compress VALU-bound. And
it concentrates on the dense wavefield, where compression itself finds least to do
and a fixed cost dominates.

**The decisive test.** Remove the clear loop while keeping the table large, using
a per-chunk generation tag validated on read. If throughput then matches the
tuned small-table build, the clear loop was the cost and table size was a proxy,
which also means the fix costs no compression ratio at all.

**Revisit in the loop.** This is the next attempt. Measure ratio on every variant:
a generation tag too narrow will alias across chunks and lose matches silently,
which shows up as ratio and not as a crash.

---

## E11 — Move the hash table into LDS

| | |
|---|---|
| Verdict | **OPEN** |

**Hypothesis.** The thesis commits to this redesign. The table is in global memory
today; LDS is the software-managed scratchpad and is far cheaper both to clear and
to probe.

**Interaction to record.** E09's validation is the quantitative motivation this
redesign was missing: A4 showed a 2.1x swing from probe-line layout alone, at
byte-identical output, and the knee sits at L1/waves on all three architectures.
An LDS-resident table takes the probes out of the contended vector cache
entirely — the mechanism E09 measured is exactly the one LDS removes. At the
useful sizes from E08 (256–512 entries, 512 B–1 KB) the old occupancy objection
is gone.

**Feasibility.** At the inherited 16384 entries of `uint16_t` the table is 32 KB
per chunk, which is why occupancy was the standing objection. At the sizes E08
found useful, 256 to 512 entries is 512 B to 1 KB, and the objection dissolves.

**Revisit in the loop.** Requires the occupancy counter before and after, since
LDS allocation is itself an occupancy limiter.

---

## E14 — Small table as the production default (O1)

| Attempt | Commit | Verdict |
|---|---|---|
| O1 — wave-conditional default: 128 (wave32) / 64 (wave64) | `4a1dcfe` | **KEPT on 3/3** (2026-08-20): 29.2 / 64.4 / 8.2 GB/s vs predicted ~30.8 / ~63.9 / ~8.1; worst byte deviation +0.0485 %, inside the E08 band |

Lands E08/E09 as shipped behavior. Predictions: ~30.8 / ~63.9 / ~8.1 GB/s on
gfx1100 / gfx90a / gfx906 for dense 64K-chunk input with no flags; ratio within
+0.0075 % in exact bytes; compress temp shrinks 128-256x.

## E11 — LDS-resident table, attempt A8 (O2)

| Attempt | Commit | Verdict |
|---|---|---|
| A8 — table in LDS at O1 sizes | `4678ea4`, default-on in `f5f089a` | **KEPT on 3/3, both regimes** — the campaign's headline: gfx90a 80.5 GB/s (+25 %), gfx1100 31.9 (+9 %), gfx906 32.6 (**+300 %**), byte-identical output everywhere; also wins at small input (+16 %, +10 %, +47 %) |

Predictions: probes leave the per-CU vector cache (`TCP_TCC_READ_REQ` collapses
toward a tableless baseline on CDNA); throughput at least at parity with the
packed small table, gains concentrated where contention still costs at
saturation. 128-256 B of LDS per wave; the occupancy objection is dead.

## E15 — Runtime-derived table cap (O3)

| Attempt | Commit | Verdict |
|---|---|---|
| O3 — runtime cap = L1/(concurrent waves) | `981e19c`, reverted in `da94739` | **REVERTED as runtime code; KEPT as derivation.** As coded it finds the knee, not the optimum: 0.71x / 0.96x / 0.84x of O1 at saturation, and it loses at small input too, the only regime where it differs. The parity prediction failed — informative failure: the optimum sits two octaves below the knee. `optimum = (L1 / max_waves) / 4`, clamped to [64, MAX], reproduces O1's constants exactly on gfx1100 (512/4 = 128) and gfx90a (256/4 = 64), so the shipped defaults are now *derived*, not tuned |

Refined prediction (sharper than the commit text): **parity** with the fixed O1
default on dense data in both regimes, since a larger allowed table is flat, not
faster, at low concurrency on dense input; the potential *win* is ratio on
match-rich data at small batches, observable in the gate bytes. The value
claimed is the form: the cap computed from two device properties, no sweep.

## E16 — wave32 VGPR-capped occupancy (O4)

| Attempt | Commit | Verdict |
|---|---|---|
| O4a — min-waves 12 (VGPR ≤ 128) | `7495b65` | **REVERTED** (`7950a3d`): 0.94x on gfx1100 at saturation, 0.74x small |
| O4b — min-waves 16 (VGPR ≤ 96) | `7495b65` | **REVERTED**: 0.79x saturated, worse still small — monotone worsening with aggressiveness, the spill signature; two attempts sufficed |

Basis: kernel-symbol table shows 136 arch VGPRs on gfx1100 (residency ~10/16
waves per SIMD) against 64 on MI210 (already at its step) and 32 on MI50.
Prediction: more resident waves on gfx1100 with small added footprint at O1
sizes; spills are the counterweight, checked by the before/after VGPR counts.
Wave64 rows built from this tip serve as tip-replication.

## The round's progression ladder (inherited → O1 → O1+LDS, dense 64K chunk)

| GPU | inherited | O1 | O1+LDS | total |
|---|---|---|---|---|
| gfx1100 (RX 7900 XT) | 6.28 | 29.17 | **31.87** | **5.1x** |
| gfx90a (MI210) | 2.56 | 64.35 | **80.51** | **31.4x** |
| gfx906 (MI50) | 1.82 | 8.17 | **32.63** | **17.9x** |

Small-input regime (17 MB, undersubscribed): totals 1.3x / 2.7x / 2.7x, with LDS
still the top build on all three. Baselines replicate the known family values;
data in `campaign-o-2026-08-20/`, six builds per GPU, exact-bytes gate on all.

## E06 revisit — small-input regime (O5, measurement only)

Same builds, `--dup 16` (~17 MB, undersubscribed) on all three GPUs.
Predictions: the knee shift already seen on MI210 reappears (large tables
tolerable), O3 tracks it automatically, and O4's occupancy lift matters more
here than at saturation.
