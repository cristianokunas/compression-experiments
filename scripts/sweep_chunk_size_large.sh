#!/bin/bash
# MI300X chunk-size sweep: does HBM3 + Infinity Cache prefer larger chunks?
#
# Default chunked benchmark uses 64 KB chunks (1600 chunks on a 100 MB
# input). MI300X has 5.3 TB/s HBM3 and 256 MB Infinity Cache -- both
# typically reward larger contiguous accesses. This sweep keeps everything
# else fixed (same SIF arcto@8599fbf, same iteration count, same TTI
# inputs) and only varies -p chunk_size in {64K, 256K, 1M, 4M, 16M}.
#
# Uses the existing run_benchmarks_auto.sh (already supports -p), no
# code change needed. Runs both baseline AND -P (pinned input) so we
# also see how the chunk-size effect interacts with coalesce+pin.
#
# Restricted to medium + large TTI: those are the paper-anchor datasets
# and isolating to TTI keeps the matrix manageable (~60 benchmark calls,
# ~15-20 min total wall time).

set -e

SIF=/home/ckunas/compression-experiments/arcto_gfx942.sif
TD_FULL=/home/ckunas/testdata
TS=$(date +%Y%m%d_%H%M%S)
OUT=/home/ckunas/results/MI300X_CHUNK_SWEEP_${TS}
mkdir -p "$OUT"

[ -f "$SIF" ] || { echo "missing $SIF"; exit 1; }

# Curated testdata subset: only medium + large TTI. Use HARDLINKS (not
# symlinks) so run_benchmarks_auto.sh's `find -type f` matches them.
# Same filesystem so no disk cost; same inode shared with the original.
TD_TTI=/home/ckunas/testdata_tti_only
rm -rf "$TD_TTI"
mkdir -p "$TD_TTI"
ln "$TD_FULL/medium_TTI_100.bin"  "$TD_TTI/medium_TTI_100.bin"
ln "$TD_FULL/large_TTI_1024.bin"  "$TD_TTI/large_TTI_1024.bin"

# Chunk sizes (bytes). 4x ratios across nearly 3 orders of magnitude.
#   64K = 65536       (current default)
#  256K = 262144
#    1M = 1048576
#    4M = 4194304
#   16M = 16777216
CHUNK_SIZES="65536 262144 1048576 4194304 16777216"

cd /home/ckunas/compression-experiments

echo "== MI300X chunk-size sweep =="
echo "  SIF:    $SIF"
echo "  data:   $TD_TTI (medium + large TTI only)"
echo "  out:    $OUT"
echo "  chunks: $CHUNK_SIZES"
echo

for chunk in $CHUNK_SIZES; do
  for mode in baseline pinned; do
    flag=""
    [ "$mode" = "pinned" ] && flag="-P"
    out_dir="$OUT/${mode}_chunk${chunk}"
    mkdir -p "$out_dir"
    echo "== chunk=$chunk  mode=$mode =="
    singularity exec --rocm -B "$TD_TTI:$TD_TTI" -B /home/ckunas:/home/ckunas "$SIF" \
        ./scripts/run_benchmarks_auto.sh \
            -d "$TD_TTI" \
            -o "$out_dir" \
            -p "$chunk" \
            -i 10 -w 2 \
            --skip-testdata \
            $flag 2>&1 | grep -E "^\\[INFO\\] *(Ratio|Total)|Benchmark Configuration|chunk|Total tests" | head -10
  done
done

echo
echo "== DONE =="
find "$OUT" -name results.csv | wc -l
echo "out: $OUT"
