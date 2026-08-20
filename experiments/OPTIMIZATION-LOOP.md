# The optimization loop — specification

How every attempt at optimizing the ARCTO compression kernels is carried out,
measured, recorded and made replayable on a second architecture.

This is the operational form of the thesis claim in RQ2: that the bottlenecks are
removed by measuring the cause with hardware counters and applying a targeted
change against it, rather than by per-case tuning that does not generalize. The
loop is what makes that claim auditable instead of asserted.

Attempts and verdicts live in [`EXPERIMENT-LOG.md`](EXPERIMENT-LOG.md).

---

## 1. The loop

Each pass is four steps and produces exactly one commit.

**Profile the target.** Start from a counter reading, not from an idea. The
reading names the resource under pressure and the kernel that is under it. If no
counter distinguishes the candidate explanations, the attempt is not ready: go
find the counter first, or state in the log that the attempt is throughput-only
and therefore cannot separate causes.

**Form a hypothesis.** Written before the edit, in the log entry, as a claim that
can fail. It must say which counter should move, in which direction, and by
roughly how much. A hypothesis that predicts only "it should be faster" is not
falsifiable and does not earn a pass.

**Edit the code.** One mechanism per attempt. Two changes in one commit cannot be
attributed, which is the error that produced `c*`.

**Run correctness, then performance.** In that order. A faster wrong kernel is not
a result. The correctness gate is in §4; it is absolute and no performance number
is read until it passes.

**Keep what works.** Merge the commit or revert it, and record the verdict either
way. Reverted attempts stay in the log and stay in the branch history, because the
value of a null result is that nobody repeats it.

---

## 2. Where things live

| | |
|---|---|
| `arcto` | the library, and nothing else. Kernel changes go here. No results, no campaign scripts, no campaign-named refs. |
| `compression-experiments/experiments/` | this specification, the log, the runners, and the raw measurements |

An attempt is a commit in `arcto`. The log entry in `compression-experiments`
names that commit. That pair is the whole traceability chain.

---

## 3. Branch and commit protocol

**One isolated branch per campaign**, off `main`, never off `feature/kernel-opt`:

```bash
git -C <arcto> checkout main
git -C <arcto> checkout -b opt/<campaign-name>
```

**One attempt per commit.** Never squash two mechanisms together, and never amend
an attempt that has already been measured. The commit is the unit that gets
replayed on another GPU, so it must build and run on its own.

The commit is made **before** measuring and carries only the hypothesis; the
measurement and verdict go in the log, never as an amend:

```
opt(<area>): <the one mechanism changed>

Attempt <ID> in experiments/EXPERIMENT-LOG.md.
Hypothesis: <what should move, which counter, which direction>.
```

A reverted attempt keeps its commit, followed by a revert commit. Both stay.
Deleting the attempt destroys the only reason the next person will not retry it.

After measuring, write the log entry with the **short commit hash and the
verdict** before starting the next attempt. The log is written as the loop runs,
not reconstructed afterwards.

---

## 4. The correctness gate

No performance number is read until this passes, on the same build.

| Codec | Gate |
|---|---|
| LZ4, Snappy, Cascaded | round-trip **bit-exact**. Any difference fails. |
| ZFP lossy | global reconstruction error within the accuracy parameter. Bit equality is not expected. |
| Any table-structure change | **compression ratio in exact bytes** against the pre-change build, across the compressibility ladder |

That last row is not optional for this campaign. A generation tag that is too
narrow, or a hash that collides more after a resize, loses matches **silently**:
the output stays valid, the round-trip still passes, and only the byte count
moves. Compare exact `Compressed size in bytes`, not a ratio rounded to two
decimals.

Ladder: `synth_zeros`, `synth_binary`, `synth_random`, `tti_rsf_t000` (sparse),
`tti_rsf_t050` (dense). The 1 MB fixtures in `arcto/tests/data/` are exactly this
set. They are not used by `ctest`; this is what they are for.

`ctest` passing 18 of 19 with only `BitPackGPU_test` failing is the expected
state, not a regression.

---

## 5. Measurement protocol

**Guard first.** Abort the campaign unless a minimal `hipMalloc` plus kernel
program passes. A wedged driver on lunaris once made 17 of 19 ctest cases fail and
looked exactly like a branch regression. `/tmp/hipmin` is that program; the
runners already call it.

