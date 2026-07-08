# Hipify Comparison Report

Comparison of three conversion approaches for nvcomp 2.2 → HIP:

1. **hipify-perl (automatic)**: Raw `hipify-perl` output from nvcomp 2.2 CUDA source
2. **hipCOMP-core (AMD)**: AMD's official manual port
3. **hip-compression-toolkit (our port)**: Our manual port with optimizations

## File-level comparison

| File (nvcomp) | hipify-perl | hipCOMP-core (AMD) | hip-compression-toolkit |
|---|---|---|---|
| src/BitPackGPU | BitPackGPU.hip | BitPackGPU.cu | BitPackGPU.hip |
| src/DeltaGPU | DeltaGPU.hip | DeltaGPU.h | DeltaGPU.hip |
| src/RunLengthEncodeGPU | RunLengthEncodeGPU.h | RunLengthEncodeGPU.h | RunLengthEncodeGPU.h |
| src/CudaUtils | CudaUtils.h | -- | HipUtils.hip |
| src/LZ4Kernels | LZ4Kernels.hiph | LZ4Kernels.cuh | LZ4Kernels.hiph |
| src/CascadedKernels | CascadedKernels.hiph | CascadedKernels.cuh | CascadedKernels.hiph |
| src/SnappyKernels | SnappyKernels.hiph | -- | -- |
| src/SnappyBlockUtils | SnappyBlockUtils.hiph | -- | -- |
| src/Check | Check.cpp | Check.cpp | Check.cpp |
| src/nvcomp_api | nvcomp_api.cpp | -- | hipcomp_api.cpp |
| src/TempSpaceBroker | TempSpaceBroker.h | TempSpaceBroker.h | TempSpaceBroker.h |

## Detailed diff statistics

| File | hipify→AMD (lines changed) | hipify→ours (lines changed) | AMD→ours (lines changed) |
|---|---|---|---|
| BitPackGPU | 545 | 224 | 606 |
| DeltaGPU | 197 | 93 | 194 |
| RunLengthEncodeGPU | 112 | 99 | 109 |
| CudaUtils | -- | 239 | -- |
| LZ4Kernels | 1201 | 416 | 1186 |
| CascadedKernels | 1174 | 156 | 1121 |
| SnappyKernels | -- | -- | -- |
| SnappyBlockUtils | -- | -- | -- |
| Check | 100 | 77 | 92 |
| nvcomp_api | -- | 49 | -- |
| TempSpaceBroker | 93 | 48 | 91 |

## Key manual changes beyond hipify-perl

These are changes that `hipify-perl` **cannot** do automatically and require manual intervention:

### 1. Wave size (warp size) adaptation
- **CUDA**: Fixed `warpSize = 32`
- **HIP CDNA (MI300X, MI250)**: `warpSize = 64` (wave64)
- **HIP RDNA3 (RX 7900 XT)**: `warpSize = 32` (wave32)
- hipify-perl does NOT handle this — it just translates API calls

### 2. Cooperative groups
- CUDA `cooperative_groups` → HIP has partial support
- AMD's hipCOMP-core uses `CG_WORKAROUND` macro
- Our port adds conditional compilation for wave32/wave64

### 3. CUB → hipCUB
- hipify-perl converts `cub::` → `hipcub::` (mostly works)
- But template specializations and device-level APIs need manual fixes

### 4. Shared memory alignment
- CDNA and RDNA have different shared memory bank configurations
- hipify-perl doesn't adjust shared memory patterns

### 5. Header/namespace renaming
- `nvcomp` → `hipcomp` (namespace, headers, API symbols)
- hipify-perl does NOT rename project-specific symbols, only CUDA runtime APIs

### 6. CMakeLists.txt
- Complete rewrite needed: CUDA language → HIP language
- Different find_package() calls (CUDAToolkit → hip, cub → hipcub)
- hipify-perl does NOT touch CMake files
