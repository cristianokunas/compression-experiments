#!/bin/bash
# A/B for attempt A1: no-clear (b9671c5) vs baseline (0cd2506), both table sizes.
# Per-repetition throughput on large TTI + exact-bytes ratio gate on the ladder.
set -u
export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib
export HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0}
ROOT=/ssd/cakunas/campaign-htocc
IN=/ssd/cakunas/compression-experiments/testdata/large_TTI_1024.bin
OUT=$ROOT/results_a1_ab
REPS=${REPS:-30}
mkdir -p "$OUT"

# guard: never measure on a wedged stack
/tmp/hipmin >/dev/null 2>&1 || { echo "ABORT: HIP stack unhealthy (/tmp/hipmin failed)"; exit 1; }

{ echo "date=$(date -Is)"; echo "host=$(hostname)"; echo "rocm=$(cat /opt/rocm/.info/version)";
  echo "HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES"; echo "input=$IN ($(stat -c %s $IN) bytes)";
  echo "reps=$REPS"; echo "baseline_commit=0cd2506"; echo "a1_commit=b9671c5"; } > "$OUT/provenance.txt"

run_variant() {  # $1=tree-dir  $2=variant-name
  local tree=$1 name=$2
  for B in "$tree"/build_ht16384 "$tree"/build_ht128; do
    local bin=$B/bin/benchmark_lz4_chunked
    [ -x "$bin" ] || { echo "SKIP $B (sem binario)"; continue; }
    local ht; ht=$(cat "$B/HT_SIZE")          # tag derived from the build, never typed
    local tag="${name}_ht${ht}"
    for C in 65536 8192; do
      export LD_LIBRARY_PATH=$B/lib:/opt/rocm/lib
      ARCTO_PER_REP_CSV="$OUT/perrep.csv" ARCTO_PER_REP_TAG="${tag}_c${C}" \
        "$bin" -f "$IN" -p "$C" -w 5 -i "$REPS" -c true -g 0 > "$OUT/${tag}_c${C}.csv" 2> "$OUT/${tag}_c${C}.err"
      printf "%-28s chunk=%-6s rc=%s\n" "$tag" "$C" "$?"
    done
    # ratio gate: exact bytes across the ladder, chunk 64K
    for F in /ssd/cakunas/campaign-htocc/arcto/tests/data/*.bin; do
      local fn; fn=$(basename "$F" .bin)
      "$bin" -f "$F" -p 65536 -w 1 -i 2 -c true -g 0 -x 64 > "$OUT/ratio_${tag}_${fn}.csv" 2>/dev/null
    done
  done
}

run_variant "$ROOT/arcto"    baseline
run_variant "$ROOT/arcto-a1" a1
echo "===== A/B DONE ====="
ls "$OUT" | wc -l
