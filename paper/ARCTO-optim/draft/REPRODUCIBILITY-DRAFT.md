# ARCTO SBAC-PAD'26 — Reproducibility Artifact (Draft Plan)

> **Status:** planning draft, not yet implemented. To be turned into a
> standalone artifact repo after the paper draft is complete. This file
> captures decisions made on 2026-05-23 so we can resume cleanly.

---

## 1. Goals

1. A reviewer (or a future reader) can take **one repo + one Zenodo DOI**
   and reproduce every CSV and every figure in the paper, from scratch,
   on a node with any of the four supported AMD GPUs.
2. Each measurement has a self-describing provenance record (SIF hash,
   arcto commit, hardware dump, date) so individual numbers in the paper
   can be traced back to the exact run that produced them.
3. The artifact is double-blind safe during review (no author-revealing
   paths, hostnames, or testbed names); the public release happens after
   the camera-ready.

## 2. Repo layout

```
arcto-sbac-pad26-artifact/
├── README.md                       quickstart: ≤5 commands to first CSV
├── REPRODUCIBILITY.md              this doc, promoted to user-facing
├── arcto/                          git submodule -> tag paper/sbac-pad-2026
├── containers/
│   ├── arcto.def                   parametrized by ARG GFX_ARCH
│   ├── build_sif.sh                builds one SIF for the local arch
│   └── pinned_versions.txt         exact ROCm, Ubuntu, hipcc versions
├── data/
│   ├── README.md                   Zenodo DOI, what's there, checksums
│   ├── manifest.json               sha256 + bytes for all 24 canonical files
│   ├── fetch_tti_zenodo.sh         pulls TTI_16gb.bin from Zenodo
│   ├── slice_tti_canonical.sh      derives 10mb..8gb from TTI_16gb.bin
│   └── regen_synthetic_seeded.sh   deterministic synthetics (seeded)
├── sweeps/
│   ├── run.sh                      generic: assumes SIF + data ready
│   ├── prepare-cluster.sh          generic cluster setup (SIF rebuild + slice)
│   └── prepare-g5k.sh              wraps oarsub + kadeploy + post_install
├── analysis/
│   ├── parse_csvs.py
│   ├── plot_*.py
│   └── make_tables.py
├── results_archive/                CSVs the paper was built from (read-only)
└── figures/                        final PDFs in the paper
```

## 3. Decision log (settled)

| # | Decision | Rationale |
|---|---|---|
| 1 | One SIF per `gfx<arch>`; baseline/pinned/adaptive picked by runtime flags `-P`, `-A` | Already how `sweep_canonical.sh` works. Avoids a baseline-vs-optim rebuild round-trip and a whole class of "wrong binary tested" errors. |
| 2 | `arcto` pinned by **tag** `paper/sbac-pad-2026` (immutable SHA), referenced as git submodule | Branch can drift; tag cannot. Branch may exist in parallel for post-paper maintenance. |
| 3 | Zenodo holds **only `TTI_16gb.bin`** (~16 GB). Smaller TTI sizes derived locally; synthetics fully regenerated from seeded scripts | Keeps the Zenodo deposit under the default 50 GB quota with margin. TTI is the only file that cannot be regenerated without the proprietary Fletcher source. |
| 4 | **SIF is rebuilt on the target node**, not downloaded pre-built | The reviewer's GPU arch is unknown; a pre-built SIF for our arch wouldn't run on theirs. Rebuild forces parity with the local toolchain. |
| 5 | `run.sh` is generic; environment setup is in `prepare-*.sh` | Reviewer chooses `prepare-cluster.sh` (standard cluster) or `prepare-g5k.sh` (kadeploy flow). Both end in the same `run.sh`. |
| 6 | Provenance JSON per result dir: SIF sha256, arcto SHA, hostname (scrubbed in review), rocm-smi, `hipDeviceProp_t`, ISO date | Already partially captured in `sweep_canonical.sh`; needs to be lifted into one JSON. |

