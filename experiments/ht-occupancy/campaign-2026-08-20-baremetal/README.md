# Bare-metal campaign — lunaris, 2026-08-20 (in progress)

Extends the 2026-08-19 campaign: the same decoupled table sweep, but with more
table sizes, per-repetition output, and hardware counters.

Run **bare metal on purpose**, to see the behaviour first. If the result is
adopted, it gets re-measured inside the self-contained container image, which is
what the methodology chapter declares.

## Tool state

The campaign needs two ARCTO changes that live on separate branches in the tool
repository, because neither belongs to the campaign:

| Branch | Commit | Why the campaign needs it |
|---|---|---|
| `feat/ht-size-override` | `f3e70b7` | makes `MAX_HASH_TABLE_SIZE` settable at build time, which is what decouples table size from chunk size |
| `feat/per-rep-output` | `03381b5` | writes the raw per-repetition values the thesis protocol requires |

Combine them with a plain merge; it is conflict-free:

```bash
git -C <arcto> checkout -b build-base feat/ht-size-override
git -C <arcto> merge feat/per-rep-output
```

No campaign branch is kept in the tool repository. `arcto` holds the library and
nothing else — no results, no campaign scripts, no campaign-named refs.

## Environment

| | |
|---|---|
| Node | lunaris, RX 7900 XT (gfx1100), **HIP_VISIBLE_DEVICES pinned to an idle device** — the node has two |
| ROCm | 7.2.3, bare metal |
| Input | `compression-experiments/testdata/large_TTI_1024.bin`, 719 MB |

**Counter limitation found on this platform:** gfx1100 exposes no `GL1C_*` or
`TCP_*` counters in this ROCm build, so the per-CU vector cache cannot be
measured directly. Only `GL2C_*` is available, which gives the traffic that
*reaches* L2 — i.e. the L0 miss count — as an indirect signal. CDNA parts do
expose `TCP_*`, so the direct measurement is a reason to run this on MI210 too.

## Scripts

`scripts/build_grid.sh` builds one library per table size (128 … 16384) and
stamps each build directory with an `HT_SIZE` file. The runner must read its
configuration label from that stamp rather than from a typed string: on the first
trial run of the per-repetition plumbing, two configurations were labelled
`ht16384` and `ht512` and both reported ~6.9 GB/s, because both had in fact
invoked the same default binary. A label that is not derived from the build will
eventually lie.
