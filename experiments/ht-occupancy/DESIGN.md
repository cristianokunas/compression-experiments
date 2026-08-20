# Experiment: what actually governs LZ4 compression throughput

Replaces the `c*` chunk-sizing result. Microbenchmark only — no application,
no Fletcher, no mamute. ARCTO's own benchmarks plus `rocprofv3` counters.

## Why this experiment exists

The `c*` result reported that shrinking the chunk from the inherited 64 KiB to
8 KiB buys up to 1.6x for LZ4, and attributed it to a per-chunk cost floor
(`c_floor`: launch and metadata overhead, LZ4 dictionary reset, ratio loss on a
small window, uncoalesced tail).

Two things are wrong with that.

**The knob moves two variables at once.** `LZ4Types.h` sets

```
HT = min(roundUpPow2(chunk), MAX_HASH_TABLE_SIZE)
```

so shrinking the chunk simultaneously (a) produces more chunks, hence more
waves, hence higher occupancy, and (b) shrinks the per-wave hash table, hence
its cache footprint. The `c*` sweep walks a diagonal across a two-dimensional
surface and reports the diagonal as if it were the axis.

**The attributed mechanism is not what the counters show.** On the MI300X,
`profiling-lz4-rootcause_MI300X_20260518` measured `MemUnitStalled` at 2.29 % and
`VALUUtilization` at 94.54 % for the LZ4 compress kernel. There is no signature
of launch or metadata overhead dominating. What the counters do show is
occupancy at 9.35 % against 9728 wave slots — the kernel is starved of waves,
not drowning in per-chunk overhead.

And decoupling the two variables shows the table is what mattered. Holding the
chunk at 64 KiB and shrinking only `MAX_HASH_TABLE_SIZE`:

| GPU | baseline (32 KB table) | tuned table | gain | what `c*` found instead |
|---|---|---|---|---|
| RX 7900 XT (gfx1100) | 6.88 GB/s | 12.74 GB/s | +85 % | 1.59x |
| MI210 (gfx90a) | 2.40 GB/s | 44.28 GB/s | **+1745 %** | 1.33x |

On the MI210 the chunk sweep found 1.33x where 18.5x was available, because it
was tuning the wrong variable.

## Hypothesis

> LZ4 compression throughput on this data is limited by the **per-chunk cost of
> clearing the hash table**, which is linear in the table size and paid before
> any compression happens.
>
> `LZ4Kernels.hiph:941` opens `compressStream` with
>
> ```cpp
> for (position_type i = threadIdx.x; i < hash_table_size;
>      i += LZ4_COMP_THREADS_PER_CHUNK) {
>   hashTable[i] = NULL_OFFSET;
> }
> SYNCWARP1();
> ```
>
> One wave clears the whole table, in global memory
> (`LZ4CompressionKernels.hip:103`, `temp_space + bidx * hash_table_size`), once
> per chunk. At the inherited default with a 64 KiB chunk that is **32 KB of
> global stores for every 64 KiB of input** — a 50 % write amplification before a
> single byte is compressed.

### Why this and not cache residency

An earlier version of this document proposed that the governing quantity was the
aggregate table footprint of concurrently resident waves against the per-CU
vector cache, predicting `table_bytes* ~ L1_bytes / waves_per_CU`. The rescued
cross-architecture data refutes it:

| GPU | predicted optimum | measured optimum | curve |
|---|---|---|---|
| gfx90a (MI210), L1 16 KB, 32 w/CU | 256 entries | **256** | sharp 4x step 512 -> 256 |
| gfx1100, L1 32 KB, 32 w/CU | 512 entries | **128** | monotone to the smallest size tested |
| gfx906 (MI50), L1 16 KB, 40 w/CU | ~205 entries | **64** | monotone to the smallest size tested |

Two of three architectures never turn over: throughput keeps rising as the table
shrinks, with no knee. A residency argument predicts a knee. A cost term linear
in table size predicts exactly this monotone shape.

The initialization hypothesis also accounts for two results the residency one
could not:

- **`archive/wave64-n4-neutral`** — packing four chunks per block lifted the wave
  count and measured *neutral* on MI300X, with rocprofv3 confirming the geometry
  change and an identical ~21.8 ms kernel time. Initialization work is per chunk,
  so geometry cannot reduce it. That tag concluded compress is VALU-bound per CU;
  the clear loop is what it is bound on.
- **The dense-wavefield concentration** — where compression itself finds little to
  do, a fixed per-chunk cost dominates the total.

MI210's sharp 512 -> 256 step remains unexplained by either account and is the one
place a residency effect may still be operating on top. It is the sharpest open
question, not a settled one.

### The prediction that matters

If initialization is the cost, then **removing the clear loop should deliver the
gain without shrinking the table at all** — e.g. by tagging entries with a
per-chunk generation counter and validating on read, so no pre-pass is needed.
That is a code fix rather than a tuning parameter, it is architecture-independent,
and it is falsifiable in one build.

## Protocol

### Phase 0 — stack guard

Run the minimal `hipMalloc` + kernel program and abort on failure. A wedged
driver on lunaris once made 17/19 ctest cases fail and looked exactly like a
branch regression; a whole campaign was attributed to a code change that had
not happened. Never skip this.

Record, per node: `rocminfo` CU count, wavefront size, max waves/CU, L1/L2
sizes, ROCm version, GPU clock state, and the ARCTO commit.

