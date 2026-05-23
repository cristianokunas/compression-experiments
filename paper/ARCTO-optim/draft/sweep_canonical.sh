#!/bin/bash
# Canonical sweep driver for the SBAC-PAD'26 paper.
#
# Runs the full (algo x data_type x size x mode) matrix on a single
# AMD GPU using the local scratch for the canonical datasets to keep
# the home quota free (datasets are regenerated per job, not stored).
#
# Algorithms : lz4, snappy, cascaded
# Data types : tti, zeros, random, binary
# Sizes      : 10mb, 100mb, 1gb, 4gb, 8gb, 16gb  (filtered by VRAM cap)
# Modes      : baseline, pinned, adaptive
#
# Environment variables (override on the command line):
#   ARCTO_BIN_DIR  path to benchmark_lz4_chunked etc.
#                  default: /home/ckunas/arcto/build_canon/bin
#   ARCTO_LIB_DIR  path to libarcto.so (LD_LIBRARY_PATH)
#                  default: /home/ckunas/arcto/build_canon/lib
#   SIF            singularity image
#                  default: /home/ckunas/compression-experiments/arcto_gfx942.sif
#   TTI_SRC        path to TTI.rsf@ binary, used to extract canonical TTI
#                  sizes from the middle (offset = 100 timesteps).
#                  default: /home/ckunas/testdata/source/TTI.rsf@
#   DATA_DIR       scratch directory for the canonical datasets.
#                  Use a LOCAL FAST disk (NOT NFS home). Will be
#                  populated by the regen scripts on first run.
#                  default: $TMPDIR/arcto_canonical
#   RESULTS_DIR    output directory for the CSVs and FINDINGS.
#                  default: /home/ckunas/compression-experiments/paper/ARCTO-optim/results/<HOST>_FULL_<ts>
#   MAX_GB_FOR_GPU integer cap; sizes > this many GB are skipped.
#                  Set per GPU's VRAM. Defaults to detect by gcnArchName:
#                    gfx906 -> 4    (MI50, 32 GB VRAM)
#                    gfx90a -> 8    (MI210, 64 GB VRAM)
#                    gfx942 -> 16   (MI300X, 192 GB VRAM)
#                    gfx1100 -> 4   (RX 7900 XT, 20 GB VRAM)
#   ITERS          timed iterations (default 3 for 8/16 GB, 5 for smaller)
#   GEN_ONLY       if "1", just regenerate datasets and exit (no sweep)
#   SKIP_GEN       if "1", skip dataset regeneration (assume DATA_DIR populated)
#
# Usage examples:
#   # On vianden-1 (MI300X, with TTI.rsf@ in luxembourg home):
#   sweep_canonical.sh
#
#   # Smaller GPU, smaller VRAM cap:
#   MAX_GB_FOR_GPU=4 sweep_canonical.sh   # MI50 / RX 7900 XT
#
#   # Just generate datasets in /scratch and stop (e.g., warm a job):
#   DATA_DIR=/scratch/canonical GEN_ONLY=1 sweep_canonical.sh
#
# Notes:
#   * The script discovers the GPU via rocm-smi and the gcnArchName via
#     hipGetDeviceProperties (through the benchmark binary).
#   * datasets are NOT cleaned at the end -- they live in DATA_DIR for
#     reuse across multiple sweep invocations within the same job.

set -e

ARCTO_BIN_DIR="${ARCTO_BIN_DIR:-/home/ckunas/arcto/build_canon/bin}"
ARCTO_LIB_DIR="${ARCTO_LIB_DIR:-/home/ckunas/arcto/build_canon/lib}"
SIF="${SIF:-/home/ckunas/compression-experiments/arcto_gfx942.sif}"
TTI_SRC="${TTI_SRC:-/home/ckunas/testdata/source/TTI.rsf@}"
DATA_DIR="${DATA_DIR:-${TMPDIR:-/tmp}/arcto_canonical}"

HOST=$(hostname -s)
TS=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="${RESULTS_DIR:-/home/ckunas/compression-experiments/paper/ARCTO-optim/results/${HOST}_FULL_${TS}}"

# Get the script directory so we can invoke the regen scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------------------------------------------
# Stage 1: regenerate canonical datasets in local scratch
# -------------------------------------------------------------------
if [ "${SKIP_GEN:-0}" != "1" ]; then
  mkdir -p "$DATA_DIR"
  echo "=== Stage 1: regenerate canonical datasets in $DATA_DIR ==="
  echo "(this is scratch; will be reused but not committed anywhere)"
  echo ""
  # TTI requires the source binary
  if [ -f "$TTI_SRC" ]; then
    SRC="$TTI_SRC" OUT_DIR="$DATA_DIR" "$SCRIPT_DIR/regen_tti_canonical.sh" || true
  else
    echo "WARNING: $TTI_SRC missing -- TTI suite will be skipped from sweep"
  fi
  # Synthetic always available
  OUT_DIR="$DATA_DIR" "$SCRIPT_DIR/regen_synthetic_canonical.sh"
fi

if [ "${GEN_ONLY:-0}" = "1" ]; then
  echo "GEN_ONLY=1 -- datasets generated, exiting before sweep"
  ls -la "$DATA_DIR"
  exit 0
fi

