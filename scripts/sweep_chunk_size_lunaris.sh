#!/bin/bash
# RX 7900 XT (lunaris, gfx1100) chunk-size sweep.
#
# Cross-validation of the wave-count-formula derived on MI300X:
#   optimal_chunk = input_size / wave_slot_count
# RX 7900 XT: ~3072 wave slots, 100MB input -> prediction: ~32K
#
# Avoids the gfx1100 SIF (which bundles old binaries lacking the -P
# flag) by invoking the local build_canon binaries directly inside the
# SIF's ROCm runtime. Outputs ICCSA26-comparable CSVs.

set -e

SIF=/ssd/cakunas/arcto_gfx1100_v3.sif
LOCAL_BIN=/ssd/cakunas/arcto/build_canon/bin
LOCAL_LIB=/ssd/cakunas/arcto/build_canon/lib
TD=/ssd/cakunas/compression-experiments/testdata
TS=$(date +%Y%m%d_%H%M%S)
OUT=/ssd/cakunas/results/RX7900XT_CHUNK_SWEEP_${TS}
mkdir -p "$OUT"

# Header matching ICCSA26 + paper2 schema
CSV_HEADER="Algorithm,TestFile,FileSizeBytes,FileSizeMB,ChunkSize,CompressionRatio,CompThroughputGBs,DecompThroughputGBs,CompTimeMs,DecompTimeMs,TransferH2DMs,TransferD2HMs,TotalTimeMs,AvgChunkTimeMs,CompThroughputStdDev,DecompThroughputStdDev,CompTimeStdDevMs,DecompTimeStdDevMs,NodeName,GPU,GPUArch,EnvLabel,Iterations,Warmup,Timestamp"

NODE=$(hostname)
ITERS=10
WARMUP=2

# 8K..4M sweep. Predicted optimum on gfx1100: ~32K.
CHUNK_SIZES="8192 16384 32768 65536 262144 1048576 4194304"

declare -A FILES=(
    [medium_TTI_100.bin]=104857600
    [large_TTI_1024.bin]=719323136
)

echo "== RX 7900 XT chunk-size sweep =="
echo "  SIF (ROCm):  $SIF"
echo "  local bins:  $LOCAL_BIN"
echo "  out:         $OUT"
echo "  chunks:      $CHUNK_SIZES"
echo

for chunk in $CHUNK_SIZES; do
  for mode in baseline pinned; do
    pflag=""
    label=RX7900XT
    [ "$mode" = "pinned" ] && { pflag="-P true"; label=RX7900XT_PINNED; }

    out_dir="$OUT/${mode}_chunk${chunk}"
    mkdir -p "$out_dir"
    csv="$out_dir/results.csv"
    echo "$CSV_HEADER" > "$csv"

    echo "== chunk=$chunk mode=$mode =="

    for algo in lz4 snappy cascaded; do
      for fname in medium_TTI_100.bin large_TTI_1024.bin; do
        fsize=${FILES[$fname]}
        fmb=$(awk "BEGIN{printf \"%.2f\", $fsize/1048576}")
        rawlog="$out_dir/${algo}_${fname}_chunk${chunk}.log"

        # Run inside SIF for ROCm runtime, using local build binaries.
        result=$(singularity exec --rocm -B /ssd/cakunas:/ssd/cakunas "$SIF" bash -c "
          export LD_LIBRARY_PATH=$LOCAL_LIB:\$LD_LIBRARY_PATH
          $LOCAL_BIN/benchmark_${algo}_chunked \
            -f $TD/$fname -i $ITERS -w $WARMUP -p $chunk -c true -t false $pflag 2>/dev/null
        " | tee "$rawlog" | tail -1)

        if [[ -z "$result" || "$result" == *Files* ]]; then
          row="$algo,$fname,$fsize,$fmb,$chunk,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,$NODE,RX7900XT,gfx1100,$label,$ITERS,$WARMUP,$TS"
          echo "  [FAIL] $algo $fname"
        else
          IFS=',' read -ra f <<< "$result"
          row="$algo,$fname,$fsize,$fmb,$chunk,${f[8]},${f[9]},${f[10]},${f[11]},${f[12]},${f[13]},${f[14]},${f[15]},${f[16]},${f[17]},${f[18]},${f[19]},${f[20]},$NODE,RX7900XT,gfx1100,$label,$ITERS,$WARMUP,$TS"
          printf "  %-9s %-30s ratio=%s comp=%s decomp=%s\n" "$algo" "$fname" "${f[8]}" "${f[9]}" "${f[10]}"
        fi
        echo "$row" >> "$csv"
      done
    done
  done
done

echo
echo "== DONE =="
find "$OUT" -name results.csv | wc -l
echo "out: $OUT"