### Phase 1 — decouple the surface

Vary independently, at fixed input (large TTI, dense — the regime where the
effect lives):

- `MAX_HASH_TABLE_SIZE` in {128, 256, 512, 1024, 2048, 4096, 8192, 16384} entries
- chunk size in {8, 16, 32, 64} KiB

32 build/measure points. **Prediction:** iso-throughput contours run parallel to
the chunk axis and cut across the table axis. The `c*` claim predicts the
opposite.

### Phase 2 — counters at each point

`rocprofv3 --pmc` for the hot compress kernel:

`OccupancyPercent`, `SQ_WAVES`, `GRBM_GUI_ACTIVE`, `VALUUtilization`,
`MemUnitStalled`, and vector-cache miss traffic (`TCP_TCC_READ_REQ_sum`,
i.e. L1 misses going to L2).

Derive `waves_per_CU` from `OccupancyPercent` and the device's max, then compute
the aggregate footprint. **Prediction:** the throughput knee and the rise in L1
miss traffic occur at the same footprint, near `L1_bytes`.

The L1 miss counter is the load-bearing measurement. Throughput alone cannot
distinguish "the table fits" from any other explanation; miss traffic can.

### Phase 3 — the decisive test (remove the cost instead of shrinking it)

Shrinking the table conflates two things: less initialization work, and a smaller
resident footprint. Removing the initialization removes one of them and leaves
the other, which is what separates the accounts.

Replace the clear loop with a **generation tag**: widen each entry, or keep a
parallel byte, holding the chunk index that wrote it; on read, an entry whose tag
does not match the current chunk is treated as empty. No pre-pass, table size
unchanged.

| build | table | clear loop | prediction if initialization is the cost |
|---|---|---|---|
| A | 16384 (inherited) | yes | the slow baseline |
| B | 16384 | **no** (generation tag) | **matches or beats the tuned small-table build** |
| C | 256 | yes | the tuned build, for reference |
| D | 256 | no | best of all, and close to C |

If B lands near C, the gain was the clear loop and table size is a red herring —
which also means the fix costs no compression ratio at all, because the table
stays large. If B stays near A, initialization is not the cost and the residency
account comes back into play.

Measure ratio on every build: a generation tag that is too narrow will alias
across chunks and silently lose matches, which shows up as ratio, not as a crash.

### Phase 4 — cross-architecture falsification

Repeat phases 1-3 on gfx90a (MI210, CDNA2, wave64, L1 16 KB). The model predicts
the knee moves with `L1_bytes / waves_per_CU`, so a device with half the L1
should show its knee at half the footprint. Two chips with different caches and
different wavefront widths is a real test, not a confirmation pass.

Name the cache level precisely per architecture rather than calling both "L1":
`rocminfo` reports 32 KB for gfx1100, which is the per-CU vector cache (L0 in
RDNA nomenclature, with a separate per-shader-array L1 it does not report),
against 16 KB per CU on CDNA2. Phase 2's miss counters, not the naming, decide
which level actually holds the table.

### Phase 5 — ratio must not be paid for

Verify in **exact bytes**, not ratios rounded to two decimals, across the full
compressibility ladder (`synth_zeros`, `synth_binary`, `synth_random`,
`tti_rsf_t000` sparse, `tti_rsf_t050` dense) that a smaller table costs no
compression ratio. Earlier measurement put the worst case anywhere at +0.056 %,
and showed the large table was buying long-range matches this data does not
contain. Re-verify rather than cite.

## Measurement protocol

Per-repetition values are preserved, per the thesis end-to-end protocol, using
`ARCTO_PER_REP_CSV` / `ARCTO_PER_REP_TAG` (branch `feat/per-rep-output`). Report
median and interquartile range; flag outliers, never remove them. Pin the GPU
clock before write-sensitive runs. Pin `HIP_VISIBLE_DEVICES` to an idle device —
lunaris has two.

**The tag must be derived from the build, never typed.** `ARCTO_PER_REP_TAG` is
a free-form string, so it will happily label a run with a table size the binary
was not compiled for. This failure was produced on the first trial run of the
plumbing: two configurations tagged `ht16384` and `ht512` both reported
~6.9 GB/s, because both invoked the same default binary. The runner must read
the value back out of the build (from the configure log or a stamp file the
build writes) and construct the tag from that, so a mislabelled point is
impossible rather than merely unlikely.

**Open protocol conflict:** the methodology chapter states every platform used
ROCm 7.0.1 inside the Singularity image. lunaris bare-metal is now ROCm 7.2.3.
Either run this campaign inside the image or amend the chapter — do not silently
mix toolchains across the campaign.

## What lands in the thesis if it holds

A profile-driven optimization in the exact form the methodology chapter defines:
a counter quantifies the bottleneck (occupancy and L1 miss traffic), one change
is aimed at it (table sized to the cache budget), and the same counter confirms
the change acted where intended. It carries to a new architecture by reading two
device properties instead of by re-running a search, which is what the chapter
claims a profile-driven result should do and what `c*` could not.

## What this does not settle

Whether raising occupancy is worth it once the table is sized correctly. The
MI300X profiling proposes packing N chunks per block to lift occupancy from
16.5 % to ~66 %; under this model that also multiplies the table footprint by N.
The two optimizations have to be co-tuned, and that is the natural next
experiment, not part of this one.
