#!/bin/bash
# Build attempt A1 (no clear loop, commit b9671c5) at two table sizes.
set -u
export ROCM_PATH=/opt/rocm HIP_PATH=/opt/rocm PATH=/opt/rocm/bin:$PATH
cd /ssd/cakunas/campaign-htocc/arcto-a1 || exit 1
for HT in 16384 128; do
  B=build_ht$HT
  [ -x "$B/bin/benchmark_lz4_chunked" ] && { echo "SKIP $B"; continue; }
  cmake -S . -B "$B" \
    -D CMAKE_PREFIX_PATH=/opt/rocm \
    -D CMAKE_HIP_ARCHITECTURES=gfx1100 \
    -D USE_WARPSIZE_32=ON \
    -D CMAKE_BUILD_TYPE=Release \
    -D BUILD_BENCHMARKS=ON -D BUILD_TESTS=OFF \
    -D CMAKE_HIP_FLAGS="-DARCTO_LZ4_MAX_HASH_TABLE_SIZE=$HT" \
    -D CMAKE_CXX_FLAGS="-DARCTO_LZ4_MAX_HASH_TABLE_SIZE=$HT" \
    > "$B.configure.log" 2>&1 || { echo "CONFIGURE FAIL $HT"; tail -5 "$B.configure.log"; exit 1; }
  cmake --build "$B" -j 16 --target benchmark_lz4_chunked \
    > "$B.build.log" 2>&1 || { echo "BUILD FAIL $HT"; tail -5 "$B.build.log"; exit 1; }
  echo "$HT" > "$B/HT_SIZE"
  echo "commit=b9671c5 attempt=A1" > "$B/ATTEMPT"
  echo "OK $B"
done
echo "===== A1 BUILDS DONE ====="
