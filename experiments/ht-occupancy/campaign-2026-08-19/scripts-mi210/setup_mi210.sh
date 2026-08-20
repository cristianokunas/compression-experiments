#!/bin/bash
# Replicate the gfx1100 hash-table experiment on MI210 (gfx90a, CDNA2, wave64, L1=16KB).
set -u
export ROCM_PATH=/opt/rocm HIP_PATH=/opt/rocm
export PATH=$HOME/.local/bin:/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
cd ~/arcto || exit 1

echo "=== checkout feature/kernel-opt (mesmo commit do lunaris) ==="
git checkout -q feature/kernel-opt 2>&1 | tail -2
git log --oneline -1

echo "=== patch: MAX_HASH_TABLE_SIZE sobrescrevivel ==="
python3 - <<'PY'
import pathlib
p=pathlib.Path("src/LZ4Kernels.hiph"); s=p.read_text()
old="constexpr const position_type MAX_HASH_TABLE_SIZE = 1U << 14;"
new="""#ifndef ARCTO_LZ4_MAX_HASH_TABLE_SIZE
#define ARCTO_LZ4_MAX_HASH_TABLE_SIZE (1U << 14)
#endif
constexpr const position_type MAX_HASH_TABLE_SIZE = ARCTO_LZ4_MAX_HASH_TABLE_SIZE;"""
if old in s:
    p.write_text(s.replace(old,new)); print("patch aplicado")
elif "ARCTO_LZ4_MAX_HASH_TABLE_SIZE" in s:
    print("patch ja presente")
else:
    raise SystemExit("ERRO: constante nao encontrada")
PY

# NOTA: gfx90a e wave64 -- SEM USE_WARPSIZE_32 (ao contrario do gfx1100)
for HT in 16384 8192 4096 2048 1024 512 256 128; do
  B=build_mi210_ht$HT
  cmake -S . -B "$B" \
    -D CMAKE_PREFIX_PATH=/opt/rocm \
    -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -D CMAKE_HIP_ARCHITECTURES=gfx90a \
    -D CMAKE_BUILD_TYPE=Release \
    -D BUILD_BENCHMARKS=ON -D BUILD_TESTS=ON \
    -D CMAKE_HIP_FLAGS="-DARCTO_LZ4_MAX_HASH_TABLE_SIZE=$HT" \
    -D CMAKE_CXX_FLAGS="-DARCTO_LZ4_MAX_HASH_TABLE_SIZE=$HT" \
    > "$B.configure.log" 2>&1 || { echo "CONFIGURE FAILED $HT"; tail -12 "$B.configure.log"; exit 1; }
  cmake --build "$B" -j 32 > "$B.build.log" 2>&1 || { echo "BUILD FAILED $HT"; grep -m5 "error:" "$B.build.log"; exit 1; }
  echo "OK $HT"
done
echo "===== BUILDS MI210 OK ====="
