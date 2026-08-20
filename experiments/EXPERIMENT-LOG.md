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
| A4 — probe-footprint discriminator | `34e623e` | **OPEN — measuring on gfx1100** |

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

**Attempt A4** (`34e623e`) probes the sub-knee residual with no counters needed:
table held at 16384 entries, hash masked to 128 logical slots in two geometries —
`contig128` (stride 1, 4 touched cache lines per wave) and `spread128` (stride
128, 128 touched lines across the full 32 KB). The logical slot function is
identical in both, so collisions and output bytes must match real ht128 exactly
(that identity is the gate). Line-residency predicts spread128 falls to roughly
the ht4096 level (~10 GB/s, same 8 KB line footprint); the collision-age account
predicts spread128 stays at the ht128 level (~30 GB/s). The separation is 3x, far
above noise.

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

**Interaction to record.** If E10 holds, moving to LDS also removes most of the
clear cost, because clearing in LDS is orders of magnitude cheaper than in global
memory. The promised redesign and E10 converge on the same fix for a reason the
proposal did not know. Measure them separately before combining, or the credit
cannot be assigned.

**Feasibility.** At the inherited 16384 entries of `uint16_t` the table is 32 KB
per chunk, which is why occupancy was the standing objection. At the sizes E08
found useful, 256 to 512 entries is 512 B to 1 KB, and the objection dissolves.

**Revisit in the loop.** Requires the occupancy counter before and after, since
LDS allocation is itself an occupancy limiter.
