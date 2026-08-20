#!/bin/bash
# Same protocol as the gfx1100 ladder, on MI210 (gfx90a, wave64, L1=16KB).
set -u
export ROCM_PATH=/opt/rocm PATH=$HOME/.local/bin:/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
export HIP_VISIBLE_DEVICES=0
cd ~/arcto || exit 1

cat > /tmp/hipmin.hip <<'PY'
#include <hip/hip_runtime.h>
#include <cstdio>
__global__ void k(int* p){ p[threadIdx.x] = threadIdx.x * 2; }
int main(){ int n=64,*d=nullptr,h[64]={0};
  if(hipMalloc(&d,n*sizeof(int))!=hipSuccess){printf("hipMalloc FALHOU\n");return 1;}
  hipLaunchKernelGGL(k,dim3(1),dim3(n),0,0,d);
  if(hipDeviceSynchronize()!=hipSuccess){printf("sync FALHOU\n");return 1;}
  hipMemcpy(h,d,n*sizeof(int),hipMemcpyDeviceToHost);
  printf("HIP OK h[10]=%d\n",h[10]); hipFree(d); return 0; }
PY
hipcc --offload-arch=gfx90a /tmp/hipmin.hip -o /tmp/hipmin 2>/dev/null
/tmp/hipmin || { echo "ABORTADO: stack HIP nao esta sa"; exit 1; }

OUT=results_mi210; mkdir -p "$OUT"
{ echo "date=$(date -Is)"; echo "host=$(hostname)"; echo "git=$(git rev-parse HEAD)";
  echo "rocm=$(ls -d /opt/rocm-*)"; echo "gpu=MI210 gfx90a wave64 L1=16KB"; } > "$OUT/provenance.txt"

for F in tti_rsf_64x64x64_t050 tti_rsf_64x64x64_t000 synth_binary_1mb; do
  for C in 65536 8192; do
    for HT in 16384 8192 4096 2048 1024 512 256 128; do
      for R in 1 2 3; do
        ./build_mi210_ht$HT/bin/benchmark_lz4_chunked -f tests/data/$F.bin -p $C \
          -x 64 -w 2 -i 10 -c true -g 0 > "$OUT/${F}_c${C}_ht${HT}_r${R}.csv" 2>/dev/null
        printf "%-24s c=%-6s HT=%-6s r%s rc=%s\n" "$F" "$C" "$HT" "$R" "$?"
      done
    done
  done
done
echo "===== MI210 CONCLUIDA ====="
