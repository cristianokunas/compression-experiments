#!/bin/bash
# A3: counter profile of the compress kernel at ht128 vs ht16384 (baseline
# builds, clear loop present). Two PMC passes to stay within multiplexing.
set -u
export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:$PATH
export HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0}
ROOT=/ssd/cakunas/campaign-htocc
IN=/ssd/cakunas/compression-experiments/testdata/large_TTI_1024.bin
OUT=$ROOT/results_a3_pmc
mkdir -p "$OUT"
/tmp/hipmin >/dev/null 2>&1 || { echo "ABORT: HIP stack unhealthy"; exit 1; }
{ echo "date=$(date -Is)"; echo "host=$(hostname)"; echo "rocm=$(cat /opt/rocm/.info/version)";
  echo "builds=baseline(0cd2506) ht128,ht16384"; echo "input=$IN"; } > "$OUT/provenance.txt"

for HT in 128 16384; do
  B=$ROOT/arcto/build_ht$HT
  export LD_LIBRARY_PATH=$B/lib:/opt/rocm/lib
  for SET in "GL2C_HIT GL2C_MISS GRBM_GUI_ACTIVE" "VALUInsts MemUnitBusy SQ_WAVES"; do
    TAGSET=$(echo "$SET" | tr ' ' '-' | cut -c1-24)
    rocprofv3 --pmc $SET -d "$OUT/ht${HT}_${TAGSET}" -o "prof" -- \
      $B/bin/benchmark_lz4_chunked -f "$IN" -p 65536 -w 1 -i 3 -g 0 \
      > "$OUT/ht${HT}_${TAGSET}.stdout" 2> "$OUT/ht${HT}_${TAGSET}.stderr"
    echo "ht=$HT set=[$SET] rc=$?"
  done
done
echo "===== A3 DONE ====="
find "$OUT" -name "*counter*" | head
