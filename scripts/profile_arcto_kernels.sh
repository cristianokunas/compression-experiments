#!/bin/bash
# =============================================================================
# rocprofv3 kernel-trace profiling for ARCTO benchmarks on AMD GPUs.
#
# Drives benchmark_${algo}_chunked through rocprofv3 with kernel + HIP API +
# memcpy tracing enabled, producing per-algorithm subdirectories with
#   - <algo>_trace_kernel_stats.csv  (per-kernel time aggregated)
#   - <algo>_trace_hip_api_stats.csv (per-HIP-API call aggregated)
#   - <algo>_trace_hip_api_trace.csv (raw timeline)
#   - <algo>_trace_agent_info.csv    (GPU agents enumerated)
#   - <algo>_trace_domain_stats.csv  (per-tracing-domain summary)
#
# The kernel_stats.csv is the headline artifact: it tells which kernel
# dominates total time and how its per-call cost compares across algorithms.
# Used to confirm the LZ4 wave64-mismatch hypothesis on MI300X
# (paper/ARCTO-optim/results/MI300X_PROFILE_*/FINDINGS.md).
#
# Required environment / defaults:
#   SIF      path to ARCTO singularity image (default: ./arcto_gfx942.sif)
#   TD       host testdata directory (default: $HOME/testdata, bind to /data)
#   FILE     relative path inside /data (default: medium_TTI_100.bin)
#   ITERS    benchmark iterations (default: 5  -- low to keep rocprof overhead manageable)
#   WARMUP   benchmark warmups (default: 2)
#   ALGOS    space-separated list (default: "lz4 snappy cascaded")
#   OUT_ROOT base output directory (default: $HOME/results)
#
# Usage:
#   ./scripts/profile_arcto_kernels.sh
#   SIF=arcto_gfx1100.sif ALGOS="lz4" ./scripts/profile_arcto_kernels.sh
# =============================================================================

set -e

SIF="${SIF:-./arcto_gfx942.sif}"
TD="${TD:-$HOME/testdata}"
FILE="${FILE:-medium_TTI_100.bin}"
ITERS="${ITERS:-5}"
WARMUP="${WARMUP:-2}"
ALGOS="${ALGOS:-lz4 snappy cascaded}"
OUT_ROOT="${OUT_ROOT:-$HOME/results}"

TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="$OUT_ROOT/MI_PROFILE_${TS}"
mkdir -p "$OUT_DIR"

[ -f "$SIF" ] || { echo "missing SIF $SIF"; exit 1; }
[ -d "$TD" ]  || { echo "missing testdata dir $TD"; exit 1; }
[ -f "$TD/$FILE" ] || { echo "missing testfile $TD/$FILE"; exit 1; }

echo "== profiling ARCTO kernels =="
echo "  SIF:   $SIF"
echo "  file:  $TD/$FILE"
echo "  iters: $ITERS  warmup: $WARMUP"
echo "  algos: $ALGOS"
echo "  out:   $OUT_DIR"
echo

profile_one() {
  local algo=$1
  local out=$OUT_DIR/${algo}_kernel_trace
  mkdir -p "$out"
  echo "== [trace] $algo =="
  singularity exec --rocm -B "$TD:/data" -B "$HOME:$HOME" "$SIF" \
    rocprofv3 \
      --kernel-trace \
      --hip-trace \
      --memory-copy-trace \
      --stats \
      -d "$out" \
      -o ${algo}_trace \
      -f csv \
      -- /opt/arcto/build/bin/benchmark_${algo}_chunked \
            -f /data/$FILE -i $ITERS -w $WARMUP -c true 2>&1 | tail -3
  echo "  artifacts:"
  ls "$out" | head -5
  echo
}

for algo in $ALGOS; do
  profile_one "$algo"
done

echo "== DONE =="
echo "headline artifacts:"
for algo in $ALGOS; do
  printf "  %-10s -> %s/%s_kernel_trace/%s_trace_kernel_stats.csv\n" \
      "$algo" "$OUT_DIR" "$algo" "$algo"
done