## 4. Build pipeline (decision 4)

Container is parametrized at build time:

```
sudo apptainer build arcto_${ARCH}.sif containers/arcto.def \
     --build-arg GFX_ARCH=${ARCH}
```

`arcto.def`:
- Base: `ubuntu:22.04`
- ROCm: **pinned exact version** (currently 7.0.1; freeze before submission)
- Submodule build of `arcto/` at the tag SHA
- CMake invocation passes `-DAMDGPU_TARGETS=${GFX_ARCH}` and the
  wave32/wave64 flag derived from the arch
- Output: `/opt/arcto/{bin,lib,include}` inside the image

Build time: ~15-25 min on a modern node. Disk: ~3 GB final SIF.

Reviewer flow: clone artifact repo → `containers/build_sif.sh` (auto-detects
their `gfx<arch>` via `rocminfo`) → SIF ready in scratch.

## 5. Data pipeline (decision 3)

### TTI (16 GB only on Zenodo)

`data/fetch_tti_zenodo.sh`:
- `curl` the deposit URL
- Verify sha256 against `manifest.json`
- Place at `${SCRATCH}/TTI_16gb.bin`

`data/slice_tti_canonical.sh`:
- Takes `${SCRATCH}/TTI_16gb.bin` as input
- For each smaller size {10mb, 100mb, 1gb, 4gb, 8gb}, extracts a slice
  from a fixed offset (same offset used in the paper, documented in the
  script) using `tail -c +N | head -c ${bytes}`
- Verifies each output sha256 against `manifest.json`

### Synthetics (seeded)

Current `regen_synthetic_canonical.sh` is **non-deterministic** for
random/binary (`/dev/urandom`). New `regen_synthetic_seeded.sh`:

```bash
# random: deterministic stream from AES-CTR with fixed key/IV
openssl enc -aes-256-ctr -K "$(cat data/seed_random.hex)" \
            -iv 00000000000000000000000000000000 \
    -in /dev/zero | head -c ${bytes} > random_${size}.bin

# binary: same pattern logic, but the os.urandom slices are replaced
# by AES-CTR output with a separate seed
```

- Seeds (`seed_random.hex`, `seed_binary.hex`) are committed to the repo.
- Zeros are trivially deterministic (`head -c ${bytes} /dev/zero`).
- All 18 synthetic files verified against `manifest.json` after generation.

## 6. Execution flow A — standard cluster

**Stages — explicit, in order:**

| Stage | Owner | Command |
|---|---|---|
| 0 | reviewer | `git clone --recurse-submodules <artifact-repo>` |
| 1 | reviewer | `containers/build_sif.sh ${SCRATCH}` (~20 min) |
| 2 | reviewer | `data/fetch_tti_zenodo.sh ${SCRATCH}` (~16 GB download) |
| 3 | reviewer | `data/slice_tti_canonical.sh ${SCRATCH}` (~30 s) |
| 4 | reviewer | `data/regen_synthetic_seeded.sh ${SCRATCH}` (~15 min) |
| 5 | reviewer | `sweeps/run.sh ${SCRATCH}` (full sweep + analysis + plots) |

`run.sh` does, end-to-end:
- Detect arch via `rocminfo` → set `MAX_GB_FOR_GPU` cap
- Loop over the (algo × dtype × size × mode) matrix
- Emit one CSV per cell into a timestamped result dir
- Emit `_provenance.json` for the campaign
- Run `analysis/parse_csvs.py` and `analysis/plot_*.py` to materialize the
  paper figures from the freshly produced CSVs
- Print a final pointer to the result dir

End state: reviewer has a result dir with CSVs + JSON + figures that match
the paper's qualitative claims (per-cell timings will differ from the
published numbers because of host load / GPU sharing — this is expected).

## 7. Execution flow B — Grid'5000-style kadeploy

**Stages — explicit, in order:**

