#!/bin/bash
# Regenerate the canonical synthetic dataset suite for the SBAC-PAD'26 paper.
#
# Three synthetic data types complement the TTI seismic workload, mirroring
# the four-dataset taxonomy of the ICCSA characterization
# (zeros / random / binary / TTI). Used to characterize the byte-level
# compressors across the full compressibility spectrum:
#
#   zeros   -- all-zero bytes; maximum compressibility (LZ4 ~ 245x)
#   random  -- uniform bytes from /dev/urandom; incompressible (ratio ~ 1.00)
#   binary  -- 70% repeating pattern + 30% random; moderate (LZ4 ~ 3x)
#
# Six sizes per type:
#   10 MB, 100 MB, 1 GB, 4 GB, 8 GB, 16 GB
#
# Usage:
#   ./regen_synthetic_canonical.sh [OUT_DIR]
#
# Default OUT_DIR = /ssd/cakunas/testdata/canonical
#
# On Grid'5000 vianden-1:
#   OUT_DIR=/home/ckunas/testdata/canonical ./regen_synthetic_canonical.sh
#
# Run time estimate (per host):
#   zeros   16 GB  ~ 1 min (sequential fill)
#   random  16 GB  ~ 60-90 s on modern AES-NI; /dev/urandom-bound
#   binary  16 GB  ~ 2-3 min (Python io + os.urandom mix)
# Total over 6 sizes per type: under 15 minutes for all 18 files.

set -e

OUT_DIR="${1:-${OUT_DIR:-/ssd/cakunas/testdata/canonical}}"
mkdir -p "$OUT_DIR"

declare -A SIZES=(
  [10mb]=10485760
  [100mb]=104857600
  [1gb]=1073741824
  [4gb]=4294967296
  [8gb]=8589934592
  [16gb]=17179869184
)

echo "out dir : $OUT_DIR"
echo ""

# -----------------------------------------------------------------------
# zeros : all-zero file, fastest
# -----------------------------------------------------------------------
echo "=== zeros (all-zero bytes) ==="
for size_name in 10mb 100mb 1gb 4gb 8gb 16gb; do
  bytes=${SIZES[$size_name]}
  out="$OUT_DIR/zeros_${size_name}.bin"
  if [ -f "$out" ] && [ "$(stat -c %s "$out")" = "$bytes" ]; then
    echo "  $out  ($bytes bytes)  -- exists, skipping"
    continue
  fi
  printf "  generating %s ($bytes bytes)..." "$out"
  # head -c is exact for any byte count, unlike dd which rounds to bs.
  head -c "$bytes" /dev/zero > "$out"
  actual=$(stat -c %s "$out")
  if [ "$actual" = "$bytes" ]; then
    echo "  done"
  else
    echo "  FAIL (got $actual, expected $bytes)" >&2
    exit 1
  fi
done
echo ""

# -----------------------------------------------------------------------
# random : uniform bytes from /dev/urandom; incompressible
# -----------------------------------------------------------------------
echo "=== random (uniform bytes from /dev/urandom) ==="
for size_name in 10mb 100mb 1gb 4gb 8gb 16gb; do
  bytes=${SIZES[$size_name]}
  out="$OUT_DIR/random_${size_name}.bin"
  if [ -f "$out" ] && [ "$(stat -c %s "$out")" = "$bytes" ]; then
    echo "  $out  ($bytes bytes)  -- exists, skipping"
    continue
  fi
  printf "  generating %s ($bytes bytes)..." "$out"
  head -c "$bytes" /dev/urandom > "$out"
  actual=$(stat -c %s "$out")
  if [ "$actual" = "$bytes" ]; then
    echo "  done"
  else
    echo "  FAIL (got $actual, expected $bytes)" >&2
    exit 1
  fi
done
echo ""

# -----------------------------------------------------------------------
# binary : 70% repeating pattern + 30% random; moderate compressibility
# -----------------------------------------------------------------------
echo "=== binary (70% repeating pattern + 30% random) ==="
for size_name in 10mb 100mb 1gb 4gb 8gb 16gb; do
  bytes=${SIZES[$size_name]}
  out="$OUT_DIR/binary_${size_name}.bin"
  if [ -f "$out" ] && [ "$(stat -c %s "$out")" = "$bytes" ]; then
    echo "  $out  ($bytes bytes)  -- exists, skipping"
    continue
  fi
  printf "  generating %s ($bytes bytes)..." "$out"
  python3 - "$bytes" "$out" <<'PY'
import os, sys
size_bytes = int(sys.argv[1])
out_path = sys.argv[2]

# 8 KB pattern that is purely repeating (matches will be found by LZ4)
pattern = bytes(range(256)) * 32  # 8 KB

CHUNK_PATTERN_BYTES = int(8 * 1024 * 0.7)   # 5734 bytes pattern per 8 KB chunk
CHUNK_RANDOM_BYTES  = 8 * 1024 - CHUNK_PATTERN_BYTES  # 2458 bytes random

with open(out_path, 'wb') as f:
    written = 0
    while written < size_bytes:
        # pattern slice
        n_p = min(CHUNK_PATTERN_BYTES, size_bytes - written)
        f.write(pattern[:n_p])
        written += n_p
        if written >= size_bytes:
            break
        # random slice
        n_r = min(CHUNK_RANDOM_BYTES, size_bytes - written)
        f.write(os.urandom(n_r))
        written += n_r
PY
  actual=$(stat -c %s "$out")
  if [ "$actual" = "$bytes" ]; then
    echo "  done"
  else
    echo "  FAIL (got $actual, expected $bytes)" >&2
    exit 1
  fi
done
echo ""

echo "All synthetic datasets generated:"
ls -la "$OUT_DIR"/zeros_*.bin "$OUT_DIR"/random_*.bin "$OUT_DIR"/binary_*.bin 2>/dev/null
echo ""
echo "Verify with:"
echo "  ls -la $OUT_DIR/*.bin"
echo "  md5sum $OUT_DIR/zeros_*.bin   # all 16 GB of zeros has known md5"
