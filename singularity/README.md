# Container tooling for the optimization loop

Four files, one job each. This replaces the old `defhip_benchmark.def` +
`scripts/build_singularity.sh` + `scripts/build_for_arch.sh` flow, which baked
per-architecture benchmark binaries from a GitHub branch into the image — a
design the loop cannot use, since attempts live as local commits and one image
must serve every architecture.

| File | Job |
|---|---|
| `toolchain.def` | the image recipe: ROCm 7.0.1 + hipcc + cmake + git + rocprofv3, **no project code**. One image serves gfx906/gfx90a/gfx942/gfx1100 alike, because code is built inside it at run time. |
| `check-node.sh` | probes a node: runtime (singularity/apptainer), amdgpu driver, gfx arch, the wave32 flag that arch needs, cores, and whether an image can be **built** here (root / sudo-g5k / sudo / fakeroot). Emits KEY=VALUE lines the other scripts consume. |
| `build-sif.sh` | builds the image from the def using whatever privilege mode `check-node.sh` found. Refuses to overwrite without `--force`, because campaign provenance points at the image it ran in. |
| `commit-sweep.sh` | the loop executor: takes the image, a **git bundle** (or repo) and a commit list; for each commit it checks out exactly that state, builds inside the image, runs the exact-bytes gate over the compressibility ladder, measures with per-repetition output, and stamps provenance. Ends with a summary: medians, step gains, total gain, and the byte matrix across commits. |

## The typical session

```bash
# once per node type (or copy an existing image -- it crosses G5K sites in seconds)
./check-node.sh
./build-sif.sh                      # needs a node where BUILD_MODE != none

# per campaign: ship code as a bundle, never by pushing
git -C <arcto> bundle create loop.bundle <campaign-branch>

# the sweep: one line per commit, optional extra cmake flags per line
cat > commits.txt <<EOF
0cd2506 -DARCTO_LZ4_MAX_HASH_TABLE_SIZE=128
ca26a31 -DARCTO_LZ4_MAX_HASH_TABLE_SIZE=128 -DARCTO_LZ4_TABLE_PAD_ENTRIES=32u
EOF
./commit-sweep.sh --sif images/arcto_toolchain_rocm701.sif \
    --source loop.bundle --commits commits.txt
```

Feeding the kept commits in merge order produces the **progression ladder** of
`../experiments/OPTIMIZATION-LOOP.md` §7; feeding one attempt commit replays
that attempt on the node's architecture (§6). The same ref may appear on
several lines with different flags — variants get tags `<sha>_v2`, `_v3`.

## Things the hard way taught

- **Bundles do not carry submodules.** The sweep runs
  `git submodule update --init third_party/zfp` after cloning; Grid'5000 nodes
  have outbound network. Offline, copy the submodule from an existing checkout
  and verify its pinned commit.
- **Grid'5000 std-env nodes run all of this without kadeploy** (driver +
  singularity present). The exception is PMC counter collection, which returns
  an empty counter list there — counter sessions still need kadeploy with sudo.
- **The gate runs before any throughput number is read.** A deterministic
  58-byte deviation on one ladder file is what exposed an instrumentation bug
  on wave64; treat any `!!` row in `summary.txt` as a stop sign, not a footnote.
- Results are harvested by rsync into
  `compression-experiments/experiments/<campaign>/`; nothing stays only on a
  node.
