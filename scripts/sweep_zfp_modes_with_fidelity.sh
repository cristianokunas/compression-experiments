#!/bin/bash
# ZFP all-modes-with-fidelity sweep: generates ratio + comp/decomp throughput
# + fidelity metrics (max_abs_diff, RMSE, PSNR, max_rel) for every ZFP mode
# on TTI workload. Designed to produce the paper's "lossy validation" table:
# how much loss does the user pay for what compression ratio?
#
# Modes covered:
#   reversible            (lossless reference)
#   fixed_accuracy 1e-3   (production-safe sweet spot for RTM)
#   fixed_accuracy 1e-4   (conservative)
#   fixed_accuracy 1e-5
#   fixed_accuracy 1e-6
#   fixed_precision 12    (visually lossless equivalent)
#   fixed_precision 20    (numerically near-lossless)
#   fixed_rate 8          (4x bit budget)
#   fixed_rate 16         (2x bit budget)
#
# All on medium TTI 100MB (448x448x130) and large TTI 686MB (896x896x224).
set -e

SIF=/ssd/cakunas/arcto_gfx1100_v3.sif
B=/ssd/cakunas/arcto/build_canon/bin/benchmark_zfp_single
TD=/ssd/cakunas/compression-experiments/testdata
TS=$(date +%Y%m%d_%H%M%S)
OUT=/ssd/cakunas/results/RX7900XT_ZFP_FIDELITY_${TS}
mkdir -p "$OUT"
NODE=$(hostname)

# Schema: standard 21-col + 5 fidelity cols (matches the updated benchmark_zfp_single output)
CSV=$OUT/results_zfp_fidelity.csv
HDR="Algorithm,Mode,Param,TestFile,FileSizeBytes,FileSizeMB,Shape,CompressionRatio,CompThroughputGBs,DecompThroughputGBs,CompTimeMs,DecompTimeMs,TransferH2DMs,TotalTimeMs,MaxAbsDiff,RMSE,PSNR_dB,MaxRelError,AmplitudeRange,NodeName,GPU,GPUArch,EnvLabel,Iterations,Warmup,Timestamp"
echo "$HDR" > "$CSV"

run_one() {
  local mode=$1 param=$2 fname=$3 shape=$4
  local iters=10 warmup=2
  local file="$TD/$fname"
  local fsize=$(stat -c%s "$file")
  local fmb=$(awk "BEGIN{printf \"%.2f\", $fsize/1048576}")
  local raw="$OUT/zfp_${mode}_${param}_${fname%.bin}.log"

  local r=""
  if [ "$mode" = "reversible" ]; then
    r=$(singularity exec --rocm -B /ssd/cakunas:/ssd/cakunas "$SIF" bash -c "
      export LD_LIBRARY_PATH=/ssd/cakunas/arcto/build_canon/lib:\$LD_LIBRARY_PATH
      $B -c -f $file -m reversible -3 $shape -i $iters -w $warmup 2>/dev/null
    ")
  else
    r=$(singularity exec --rocm -B /ssd/cakunas:/ssd/cakunas "$SIF" bash -c "
      export LD_LIBRARY_PATH=/ssd/cakunas/arcto/build_canon/lib:\$LD_LIBRARY_PATH
      $B -c -f $file -m $mode -r $param -3 $shape -i $iters -w $warmup 2>/dev/null
    ")
  fi
  echo "$r" > "$raw"
  local last=$(echo "$r" | tail -1)
  if [[ -z "$last" || "$last" == *Files* ]]; then
    echo "  [FAIL] $mode $param $fname"; return
  fi
  IFS=',' read -ra f <<< "$last"
  # Shape contains commas; rewrite with 'x' so it doesn't break the CSV.
  local shape_safe=$(echo "$shape" | tr ',' 'x')
  # Build the CSV row from standard fields (8=ratio, 9=comp, 10=decomp, 11=comp_ms, 12=decomp_ms, 13=h2d, 15=total, 21=max_abs, 22=rmse, 23=psnr, 24=max_rel, 25=amp_range)
  echo "zfp,$mode,$param,$fname,$fsize,$fmb,$shape_safe,${f[8]},${f[9]},${f[10]},${f[11]},${f[12]},${f[13]},${f[15]},${f[21]},${f[22]},${f[23]},${f[24]},${f[25]},$NODE,RX7900XT,gfx1100,RX7900XT_ZFP_FIDELITY,$iters,$warmup,$TS" >> "$CSV"
  printf "  %-18s %-6s %-22s ratio=%-6s comp=%-7s decomp=%-7s max_abs=%-10s PSNR=%s\n" \
    "$mode" "$param" "$fname" "${f[8]}" "${f[9]}" "${f[10]}" "${f[21]}" "${f[23]}"
}

echo "== ZFP all modes + fidelity sweep =="
echo "  out: $OUT"

for size_tag in "medium_TTI_100.bin 448,448,130" "large_TTI_1024.bin 896,896,224"; do
  set -- $size_tag
  fname=$1 shape=$2
  echo
  echo "=== $fname ==="
  run_one reversible       0    "$fname" "$shape"
  run_one fixed_accuracy   1e-3 "$fname" "$shape"
  run_one fixed_accuracy   1e-4 "$fname" "$shape"
  run_one fixed_accuracy   1e-5 "$fname" "$shape"
  run_one fixed_accuracy   1e-6 "$fname" "$shape"
  run_one fixed_precision  12   "$fname" "$shape"
  run_one fixed_precision  20   "$fname" "$shape"
  run_one fixed_rate       8    "$fname" "$shape"
  run_one fixed_rate       16   "$fname" "$shape"
done

echo
echo "== DONE =="
wc -l "$CSV"
