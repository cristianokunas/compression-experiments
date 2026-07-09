#!/bin/bash
# =============================================================================
# Hipify nvcomp 2.2 → HIP and compare against:
#   1) AMD's official hipCOMP-core (manual port by AMD)
#   2) arcto (our port)
#
# This script:
#   a) Copies nvcomp 2.2 source to a working directory
#   b) Runs hipify-perl on all CUDA files (.cu → .hip, .cuh → .hiph)
#   c) Adapts the CMakeLists.txt for HIP
#   d) Attempts to build
#   e) Generates a diff report comparing the hipified output vs AMD's port
#
# Usage:
#   ./scripts/hipify_nvcomp.sh [--build] [--diff-only]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source directories
NVCOMP_SRC="/ssd/cakunas/devel/nvcomp"
HIPCOMP_AMD="/ssd/cakunas/devel/hipCOMP-core"
ARCTO_OURS="/ssd/cakunas/arcto"

# Output
HIPIFIED_DIR="$PROJECT_ROOT/hipify-output/nvcomp-hipified"
REPORT_DIR="$PROJECT_ROOT/hipify-output/reports"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()  { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}${BOLD}=== $1 ===${NC}"; }

DO_BUILD=false
DIFF_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --build) DO_BUILD=true ;;
        --diff-only) DIFF_ONLY=true ;;
        -h|--help)
            echo "Usage: $0 [--build] [--diff-only]"
            echo "  --build      Attempt to build the hipified code"
            echo "  --diff-only  Only generate comparison reports (skip hipify)"
            exit 0
            ;;
    esac
done

