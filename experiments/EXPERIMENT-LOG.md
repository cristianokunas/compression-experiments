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

| | |
|---|---|
| Verdict | **SUPERSEDED** (refuted 2026-08-20) |

**Hypothesis.** Each wave carries its own table, so the governing quantity is the
aggregate footprint of concurrently resident waves against the per-CU vector
cache, predicting an optimum at `table_bytes ≈ L1_bytes / waves_per_CU`.

**Measurement.** Rescued cross-architecture data:

| GPU | predicted | measured | shape |
|---|---|---|---|
| gfx90a | 256 entries | **256** | sharp 4× step at 512 to 256 |
| gfx1100 | 512 entries | **128** | monotone to the smallest size tested |
| gfx906 | ~205 entries | **64** | monotone to the smallest size tested |

**Post-mortem.** Two of three architectures never turn over. A residency argument
predicts a knee, and there is none. The MI210 hit is the one point that fits, and
its 4× step is too sharp for a smooth residency story anyway.

**Revisit in the loop.** Do not discard entirely. MI210's step remains unexplained
by E10 as well, and may be a residency effect operating on top of it. It is the
sharpest open question in the campaign.

---

## E10 — Per-chunk hash-table clear loop as the real cost

| Attempt | Commit | Verdict |
|---|---|---|
| A1 — clear loop removed outright | `b9671c5` | **FAILED THE GATE** on gfx1100: illegal memory access, refined into A2 |
| A2 — A1 plus a stale-entry guard in `isValidHash` | `b48397c` | **OPEN — measuring on gfx1100** |

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
