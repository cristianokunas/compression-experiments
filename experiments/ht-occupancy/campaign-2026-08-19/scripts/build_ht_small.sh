#!/bin/bash
# Build ARCTO (gfx1100, wave32) once per LZ4 hash-table size.
set -u
export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm
export PATH=/opt/rocm/bin:$PATH
cd /ssd/cakunas/arcto || exit 1
for HT in 1024 512 256 128; do
  B=build_ht$HT
  echo "===== configure $B ====="
  cmake -S . -B "$B" \
    -D CMAKE_PREFIX_PATH=/opt/rocm \
    -D CMAKE_HIP_ARCHITECTURES=gfx1100 \
    -D USE_WARPSIZE_32=ON \
    -D CMAKE_BUILD_TYPE=Release \
    -D BUILD_BENCHMARKS=ON \
    -D BUILD_TESTS=ON \
    -D CMAKE_HIP_FLAGS="-DARCTO_LZ4_MAX_HASH_TABLE_SIZE=$HT" \
    -D CMAKE_CXX_FLAGS="-DARCTO_LZ4_MAX_HASH_TABLE_SIZE=$HT" \
    > "$B.configure.log" 2>&1 || { echo "CONFIGURE FAILED $HT"; tail -15 "$B.configure.log"; exit 1; }
  echo "===== build $B ====="
  cmake --build "$B" -j 24 > "$B.build.log" 2>&1 || { echo "BUILD FAILED $HT"; tail -30 "$B.build.log"; exit 1; }
  echo "OK $HT -> $(ls $B/bin/benchmark_lz4_chunked 2>/dev/null || echo 'SEM BINARIO')"
done
echo "===== TODOS OS BUILDS OK ====="
