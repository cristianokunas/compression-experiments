#!/bin/bash
# =============================================================================
# sweep_cstar.sh -- generic chunk-size (c*) sweep for ARCTO codecs on ANY AMD GPU.
#
# Measures the kernel-only compression throughput of LZ4 / Snappy / Cascaded
# across a range of chunk sizes and reports the empirical optimum c* per codec,
# plus the speedup over the inherited 64 KiB default. Self-contained: detects
# the GPU from rocminfo, derives the wave-slot count W = CU x MaxWavesPerCU,
# prints the wave-saturation prediction (reference only), generates a small
# synthetic input if none is given, runs the sweep, and prints the winner.
#
# Runs the benchmark binaries NATIVELY (no container). You only need:
#   - ARCTO_BIN / ARCTO_LIB : a build of arcto compiled for this host+arch
#                             (benchmark_<algo>_chunked + libarcto.so)
#   - ROCM_LIB              : the host ROCm runtime lib dir
# so the binaries must be linkable against the host's glibc/ROCm. The defaults
# below are EXAMPLES from one machine; override them for your environment.
#
# Methodology note: the empirical c* is the source of truth. The S/W formula is
# NOT a closed form for c* (the optimum is a per-(arch,codec) constant ~8 KiB,
# roughly independent of workload size); W only predicts the SATURATION size
# S_sat = W * c_floor and the octave where to start the sweep. See
# paper/ARCTO-optim/analysis/cstar_reframing.md.
#
# Usage:
#   ARCTO_BIN=/path/build/bin ARCTO_LIB=/path/build/lib ./scripts/sweep_cstar.sh
#   DATA=/path/medium_TTI_100.bin ./scripts/sweep_cstar.sh    # use real data
#   ALGOS="lz4" CHUNKS="8192 16384 32768 65536" ./scripts/sweep_cstar.sh
#
# Knobs (env overrides; defaults shown are illustrative examples):
#   ARCTO_BIN  dir with benchmark_<algo>_chunked
#   ARCTO_LIB  dir with libarcto.so
#   ROCM_LIB   host ROCm lib dir (provides libamdhip64.so.* etc.)
#   DATA       input file to sweep (default: generated synthetic)
#   DATA_MB    synthetic size in MiB (default: derived from W, >=128, >=4*S_sat)
#   ALGOS      codecs (default: "lz4 snappy cascaded")
#   CHUNKS     chunk sizes in bytes (default: 8K..4M octaves)
#   ITERS/WARMUP measured/warmup iterations (default 10/2)
#   OUTROOT    results root
#   C_FLOOR    assumed per-codec floor for the S_sat estimate (default 8 KiB)
# =============================================================================
set -u

# ---- EXAMPLE defaults: point these at YOUR arcto build / ROCm ----
ARCTO_BIN="${ARCTO_BIN:-/ssd/cakunas/arcto/build_norev/bin}"
ARCTO_LIB="${ARCTO_LIB:-/ssd/cakunas/arcto/build_norev/lib}"
ROCM_LIB="${ROCM_LIB:-/opt/rocm/lib}"
ALGOS="${ALGOS:-lz4 snappy cascaded}"
CHUNKS="${CHUNKS:-8192 16384 32768 65536 131072 262144 1048576 4194304}"
ITERS="${ITERS:-10}"
WARMUP="${WARMUP:-2}"
DATA="${DATA:-}"
DATA_MB="${DATA_MB:-}"
OUTROOT="${OUTROOT:-/ssd/cakunas/results}"
C_FLOOR="${C_FLOOR:-8192}"
ROCMINFO="$(command -v rocminfo || echo /opt/rocm/bin/rocminfo)"

export LD_LIBRARY_PATH="$ARCTO_LIB:$ROCM_LIB:${LD_LIBRARY_PATH:-}"

# ---- preflight: the binary must load natively against host glibc/ROCm ----
first_algo="$(set -- $ALGOS; echo "$1")"
BIN0="$ARCTO_BIN/benchmark_${first_algo}_chunked"
if ! "$BIN0" --help 2>/dev/null | grep -qiE "usage|options"; then
  echo "ERROR: cannot run $BIN0 natively. Check that:"
  echo "  - ARCTO_BIN/ARCTO_LIB point at a build compiled for this host+arch"
  echo "  - the build's glibc/libstdc++ are <= the host's"
  echo "  - ROCM_LIB ($ROCM_LIB) provides libamdhip64.so.*"
  echo "diagnostics:"; "$BIN0" --help 2>&1 | head -3
  exit 1
fi

# ---- detect GPU: first GPU agent's gfx, CU count, max waves per CU ----
read -r GFX CU WAVES <<< "$(
  "$ROCMINFO" 2>/dev/null | awk '
    /^ *Name: *gfx/        {gfx=$2}
    /^ *Compute Unit:/     {cu=$3}
    /^ *Max Waves Per CU:/ {sub(/\(.*/,"",$5); print gfx, cu, $5; exit}'
)"
: "${GFX:=unknown}"; : "${CU:=0}"; : "${WAVES:=32}"
W=$(( CU * WAVES ))
[ "$W" -gt 0 ] || { echo "ERROR: could not read CU/waves from rocminfo (GFX=$GFX CU=$CU)"; exit 1; }

