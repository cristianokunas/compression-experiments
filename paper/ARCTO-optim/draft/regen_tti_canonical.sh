#!/bin/bash
# Regenerate the canonical TTI dataset suite for the SBAC-PAD'26 paper.
#
# Six sizes (matching Table II in section 2.4 of the draft):
#   10 MB, 100 MB, 1 GB, 4 GB, 8 GB, 16 GB
#
# Each file is extracted from the MIDDLE of the source TTI.rsf binary
# (offset = 100 timesteps in, to avoid the near-zero values produced
# during simulation initialization that would inflate compression
# ratios). The source RSF describes a 448x448x448 grid with 201 float32
# timesteps:
#
#   per-timestep bytes = 448 * 448 * 448 * 4 = 359,411,712  (~342.75 MB)
#   total bytes        = per-timestep * 201   = 72,237,754,112  (~67.3 GB)
#   start offset (ts=100) = 35,941,171,200    (~33.5 GB)
#
# Usage:
#   ./regen_tti_canonical.sh [SRC] [OUT_DIR]
#
# Defaults:
#   SRC     = /ssd/cakunas/fletcher-io/original/run/large/TTI.rsf@
#   OUT_DIR = /ssd/cakunas/testdata/canonical
#
# To run on Grid'5000 vianden-1:
#   SRC=/path/to/TTI.rsf@ OUT_DIR=/home/ckunas/testdata/canonical \
#     ./regen_tti_canonical.sh
#
# If TTI.rsf@ is not present on the target host, the canonical sizes
# > 4 GB can be produced by re-concatenating an extracted 4 GB middle
# slice (4x for 16 GB, 2x for 8 GB); this preserves the byte
# distribution but is documented as a fallback.

set -e

SRC="${1:-${SRC:-/ssd/cakunas/fletcher-io/original/run/large/TTI.rsf@}}"
OUT_DIR="${2:-${OUT_DIR:-/ssd/cakunas/testdata/canonical}}"

START_OFFSET=$((448 * 448 * 448 * 4 * 100))  # 100 timesteps in

declare -A SIZES=(
  [10mb]=10485760           # 10 * 1024^2
  [100mb]=104857600         # 100 * 1024^2
  [1gb]=1073741824          # 1 * 1024^3
  [4gb]=4294967296          # 4 * 1024^3
  [8gb]=8589934592          # 8 * 1024^3
  [16gb]=17179869184        # 16 * 1024^3
)

if [ ! -f "$SRC" ]; then
  echo "ERROR: source file not found: $SRC" >&2
  echo "       Fallback: use concat_from_4gb.sh on a host that has only the 4 GB middle slice." >&2
  exit 1
fi

src_size=$(stat -c %s "$SRC")
required_end=$((START_OFFSET + 17179869184))  # end of largest (16 GB) extraction
if [ "$src_size" -lt "$required_end" ]; then
  echo "ERROR: source file is $src_size bytes; need at least $required_end bytes" >&2
  echo "       (offset 100 timesteps + 16 GB extraction)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "source     : $SRC"
echo "src size   : $src_size bytes (~$(awk "BEGIN{printf \"%.1f\", $src_size/1073741824}") GB)"
echo "out dir    : $OUT_DIR"
echo "start off  : $START_OFFSET bytes (~$(awk "BEGIN{printf \"%.1f\", $START_OFFSET/1073741824}") GB, timestep 100)"
echo ""

for size_name in 10mb 100mb 1gb 4gb 8gb 16gb; do
  bytes=${SIZES[$size_name]}
  out="$OUT_DIR/tti_${size_name}.bin"
  if [ -f "$out" ] && [ "$(stat -c %s "$out")" = "$bytes" ]; then
    echo "  $out  ($bytes bytes)  -- exists, skipping"
    continue
  fi
  printf "  generating %s  (%s bytes)..." "$out" "$bytes"
  # tail -c +N skips (N-1) bytes from start; bash $((START_OFFSET + 1))
  tail -c "+$((START_OFFSET + 1))" "$SRC" | head -c "$bytes" > "$out"
  actual=$(stat -c %s "$out")
  if [ "$actual" = "$bytes" ]; then
    echo "  done"
  else
    echo "  FAIL (got $actual bytes, expected $bytes)" >&2
    exit 1
  fi
done

echo ""
echo "All datasets regenerated. Verify with:"
echo "  ls -la $OUT_DIR/tti_*.bin"
echo "  md5sum $OUT_DIR/tti_*.bin"