# -------------------------------------------------------------------
# Stage 2: determine the per-GPU size cap
# -------------------------------------------------------------------
if [ -z "${MAX_GB_FOR_GPU:-}" ]; then
  # Detect arch via rocm-smi (works under singularity --rocm)
  ARCH=$(singularity exec --rocm "$SIF" rocminfo 2>/dev/null \
         | grep -m1 "gfx[0-9]" | awk '{print $2}' || echo unknown)
  case "$ARCH" in
    gfx906)  MAX_GB_FOR_GPU=4  ;;  # MI50 32 GB
    gfx90a)  MAX_GB_FOR_GPU=8  ;;  # MI210 64 GB (or 16 if VRAM allows)
    gfx942)  MAX_GB_FOR_GPU=16 ;;  # MI300X 192 GB
    gfx1100) MAX_GB_FOR_GPU=4  ;;  # RX 7900 XT 20 GB
    *)       MAX_GB_FOR_GPU=4  ;;
  esac
  echo "detected arch=$ARCH, using MAX_GB_FOR_GPU=$MAX_GB_FOR_GPU"
fi

# Convert size_name to GB integer for comparison
size_to_gb() {
  case "$1" in
    10mb)  echo 0 ;;
    100mb) echo 0 ;;
    1gb)   echo 1 ;;
    4gb)   echo 4 ;;
    8gb)   echo 8 ;;
    16gb)  echo 16 ;;
    *)     echo 99 ;;
  esac
}

# -------------------------------------------------------------------
# Stage 3: sweep
# -------------------------------------------------------------------
mkdir -p "$RESULTS_DIR"
echo "=== Stage 3: sweep -> $RESULTS_DIR ==="

# provenance
echo "$HOST" > "$RESULTS_DIR/_host.txt"
date -Iseconds > "$RESULTS_DIR/_date.txt"
sha256sum "$SIF" | awk '{print $1}' > "$RESULTS_DIR/_sif_sha256.txt"
(cd "$(dirname "$ARCTO_BIN_DIR")/.." 2>/dev/null && git rev-parse HEAD) > "$RESULTS_DIR/_arcto_commit.txt" 2>/dev/null || true
(cd "$(dirname "$ARCTO_BIN_DIR")/.." 2>/dev/null && git rev-parse --abbrev-ref HEAD) > "$RESULTS_DIR/_arcto_branch.txt" 2>/dev/null || true
echo "MAX_GB_FOR_GPU=$MAX_GB_FOR_GPU" > "$RESULTS_DIR/_config.txt"

DATA_TYPES="tti zeros random binary"
SIZES="10mb 100mb 1gb 4gb 8gb 16gb"
ALGOS="lz4 snappy cascaded"
MODES="baseline pinned adaptive"

n_done=0
n_total=0
# pre-count for the progress display
for size in $SIZES; do
  size_gb=$(size_to_gb "$size")
  if [ "$size_gb" -le "$MAX_GB_FOR_GPU" ]; then
    for dtype in $DATA_TYPES; do
      [ -f "$DATA_DIR/${dtype}_${size}.bin" ] || continue
      for algo in $ALGOS; do
        for mode in $MODES; do
          n_total=$((n_total + 1))
        done
      done
    done
  fi
done
echo "will run $n_total benchmark invocations"

for size in $SIZES; do
  size_gb=$(size_to_gb "$size")
  if [ "$size_gb" -gt "$MAX_GB_FOR_GPU" ]; then
    echo "[skip] all $size runs exceed MAX_GB_FOR_GPU=$MAX_GB_FOR_GPU"
    continue
  fi

  # smaller iter count for the big workloads to keep job time bounded
  if [ "$size_gb" -ge 8 ]; then
    iters="${ITERS:-3}"
  else
    iters="${ITERS:-5}"
  fi

  for dtype in $DATA_TYPES; do
    input="$DATA_DIR/${dtype}_${size}.bin"
    [ -f "$input" ] || { echo "[skip] $input missing"; continue; }

    for algo in $ALGOS; do
      for mode in $MODES; do
        case "$mode" in
          baseline) flags="-P false -A false" ;;
          pinned)   flags="-P true  -A false" ;;
          adaptive) flags="-P false -A true"  ;;
        esac
        csv="$RESULTS_DIR/${dtype}_${size}_${algo}_${mode}.csv"
        n_done=$((n_done + 1))
        printf "[%3d/%3d %s] %-8s %-5s %-9s %-9s\n" \
          "$n_done" "$n_total" "$(date +%H:%M:%S)" "$dtype" "$size" "$algo" "$mode"
        singularity exec --rocm "$SIF" bash -c \
          "LD_LIBRARY_PATH=$ARCTO_LIB_DIR:\$LD_LIBRARY_PATH \
           $ARCTO_BIN_DIR/benchmark_${algo}_chunked \
             -f $input -c true $flags -R true -w 1 -i $iters" \
          > "$csv" 2> "$csv.stderr" || echo "  FAIL: see $csv.stderr"
      done
    done
  done
done

echo ""
echo "=== sweep done. CSVs: $(ls $RESULTS_DIR/*.csv 2>/dev/null | wc -l) ==="
echo ""
echo "to keep the home quota free, optionally remove the scratch:"
echo "  rm -rf $DATA_DIR"
