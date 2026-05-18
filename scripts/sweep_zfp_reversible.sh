#!/bin/bash
# ZFP-Reversible sweep -- CSV output for direct comparison vs LZ4 lossless.
# Runs on the 4 medium TTI/zeros/random/binary datasets + large TTI on
# whatever GPU we're running on (driven by the SIF's --rocm device).
set -e

SIF=${SIF:-/ssd/cakunas/arcto_gfx1100_v3.sif}
LOCAL_BIN=${LOCAL_BIN:-/ssd/cakunas/arcto/build_canon/bin}
LOCAL_LIB=${LOCAL_LIB:-/ssd/cakunas/arcto/build_canon/lib}
TD=${TD:-/ssd/cakunas/compression-experiments/testdata}
OUT=${OUT:-/ssd/cakunas/results/RX7900XT_REVERSIBLE_$(date +%Y%m%d_%H%M%S)}
GPU_LABEL=${GPU_LABEL:-RX7900XT}
GPU_ARCH=${GPU_ARCH:-gfx1100}
NODE=$(hostname)
mkdir -p "$OUT"

# CSV in the standard 25-col paper2 schema (same as run_benchmarks_auto.sh)
CSV=$OUT/results_reversible.csv
echo "Algorithm,TestFile,FileSizeBytes,FileSizeMB,ChunkSize,CompressionRatio,CompThroughputGBs,DecompThroughputGBs,CompTimeMs,DecompTimeMs,TransferH2DMs,TransferD2HMs,TotalTimeMs,AvgChunkTimeMs,CompThroughputStdDev,DecompThroughputStdDev,CompTimeStdDevMs,DecompTimeStdDevMs,NodeName,GPU,GPUArch,EnvLabel,Iterations,Warmup,Timestamp" > "$CSV"

TS=$(date +%Y%m%d_%H%M%S)
ITERS=10
WARMUP=2

run_one() {
  local fname=$1 shape=$2 iters=$3
  local file="$TD/$fname"
  [ -f "$file" ] || { echo "missing $file"; return; }
  local fsize=$(stat -c%s "$file")
  local fmb=$(awk "BEGIN{printf \"%.2f\", $fsize/1048576}")
  local raw="$OUT/zfp_reversible_${fname%.bin}.log"

  local result=$(singularity exec --rocm -B /ssd/cakunas:/ssd/cakunas "$SIF" bash -c "
    export LD_LIBRARY_PATH=$LOCAL_LIB:\$LD_LIBRARY_PATH
    $LOCAL_BIN/benchmark_zfp_single -c -f $file -m reversible -3 $shape -i $iters -w $WARMUP 2>/dev/null
  " | tee "$raw" | tail -1)

  if [[ -z "$result" || "$result" == *Files* ]]; then
    echo "  [FAIL] $fname"
    echo "zfp_reversible,$fname,$fsize,$fmb,0,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,FAILED,$NODE,$GPU_LABEL,$GPU_ARCH,$GPU_LABEL,$iters,$WARMUP,$TS" >> "$CSV"
    return
  fi
  IFS=',' read -ra f <<< "$result"
  echo "zfp_reversible,$fname,$fsize,$fmb,0,${f[8]},${f[9]},${f[10]},${f[11]},${f[12]},${f[13]},${f[14]},${f[15]},${f[16]},${f[17]},${f[18]},${f[19]},${f[20]},$NODE,$GPU_LABEL,$GPU_ARCH,$GPU_LABEL,$iters,$WARMUP,$TS" >> "$CSV"
  printf "  %-25s ratio=%-7s comp=%-8s GB/s decomp=%-8s GB/s\n" "$fname" "${f[8]}" "${f[9]}" "${f[10]}"
}

echo "== ZFP-Reversible sweep =="
echo "  out: $OUT"
echo

# Shapes derived from existing TTI / file sizes
# medium 100MB at 448x448x130 (104366080 bytes = 26091520 floats; same shape used by paper baseline)
# large 686MB at 896x896x224
# small 10MB at 128x128x160 (10485760 bytes = 2621440 floats)
# xlarge 3.7GB at 1024x1024x944 ≈ 3.86GB (xlarge_TTI is 3956277248 bytes = 989069312 floats; 1024*1024*944 = 989855744 close but bigger; use 1024x1024x944 -- it'll truncate)
# For synth files at "medium" size we use the same medium TTI shape since they're 100MB exactly

run_one medium_TTI_100.bin     448,448,130 $ITERS
run_one medium_zeros_100.bin   448,448,130 $ITERS
run_one medium_random_100.bin  448,448,130 $ITERS
run_one medium_binary_100.bin  448,448,130 $ITERS

run_one large_TTI_1024.bin     896,896,224 $ITERS
# large synth are 1024MB = 1073741824 bytes = 268435456 floats. Use 1024x512x512 = 268435456.
run_one large_zeros_1024.bin   1024,512,512 $ITERS
run_one large_random_1024.bin  1024,512,512 $ITERS
run_one large_binary_1024.bin  1024,512,512 $ITERS

# small 10MB
run_one small_TTI_10.bin       128,128,160 5
run_one small_zeros_10.bin     128,128,160 5
run_one small_random_10.bin    128,128,160 5
run_one small_binary_10.bin    128,128,160 5

echo
echo "== DONE =="
wc -l "$CSV"
