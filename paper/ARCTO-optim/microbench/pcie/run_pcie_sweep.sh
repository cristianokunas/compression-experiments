#!/bin/bash
# run_pcie_sweep.sh
#
# Sweep transfer sizes through pcie_bw.cu and emit a CSV of H2D/D2H
# bandwidth for pageable and pinned host buffers. The purpose is to
# identify the knee of the bandwidth curve on the host-device link of
# the target machine, and validate the W_pcie_amort floor used by the
# adaptive aggregation runtime.
#
# The .cu binary itself is the one vendored under
# results/RX7900XT_PCIe_20260517_195247/ and copied here unchanged; this
# wrapper just loops it across a power-of-two size sweep.
#
# Environment variables (override on the command line):
#   SIF        Singularity image. Default: arcto_gfx1100_v3.sif in /ssd/cakunas.
#   SRC        path to pcie_bw.cu. Default: alongside this script.
#   BIN        path for the built binary. Default: alongside this script.
#   OUT        path for the CSV. Default: pcie_sweep_<host>_<ts>.csv in cwd.
#   SIZES_MB   space-separated list of sweep points in MiB.
#              Default: "1 2 4 8 16 24 32 48 64 96 128 192 256 384 512 1024"
#
# Usage examples:
#   ./run_pcie_sweep.sh                  # defaults
#   SIF=/path/to/arcto_gfx90a.sif ./run_pcie_sweep.sh
#   SIZES_MB="4 8 16 32 64 128" ./run_pcie_sweep.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF="${SIF:-/ssd/cakunas/arcto_gfx1100_v3.sif}"
SRC="${SRC:-$SCRIPT_DIR/pcie_bw.cu}"
BIN="${BIN:-$SCRIPT_DIR/pcie_bw}"
HOST=$(hostname -s)
TS=$(date +%Y%m%d_%H%M%S)
OUT="${OUT:-$SCRIPT_DIR/pcie_sweep_${HOST}_${TS}.csv}"

SIZES_MB="${SIZES_MB:-1 2 4 8 16 24 32 48 64 96 128 192 256 384 512 1024}"

# Build if missing or stale
if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
  echo "[build] hipcc -O2 -o $BIN $SRC"
  SINGULARITY_BINDPATH=/ssd/cakunas singularity exec --rocm "$SIF" \
    hipcc -O2 -o "$BIN" "$SRC"
fi

# CSV header
echo "host,timestamp,size_mb,size_bytes,h2d_pageable_gbps,h2d_pinned_gbps,d2h_pageable_gbps,d2h_pinned_gbps" > "$OUT"

# Provenance: record device info once at the top of the run
echo "# host=$HOST ts=$TS" >&2
SINGULARITY_BINDPATH=/ssd/cakunas singularity exec --rocm "$SIF" rocminfo 2>/dev/null \
  | awk '/^Agent/{found=0} /Marketing Name:/&&!found{print "# gpu:"$0; found=1} /Compute Unit:/&&!cu{print "# cus:"$0; cu=1} /Max Waves Per CU/&&!mw{print "# waves:"$0; mw=1}' >&2

for mb in $SIZES_MB; do
  bytes=$((mb * 1024 * 1024))
  printf "[%5d MiB] " "$mb" >&2
  raw=$(SINGULARITY_BINDPATH=/ssd/cakunas singularity exec --rocm "$SIF" "$BIN" "$bytes")
  # Each line ends with "<value> GB/s"; pick the second-to-last whitespace
  # field to be robust to extra tokens like "(Default)".
  h2d_pa=$(echo "$raw" | awk '/H2D pageable/ {print $(NF-1)}')
  h2d_pi=$(echo "$raw" | awk '/H2D pinned/   {print $(NF-1)}')
  d2h_pa=$(echo "$raw" | awk '/D2H pageable/ {print $(NF-1)}')
  d2h_pi=$(echo "$raw" | awk '/D2H pinned/   {print $(NF-1)}')
  echo "$HOST,$TS,$mb,$bytes,$h2d_pa,$h2d_pi,$d2h_pa,$d2h_pi" >> "$OUT"
  printf "H2D pa=%6s pi=%6s | D2H pa=%6s pi=%6s\n" "$h2d_pa" "$h2d_pi" "$d2h_pa" "$d2h_pi" >&2
done

echo "" >&2
echo "Output: $OUT" >&2