**Pin the device.** lunaris has two GPUs. Check `rocm-smi --showuse` and export
`HIP_VISIBLE_DEVICES` to an idle one. A neighbour's job is indistinguishable from
a regression.

**Per-repetition values.** Set `ARCTO_PER_REP_CSV` and `ARCTO_PER_REP_TAG`
(branch `feat/per-rep-output`). The aggregated mean plus stddev the benchmark
prints does not satisfy the thesis protocol. Report median and interquartile
range; flag outliers and never remove them.

**Derive the tag from the build, never type it.** Each build directory carries an
`HT_SIZE` stamp; the runner reads it. On the first trial of the per-repetition
plumbing two configurations were labelled `ht16384` and `ht512` and both reported
about 6.9 GB/s, because both had in fact invoked the same default binary. A label
that is not derived from the build will eventually lie.

**Record provenance per run**: git HEAD, the full dirty-state listing, ROCm
version, device, input file and its size, repetition count. The existing runners
write `provenance.txt`; keep that.

**Bare metal for now, by decision.** These runs use lunaris bare metal at ROCm
7.2.3 in order to see the behaviour first. The methodology chapter declares ROCm
7.0.1 inside the Singularity image, so **anything adopted is re-measured in the
container before it is written up**. Do not mix toolchains within one comparison.

---

## 6. Cross-architecture replay

This is why one attempt equals one commit. To ask whether an attempt that worked
on gfx1100 also works on gfx942 or gfx90a, replay the same commits on the other
part rather than re-implementing anything:

```bash
git -C <arcto> checkout <attempt-commit>
# build and measure with the same runner, same input, same repetition count
```

Rules that keep the comparison honest:

- **Same commit, not the same idea.** Build from the exact hash in the log.
- **Both wave widths before generalizing.** gfx1100 is wave32; gfx942 and gfx90a
  are wave64. E07 in the log is the standing reminder: wave64 rejected every
  vectorized-copy and warp-LSIC variant that wave32 accepted, some by as much as
  −43 %.
- **A per-architecture verdict, not a global one.** The log records the verdict
  per architecture. "Kept on gfx1100, reverted on gfx942" is a normal and useful
  outcome, and it is the shape of most results in this project so far.
- **Counter availability differs.** gfx1100 exposes no `GL1C_*` or `TCP_*` counters
  in this ROCm build, so the per-CU vector cache cannot be measured directly there
  and only traffic reaching L2 (`GL2C_HIT`, `GL2C_MISS`) is observable. CDNA parts
  do expose `TCP_*`. Where a hypothesis is about the per-CU cache, MI210 is the
  part that can test it directly.

Available counters on gfx1100 that the loop uses: `OccupancyPercent`,
`MeanOccupancyPerCU`, `SQ_WAVES`, `GRBM_GUI_ACTIVE`, `MemUnitBusy`, `VALUInsts`,
`L2CacheHit`, `GL2C_HIT`, `GL2C_MISS`.

---

## 7. Stop criteria

Stop the campaign when any of these is true, and say which in the log:

- The counter the hypothesis named did not move, and no revised hypothesis
  explains why. Chasing wall-clock past that point is tuning, not method.
- Two consecutive attempts return null on every architecture.
- The remaining candidates all require a redesign larger than the campaign, in
  which case write them up as next steps rather than starting them.

---

## 8. What the loop must not do

- **Do not let an agent commit.** The developer runs `git commit`, keeping
  sign-off and control. This is the practice the ROCm case study calls out
  explicitly, and it is the one that keeps authorship unambiguous.
- **Do not present the tooling as the contribution.** If an assistant or an agent
  such as GEAK compresses the experimental loop, that is an accelerator. The
  contribution is the method and the mechanism found, and claiming otherwise
  hollows out RQ2.
- **Do not quote a superseded result.** `c*` and the ZFP reversible measurements
  were removed for this reason; see `HISTORY.md` at the repository root.
- **Do not report a gain without its ratio check.** On this data the dense
  wavefield compresses to 0.9961x, meaning LZ4 slightly expands it. A "gain" that
  came from emitting less output is not a gain.