| Stage | Owner | Command |
|---|---|---|
| 0 | reviewer | Reserve node with `oarsub -t deploy -l host=1,walltime=4` |
| 1 | reviewer | `kadeploy3 -e ubuntu2204-x64-min -f $OAR_NODEFILE` |
| 2 | reviewer | `sweeps/prepare-g5k.sh ${NODE}` (calls a sed-or-arg variant of `post_install`) |
| 3 | (auto) | `post_install` installs apptainer, mounts local scratch, builds SIF, generates synthetics, fetches TTI from Zenodo, slices |
| 4 | reviewer | `ssh ${NODE} 'cd <artifact> && sweeps/run.sh /tmp/arcto_canonical'` |

`prepare-g5k.sh` must:
- Accept node name as positional arg (the current
  `post_install_with_canonical.sh` **hardcodes** `vianden-1` — needs to
  be parametrized).
- Drive the inner SSH to the deployed node.
- Be aware of the two-hop pattern (`ssh luxembourg.g5k` then `ssh ${NODE}`
  inside) — in the artifact-public version, the site name will be a
  parameter so the script does not embed any specific testbed.

## 8. Provenance schema

`_provenance.json` per result dir:

```json
{
  "campaign_id": "uuid",
  "timestamp_iso": "2026-05-23T14:32:11+02:00",
  "hostname_scrubbed": "node-anon",
  "arch": "gfx942",
  "gpu_model_generic": "AMD MI300X",
  "vram_gib": 192,
  "rocm_version": "7.0.1",
  "sif_sha256": "...",
  "arcto_commit": "abc123",
  "artifact_repo_commit": "def456",
  "hip_device_props": { "name": "...", "totalGlobalMem": ... },
  "rocm_smi_dump": "...",
  "config": {
    "max_gb_for_gpu": 16,
    "iters": 5,
    "modes": ["baseline", "pinned", "adaptive"]
  }
}
```

For the public release, `hostname` is replaced by a stable but
non-identifying tag (`node-mi300x-a`).

## 9. Anonymization for review

- **Repo stays private.** No public link in the submission PDF.
- If reviewers explicitly request the artifact, provide it through an
  anonymous mirror (e.g. `anonymous.4open.science`) that strips Git
  history and replaces author-identifying strings.
- **Strings to scrub** before any review-time share:
  - All paths under `/home/<user>/`
  - Hostnames (`vianden-*`, `lunaris*`, `luxembourg.g5k`, ...)
  - The testbed names themselves (`Grid'5000`, `PCAD`)
  - Funding/acknowledgment text
- **Paper text** (separate concern but related): describe the hardware
  generically — "a node with an AMD MI300X (192 GB HBM3, gfx942)" —
  rather than naming the specific testbed.

## 10. Open items for the build session

- [ ] Decide where the artifact repo lives long-term (own GitHub org repo
      vs. subpath of `compression-experiments`).
- [ ] Confirm whether `anonymous.4open.science` is acceptable to
      SBAC-PAD's chairs as the review-time mirror.
- [ ] Pin the exact ROCm version that goes into the SIF and freeze it in
      `containers/pinned_versions.txt`.
- [ ] Move `post_install_with_canonical.sh` from local-only to a
      parametrized `prepare-g5k.sh` (node arg + site arg).
- [ ] Generate `data/seed_random.hex` and `data/seed_binary.hex` and
      regenerate the canonical synthetics with them, then publish their
      sha256 in `manifest.json`. (Decision: do this **before** running
      the final paper sweeps, so the numbers in the paper match the
      seeded files reviewers will get.)
- [ ] Verify Zenodo's actual quota for the deposit (default 50 GB; we
      need ~16 GB — should fit without a quota request).

## 11. Schedule

Build the artifact repo **after** the paper draft is internally complete
(all sections written, results stable). Earliest sensible window: once
Section 6 (Evaluation) is locked. Aim to have the artifact ready ~1 week
before the camera-ready deadline so we can do a clean-room reproduction
test on a fresh node before submission.