# ============================================================
# Step 1: Hipify nvcomp 2.2 source
# ============================================================
if [ "$DIFF_ONLY" = false ]; then
    print_header "Step 1: Hipify nvcomp 2.2 CUDA → HIP"

    # Verify sources exist
    if [ ! -d "$NVCOMP_SRC/src" ]; then
        print_error "nvcomp source not found at $NVCOMP_SRC"
        exit 1
    fi

    # Clean previous output
    rm -rf "$HIPIFIED_DIR"
    mkdir -p "$HIPIFIED_DIR"

    # Copy full source tree
    print_info "Copying nvcomp source tree..."
    cp -r "$NVCOMP_SRC"/* "$HIPIFIED_DIR"/

    # Run hipify-perl on all .cu and .cuh files
    print_info "Running hipify-perl on CUDA files..."

    CU_COUNT=0
    CUH_COUNT=0
    CHANGES_LOG="$REPORT_DIR/hipify_changes.log"
    mkdir -p "$REPORT_DIR"
    : > "$CHANGES_LOG"

    # Process .cu files → .hip
    while IFS= read -r cufile; do
        relpath="${cufile#$HIPIFIED_DIR/}"
        hipfile="${cufile%.cu}.hip"

        print_info "  hipify: $relpath → ${relpath%.cu}.hip"

        # Run hipify-perl, capture output
        hipify-perl "$cufile" > "$hipfile" 2>> "$CHANGES_LOG"

        # Log what changed
        if ! diff -q "$cufile" "$hipfile" > /dev/null 2>&1; then
            diff -u "$cufile" "$hipfile" >> "$CHANGES_LOG" 2>/dev/null || true
        fi

        # Remove original .cu
        rm -f "$cufile"
        CU_COUNT=$((CU_COUNT + 1))
    done < <(find "$HIPIFIED_DIR/src" -name "*.cu" -type f)

    # Process .cuh files → .hiph (header equivalents)
    while IFS= read -r cuhfile; do
        relpath="${cuhfile#$HIPIFIED_DIR/}"
        hiphfile="${cuhfile%.cuh}.hiph"

        print_info "  hipify: $relpath → ${relpath%.cuh}.hiph"

        hipify-perl "$cuhfile" > "$hiphfile" 2>> "$CHANGES_LOG"
        rm -f "$cuhfile"
        CUH_COUNT=$((CUH_COUNT + 1))
    done < <(find "$HIPIFIED_DIR/src" -name "*.cuh" -type f)

    # Also hipify headers in include/
    while IFS= read -r hfile; do
        relpath="${hfile#$HIPIFIED_DIR/}"
        tmpfile="${hfile}.hipified"
        hipify-perl "$hfile" > "$tmpfile" 2>> "$CHANGES_LOG"
        mv "$tmpfile" "$hfile"
    done < <(find "$HIPIFIED_DIR/include" -name "*.h" -o -name "*.hpp" -type f 2>/dev/null)

    # Also hipify benchmark .cu files
    while IFS= read -r cufile; do
        relpath="${cufile#$HIPIFIED_DIR/}"
        hipfile="${cufile%.cu}.hip"
        print_info "  hipify: $relpath → ${relpath%.cu}.hip"
        hipify-perl "$cufile" > "$hipfile" 2>> "$CHANGES_LOG"
        rm -f "$cufile"
        CU_COUNT=$((CU_COUNT + 1))
    done < <(find "$HIPIFIED_DIR/benchmarks" -name "*.cu" -type f 2>/dev/null)

    # Also hipify test .cu files
    while IFS= read -r cufile; do
        relpath="${cufile#$HIPIFIED_DIR/}"
        hipfile="${cufile%.cu}.hip"
        print_info "  hipify: $relpath → ${relpath%.cu}.hip"
        hipify-perl "$cufile" > "$hipfile" 2>> "$CHANGES_LOG"
        rm -f "$cufile"
        CU_COUNT=$((CU_COUNT + 1))
    done < <(find "$HIPIFIED_DIR/tests" -name "*.cu" -type f 2>/dev/null)

    print_info "Hipified $CU_COUNT .cu files and $CUH_COUNT .cuh files"
fi

# ============================================================
# Step 2: Generate comparison reports
# ============================================================
print_header "Step 2: Comparing hipified output vs AMD's hipCOMP-core"

mkdir -p "$REPORT_DIR"

SUMMARY="$REPORT_DIR/comparison_summary.md"
cat > "$SUMMARY" << 'HEADER'
# Hipify Comparison Report

Comparison of three conversion approaches for nvcomp 2.2 → HIP:

1. **hipify-perl (automatic)**: Raw `hipify-perl` output from nvcomp 2.2 CUDA source
2. **hipCOMP-core (AMD)**: AMD's official manual port
3. **arcto (our port)**: Our manual port with optimizations

## File-level comparison
HEADER

echo "" >> "$SUMMARY"
echo "| File (nvcomp) | hipify-perl | hipCOMP-core (AMD) | hip-compression-toolkit |" >> "$SUMMARY"
echo "|---|---|---|---|" >> "$SUMMARY"

# Compare key source files
NVCOMP_KEY_FILES=(
    "src/BitPackGPU"
    "src/DeltaGPU"
    "src/RunLengthEncodeGPU"
    "src/CudaUtils"
    "src/LZ4Kernels"
    "src/CascadedKernels"
    "src/SnappyKernels"
    "src/SnappyBlockUtils"
    "src/Check"
    "src/nvcomp_api"
    "src/TempSpaceBroker"
)

for base in "${NVCOMP_KEY_FILES[@]}"; do
    fname=$(basename "$base")

    # Find hipified version
    hipified=$(find "$HIPIFIED_DIR" -name "${fname}.*" -path "*/src/*" 2>/dev/null | head -1)
    hipified_status="--"
    if [ -n "$hipified" ]; then
        hipified_status="$(basename "$hipified")"
    fi

    # Find AMD version
    amd_file=$(find "$HIPCOMP_AMD/src" -name "${fname}.*" 2>/dev/null | head -1)
    amd_status="--"
    if [ -n "$amd_file" ]; then
        amd_status="$(basename "$amd_file")"
    fi

    # Find our version
    # Map nvcomp names to our names (CudaUtils → HipUtils, nvcomp_api → arcto_api, etc.)
    our_name="$fname"
    case "$fname" in
        CudaUtils) our_name="HipUtils" ;;
        nvcomp_api) our_name="arcto_api" ;;
        nvcomp_cub) our_name="arcto_hipcub" ;;
    esac
    our_file=$(find "$ARCTO_OURS/src" -name "${our_name}.*" 2>/dev/null | head -1)
    our_status="--"
    if [ -n "$our_file" ]; then
        our_status="$(basename "$our_file")"
    fi

    echo "| $base | $hipified_status | $amd_status | $our_status |" >> "$SUMMARY"
done

# ============================================================
# Step 3: Detailed diffs for key files
# ============================================================
print_header "Step 3: Generating detailed diffs"

DIFF_DIR="$REPORT_DIR/diffs"
mkdir -p "$DIFF_DIR"

echo "" >> "$SUMMARY"
echo "## Detailed diff statistics" >> "$SUMMARY"
echo "" >> "$SUMMARY"
echo "| File | hipify→AMD (lines changed) | hipify→ours (lines changed) | AMD→ours (lines changed) |" >> "$SUMMARY"
echo "|---|---|---|---|" >> "$SUMMARY"

for base in "${NVCOMP_KEY_FILES[@]}"; do
    fname=$(basename "$base")

    # Find all versions
    hipified=$(find "$HIPIFIED_DIR" -name "${fname}.*" -path "*/src/*" 2>/dev/null | head -1)

    amd_file=$(find "$HIPCOMP_AMD/src" -name "${fname}.*" 2>/dev/null | head -1)

    our_name="$fname"
    case "$fname" in
        CudaUtils) our_name="HipUtils" ;;
        nvcomp_api) our_name="arcto_api" ;;
        nvcomp_cub) our_name="arcto_hipcub" ;;
    esac
    our_file=$(find "$ARCTO_OURS/src" -name "${our_name}.*" 2>/dev/null | head -1)

    diff_hipify_amd="--"
    diff_hipify_ours="--"
    diff_amd_ours="--"

    # hipify vs AMD
    if [ -n "$hipified" ] && [ -n "$amd_file" ]; then
        diff_file="$DIFF_DIR/${fname}_hipify_vs_amd.diff"
        diff -u "$hipified" "$amd_file" > "$diff_file" 2>/dev/null || true
        lines=$(wc -l < "$diff_file")
        diff_hipify_amd="$lines"
    fi

    # hipify vs ours
    if [ -n "$hipified" ] && [ -n "$our_file" ]; then
        diff_file="$DIFF_DIR/${fname}_hipify_vs_ours.diff"
        diff -u "$hipified" "$our_file" > "$diff_file" 2>/dev/null || true
        lines=$(wc -l < "$diff_file")
        diff_hipify_ours="$lines"
    fi

    # AMD vs ours
    if [ -n "$amd_file" ] && [ -n "$our_file" ]; then
        diff_file="$DIFF_DIR/${fname}_amd_vs_ours.diff"
        diff -u "$amd_file" "$our_file" > "$diff_file" 2>/dev/null || true
        lines=$(wc -l < "$diff_file")
        diff_amd_ours="$lines"
    fi

    echo "| $fname | $diff_hipify_amd | $diff_hipify_ours | $diff_amd_ours |" >> "$SUMMARY"
done

# ============================================================
# Step 4: Identify manual changes needed beyond hipify
# ============================================================
print_header "Step 4: Analyzing manual changes beyond hipify"

echo "" >> "$SUMMARY"
cat >> "$SUMMARY" << 'MANUAL'
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
MANUAL

# ============================================================
# Step 5 (optional): Attempt build
# ============================================================
if [ "$DO_BUILD" = true ]; then
    print_header "Step 5: Attempting to build hipified code"
    print_warn "The hipified code will likely NOT build without manual fixes"
    print_warn "This is expected — documenting the build errors is the point"

    BUILD_DIR="$HIPIFIED_DIR/build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    BUILD_LOG="$REPORT_DIR/build_attempt.log"

    # Try cmake (will likely fail — CMakeLists still has CUDA language)
    cmake .. \
        -DCMAKE_PREFIX_PATH=/opt/rocm \
        -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
        -DBUILD_BENCHMARKS=ON \
        -DBUILD_TESTS=ON \
        2>&1 | tee "$BUILD_LOG" || true

    # Try make if cmake succeeded
    if [ -f Makefile ]; then
        make -j$(nproc) 2>&1 | tee -a "$BUILD_LOG" || true
    fi

    # Count errors
    ERROR_COUNT=$(grep -c -i "error" "$BUILD_LOG" 2>/dev/null || echo "0")
    WARNING_COUNT=$(grep -c -i "warning" "$BUILD_LOG" 2>/dev/null || echo "0")

    echo "" >> "$SUMMARY"
    echo "## Build attempt results" >> "$SUMMARY"
    echo "" >> "$SUMMARY"
    echo "- **Errors**: $ERROR_COUNT" >> "$SUMMARY"
    echo "- **Warnings**: $WARNING_COUNT" >> "$SUMMARY"
    echo "- **Full log**: \`hipify-output/reports/build_attempt.log\`" >> "$SUMMARY"
fi

# ============================================================
# Final summary
# ============================================================
print_header "Done"
print_info "Reports saved to: $REPORT_DIR/"
print_info "Hipified source in: $HIPIFIED_DIR/"
print_info "Summary: $SUMMARY"
echo ""
print_info "Key files:"
ls -la "$REPORT_DIR/"
echo ""
if [ -d "$DIFF_DIR" ]; then
    print_info "Diff files:"
    ls -la "$DIFF_DIR/"
fi
