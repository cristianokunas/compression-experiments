#!/bin/bash
# Build one ARCTO per LZ4 hash-table size, gfx1100 / wave32, bare metal.
set -u
export ROCM_PATH=/opt/rocm HIP_PATH=/opt/rocm PATH=/opt/rocm/bin:$PATH
cd /ssd/cakunas/campaign-htocc/arcto || exit 1
for HT in 128 256 512 1024 2048 4096 8192 16384; do
  B=build_ht$HT
  [ -x "$B/bin/benchmark_lz4_chunked" ] && { echo "SKIP $B (ja construido)"; continue; }
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
  # stamp the table size the binary was actually built with, so the runner
  # derives its tag from the build instead of trusting a typed label
  echo "$HT" > "$B/HT_SIZE"
  echo "OK $B"
done
echo "===== BUILDS CONCLUIDOS ====="
ls -d build_ht*/ | wc -l