# ---- wave-saturation prediction (reference only; NOT the optimum) ----
S_SAT=$(( W * C_FLOOR ))                  # bytes: min workload to saturate
S_SAT_MB=$(( S_SAT / 1048576 ))
if [ -z "$DATA_MB" ]; then
  DATA_MB=$(( 4 * S_SAT_MB ))             # comfortably above saturation
  [ "$DATA_MB" -lt 128 ] && DATA_MB=128
fi

echo "=== GPU (rocminfo) ==="
echo "  arch=$GFX  CU=$CU  MaxWavesPerCU=$WAVES  -> W = CU*Waves = $W wave slots"
echo "  run mode: native (ARCTO_BIN=$ARCTO_BIN)"
echo "=== wave-saturation reference (not the optimum) ==="
echo "  c_floor(assumed)=$((C_FLOOR/1024)) KiB  ->  S_sat = W*c_floor = ${S_SAT_MB} MiB"
echo "  sweep workload  = ${DATA_MB} MiB  (>= 4*S_sat keeps the device saturated)"
echo "  legacy S/W at this workload = $(( DATA_MB*1048576 / W / 1024 )) KiB  (would WRONGLY scale with size)"
echo

# ---- input data: use DATA if given, else generate small synthetic (70% pattern + 30% random) ----
if [ -z "$DATA" ]; then
  CACHE="$OUTROOT/_cstar_data"; mkdir -p "$CACHE"
  DATA="$CACHE/synth_${DATA_MB}mb.bin"
  want=$(( DATA_MB * 1048576 ))
  if [ ! -f "$DATA" ] || [ "$(stat -c%s "$DATA" 2>/dev/null || echo 0)" != "$want" ]; then
    echo "generating synthetic input: $DATA (${DATA_MB} MiB, 70% pattern + 30% random)"
    pat=$(( DATA_MB * 7 / 10 )); rnd=$(( DATA_MB - pat ))
    python3 - "$DATA" "$pat" "$rnd" <<'PY' 2>/dev/null || \
      dd if=/dev/urandom of="$DATA" bs=1M count="$DATA_MB" status=none
import sys, os
path, pat_mb, rnd_mb = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
block = (bytes(range(256)) * 4096)[:1024*1024]   # 1 MiB repeating 0x00..0xFF
with open(path, "wb") as f:
    for _ in range(pat_mb):
        f.write(block)
    f.write(os.urandom(rnd_mb * 1024 * 1024))
PY
  fi
fi
echo "input: $DATA  ($(stat -c%s "$DATA" 2>/dev/null) bytes)"
echo

# ---- sweep ----
TS=$(date +%Y%m%d_%H%M%S)
OUT="$OUTROOT/CSTAR_${GFX}_${TS}"; mkdir -p "$OUT"
CSV="$OUT/cstar.csv"
echo "gpu,gfx,cu,waves,wave_slots,algo,data_mb,chunk,ratio,comp_gbs,decomp_gbs" > "$CSV"

for algo in $ALGOS; do
  bin="$ARCTO_BIN/benchmark_${algo}_chunked"
  echo "== $algo =="
  for chunk in $CHUNKS; do
    line=$("$bin" -f "$DATA" -i "$ITERS" -w "$WARMUP" -p "$chunk" -c true -t false 2>/dev/null | tail -1)
    IFS=',' read -ra F <<< "$line"
    ratio="${F[8]:-NA}"; comp="${F[9]:-NA}"; decomp="${F[10]:-NA}"
    echo "$GFX,$GFX,$CU,$WAVES,$W,$algo,$DATA_MB,$chunk,$ratio,$comp,$decomp" >> "$CSV"
    printf "  chunk=%-8s ratio=%-6s comp=%-7s decomp=%-7s GB/s\n" \
      "$((chunk/1024))K" "$ratio" "$comp" "$decomp"
  done
done

# ---- summary: empirical c* per codec + speedup vs 64K ----
echo
echo "=== empirical c* (max kernel compress throughput) ==="
awk -F, 'NR>1 && $10!="NA" {
  thr[$6"@"$8]=$10
  if ($10+0 > best[$6]+0) { best[$6]=$10; bestc[$6]=$8 }
  algos[$6]=1
}
END {
  printf "  %-9s %-10s %-12s %-12s %-8s\n","codec","c*","comp@c*","comp@64K","speedup"
  for (a in algos) {
    d=thr[a"@65536"]; sp=(d>0)?best[a]/d:0
    printf "  %-9s %-10s %-12.2f %-12s %.2fx\n", a, bestc[a]/1024"K", best[a], (d>0?sprintf("%.2f",d):"NA"), sp
  }
}' "$CSV"

echo
echo "CSV: $CSV"
echo "NOTE: c* is the EMPIRICAL optimum. W only sets S_sat=${S_SAT_MB}MiB and the start octave."
