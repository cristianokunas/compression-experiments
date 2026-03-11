#!/bin/bash
# =============================================================================
# Run hipCOMP benchmarks inside a Singularity container
#
# Handles bind mounts, GPU access, and forwards options to run_benchmarks_auto.sh
#
# Usage:
#   ./scripts/run_singularity.sh <image.sif> <rsf_dir> [BENCHMARK_OPTIONS...]
#
# Examples:
#   ./scripts/run_singularity.sh hipcomp_gfx942.sif /path/to/fletcher-io/original/run
#   ./scripts/run_singularity.sh hipcomp_gfx942.sif /path/to/rsf -i 20 -p "65536 1048576"
#   ./scripts/run_singularity.sh hipcomp_gfx942.sif /path/to/rsf --dry-run
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Auto-detect singularity or apptainer (apptainer is the upstream successor)
if command -v singularity &>/dev/null; then
    CONTAINER_RUNTIME="singularity"
elif command -v apptainer &>/dev/null; then
    CONTAINER_RUNTIME="apptainer"
else
    echo -e "${RED}[ERROR]${NC} Neither singularity nor apptainer found."
    exit 1
fi

# -------------------- Help --------------------
show_help() {
    cat << 'EOF'
Run hipCOMP benchmarks inside a Singularity container.

Usage: run_singularity.sh <image.sif> [rsf_dir] [BENCHMARK_OPTIONS...]

ARGUMENTS:
    image.sif       Path to the Singularity image (built with build_singularity.sh)
    rsf_dir         (Optional) Path to RSF data directory (e.g., fletcher-io/original/run)
                    Must contain a 'large/' subdirectory with TTI.rsf.
                    If omitted, only synthetic test data is generated (TTI files
                    already present in testdata/ are used as-is).

BENCHMARK OPTIONS (forwarded to run_benchmarks_auto.sh):
    -a, --algorithms ALGOS   Algorithms to test (default: "lz4 snappy cascaded")
    -i, --iterations N       Number of iterations (default: 10)
    -w, --warmup N           Warmup iterations (default: 2)
    -g, --gpu N              GPU device ID (default: 0)
    -p, --chunk-sizes SIZES  Chunk sizes in bytes (default: "65536")
    --dry-run                Show what would run without executing
    --help-benchmark         Show full benchmark options

ENVIRONMENT VARIABLES:
    RESULTS_DIR     Host directory for results (default: ./results)
    EXTRA_BINDS     Additional --bind arguments (space-separated)

EXAMPLES:
    # With RSF — generates/updates TTI data and runs benchmarks
    ./scripts/run_singularity.sh hipcomp_gfx942.sif /data/fletcher-io/original/run

    # Without RSF — uses existing testdata/ (generates missing synthetic files only)
    ./scripts/run_singularity.sh hipcomp_gfx942.sif

    # Multiple chunk sizes, 20 iterations (no RSF needed)
    ./scripts/run_singularity.sh hipcomp_gfx942.sif -i 20 -p "65536 1048576 16777216"

    # Custom results directory
    RESULTS_DIR=/tmp/bench_results ./scripts/run_singularity.sh hipcomp_gfx942.sif /data/rsf

    # Dry run to verify setup
    ./scripts/run_singularity.sh hipcomp_gfx942.sif /data/rsf --dry-run
EOF
}

# -------------------- Parse Required Args --------------------
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

SIF_IMAGE="$1"
shift

if [ "$1" = "--help-benchmark" ]; then
    $CONTAINER_RUNTIME run --rocm "$SIF_IMAGE" --help
    exit 0
fi

# RSF dir is optional — detect it only if the next arg is a directory (not a flag)
RSF_DIR=""
if [ $# -gt 0 ] && [[ "$1" != -* ]] && [ -d "$1" ]; then
    RSF_DIR="$1"
    shift
fi

# Remaining args are forwarded to run_benchmarks_auto.sh
BENCH_ARGS=("$@")

# -------------------- Validate --------------------
if [ ! -f "$SIF_IMAGE" ]; then
    print_error "Singularity image not found: $SIF_IMAGE"
    print_info "Build one with: ./scripts/build_singularity.sh --arch <gpu_arch>"
    exit 1
fi

RSF_DIR_ABS=""
if [ -n "$RSF_DIR" ]; then
    RSF_DIR_ABS="$(cd "$RSF_DIR" && pwd)" || {
        print_error "RSF directory not found: $RSF_DIR"
        exit 1
    }
    if [ ! -d "$RSF_DIR_ABS/large" ]; then
        print_warn "No 'large/' subdirectory in $RSF_DIR_ABS"
        print_warn "The benchmark requires large RSF data for representative test generation"
    fi
fi

# -------------------- Setup Bind Mounts --------------------
RESULTS_DIR="${RESULTS_DIR:-$(pwd)/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR_ABS="$(cd "$RESULTS_DIR" && pwd)"

# Testdata cache — persists between runs to avoid re-generating
TESTDATA_DIR="${TESTDATA_DIR:-$(pwd)/testdata}"
mkdir -p "$TESTDATA_DIR"
TESTDATA_DIR_ABS="$(cd "$TESTDATA_DIR" && pwd)"

BIND_ARGS=(
    "--bind" "$RESULTS_DIR_ABS:/data/results"
    "--bind" "$TESTDATA_DIR_ABS:/data/testdata"
)
if [ -n "$RSF_DIR_ABS" ]; then
    BIND_ARGS+=("--bind" "$RSF_DIR_ABS:/data/rsf:ro")
fi

# Add any extra user-specified binds
if [ -n "$EXTRA_BINDS" ]; then
    for bind in $EXTRA_BINDS; do
        BIND_ARGS+=("--bind" "$bind")
    done
fi

# -------------------- Print Config --------------------
echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}  hipCOMP Singularity Benchmark Runner${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
print_info "Image:     $SIF_IMAGE"
if [ -n "$RSF_DIR_ABS" ]; then
    print_info "RSF data:  $RSF_DIR_ABS -> /data/rsf"
else
    print_info "RSF data:  (none — using existing testdata/)"
fi
print_info "Results:   $RESULTS_DIR_ABS -> /data/results"
print_info "Test data: $TESTDATA_DIR_ABS -> /data/testdata"
if [ ${#BENCH_ARGS[@]} -gt 0 ]; then
    print_info "Extra args: ${BENCH_ARGS[*]}"
fi
echo ""

# -------------------- Run --------------------
print_info "Starting benchmarks..."
echo ""

RSF_ARG=()
[ -n "$RSF_DIR_ABS" ] && RSF_ARG=(-r /data/rsf)

$CONTAINER_RUNTIME run --rocm \
    "${BIND_ARGS[@]}" \
    "$SIF_IMAGE" \
    "${RSF_ARG[@]}" \
    -d /data/testdata \
    -o /data/results \
    "${BENCH_ARGS[@]}"

# -------------------- Done --------------------
echo ""
print_info "Results saved to: $RESULTS_DIR_ABS"
ls -lh "$RESULTS_DIR_ABS"/ 2>/dev/null | tail -5
