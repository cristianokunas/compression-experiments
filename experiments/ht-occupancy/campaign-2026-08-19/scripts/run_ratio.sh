#!/bin/bash
# Does a smaller hash table cost compression RATIO on compressible data?
# The 686MB TTI field has ratio 1.04 (essentially incompressible), so it cannot
# answer this. Walk a compressibility ladder instead, at the 64K default chunk.
set -u
export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
export HIP_VISIBLE_DEVICES=0
cd /ssd/cakunas/arcto || exit 1
/tmp/hipmin >/dev/null 2>&1 || { echo "ABORTADO: stack HIP nao esta sa"; exit 1; }

OUT=results_ratio; mkdir -p "$OUT"
{ echo "date=$(date -Is)"; echo "git=$(git rev-parse HEAD)"; echo "chunk=65536 dup=64 reps=3"; } > "$OUT/provenance.txt"

for F in synth_zeros_1mb tti_rsf_64x64x64_t000 tti_rsf_64x64x64_t050 synth_binary_1mb synth_random_1mb; do
  for HT in 16384 2048; do
    for R in 1 2 3; do
      ./build_ht$HT/bin/benchmark_lz4_chunked -f tests/data/$F.bin -p 65536 \
        -x 64 -w 2 -i 10 -c true -g 0 > "$OUT/${F}_ht${HT}_r${R}.csv" 2>"$OUT/${F}_ht${HT}_r${R}.err"
      printf "%-26s HT=%-6s rep=%s rc=%s\n" "$F" "$HT" "$R" "$?"
    done
  done
done
echo "===== LADDER CONCLUIDA ====="
