#!/bin/bash
# Hash-table-size sweep, decoupled from chunk size.
# One raw CSV per (HT, chunk, repetition) -- no aggregation on the node.
set -u
export ROCM_PATH=/opt/rocm
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
export HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0}
cd /ssd/cakunas/arcto || exit 1

IN=testdata/large_TTI_1024.bin
OUT=results_htsweep
REPS=${REPS:-5}
CHUNKS=${CHUNKS:-"8192 65536"}
HTS=${HTS:-"16384 8192 4096 2048"}
mkdir -p "$OUT"

# sanidade: nao medir com driver travado (ver /tmp/hipmin)
if ! /tmp/hipmin >/dev/null 2>&1; then
  echo "ABORTADO: stack HIP nao esta sa (/tmp/hipmin falhou). Faca o reload do amdgpu antes."; exit 1
fi

# provenance
{ echo "date=$(date -Is)"; echo "host=$(hostname)"; echo "git=$(git rev-parse HEAD)"; \
  echo "dirty=$(git status --porcelain | tr '\n' ';')"; echo "rocm=$(ls -d /opt/rocm-* )"; \
  echo "HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES"; echo "input=$IN ($(stat -c %s $IN) bytes)"; \
  echo "reps=$REPS chunks=$CHUNKS hts=$HTS"; } > "$OUT/provenance.txt"

for HT in $HTS; do
  BIN=build_ht$HT/bin/benchmark_lz4_chunked
  [ -x "$BIN" ] || { echo "SKIP HT=$HT (sem binario)"; continue; }
  for C in $CHUNKS; do
    for R in $(seq 1 "$REPS"); do
      F="$OUT/ht${HT}_c${C}_r${R}.csv"
      "$BIN" -f "$IN" -p "$C" -w 2 -i 10 -c true -g 0 > "$F" 2> "$F.err"
      rc=$?
      printf "HT=%-6s chunk=%-6s rep=%s rc=%s\n" "$HT" "$C" "$R" "$rc"
      [ $rc -ne 0 ] && head -3 "$F.err"
    done
  done
done
echo "===== CAMPANHA CONCLUIDA ====="
ls "$OUT" | wc -l
