#!/bin/bash
# Follow-up: chunk sizes SMALLER than default 64K.
# Hypothesis: at 64K we have 1600 chunks = 1600 waves on LZ4 (9.35% occ).
# 16K -> 6400 waves -> potentially ~37% occ. May lift throughput
# linearly if per-launch overhead doesn't dominate.
set -e

SIF=/home/ckunas/compression-experiments/arcto_gfx942.sif
TD_FULL=/home/ckunas/testdata
TS=$(date +%Y%m%d_%H%M%S)
OUT=/home/ckunas/results/MI300X_CHUNK_SWEEP_SMALL_${TS}
mkdir -p "$OUT"

TD_TTI=/home/ckunas/testdata_tti_only
[ -d "$TD_TTI" ] || { rm -rf "$TD_TTI"; mkdir -p "$TD_TTI"; \
    ln "$TD_FULL/medium_TTI_100.bin" "$TD_TTI/medium_TTI_100.bin"; \
    ln "$TD_FULL/large_TTI_1024.bin" "$TD_TTI/large_TTI_1024.bin"; }

# 8K, 16K, 32K, plus 64K reference baseline
CHUNK_SIZES="8192 16384 32768 65536"

cd /home/ckunas/compression-experiments
echo "== smaller-chunk sweep =="
echo "  chunks: $CHUNK_SIZES"
echo

for chunk in $CHUNK_SIZES; do
  for mode in baseline pinned; do
    flag=""
    [ "$mode" = "pinned" ] && flag="-P"
    out_dir="$OUT/${mode}_chunk${chunk}"
    mkdir -p "$out_dir"
    echo "== chunk=$chunk mode=$mode =="
    singularity exec --rocm -B "$TD_TTI:$TD_TTI" -B /home/ckunas:/home/ckunas "$SIF" \
        ./scripts/run_benchmarks_auto.sh \
            -d "$TD_TTI" -o "$out_dir" -p "$chunk" -i 10 -w 2 \
            --skip-testdata $flag 2>&1 | grep -E "Compression throughput|ratio" | head -3
  done
done

echo "DONE -> $OUT"
