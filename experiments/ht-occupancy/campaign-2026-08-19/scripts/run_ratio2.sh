#!/bin/bash
# Extend the ratio ladder BELOW 2048 entries. The knee sweep found monotone gains
# down to 128 on ratio-1.04 data, where the match finder barely fires anyway.
# On genuinely compressible input a degenerate table should cost ratio -- measure it.
set -u
export ROCM_PATH=/opt/rocm PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
export HIP_VISIBLE_DEVICES=0
cd /ssd/cakunas/arcto || exit 1
/tmp/hipmin >/dev/null 2>&1 || { echo "ABORTADO: stack HIP nao esta sa"; exit 1; }
OUT=results_ratio2; mkdir -p "$OUT"
for F in synth_binary_1mb tti_rsf_64x64x64_t000 synth_zeros_1mb tti_rsf_64x64x64_t050; do
  for HT in 16384 2048 1024 512 256 128; do
    for R in 1 2 3; do
      ./build_ht$HT/bin/benchmark_lz4_chunked -f tests/data/$F.bin -p 65536 \
        -x 64 -w 2 -i 10 -c true -g 0 > "$OUT/${F}_ht${HT}_r${R}.csv" 2>/dev/null
      printf "%-24s HT=%-6s r%s rc=%s\n" "$F" "$HT" "$R" "$?"
    done
  done
done
echo "===== LADDER ESTENDIDA CONCLUIDA ====="
