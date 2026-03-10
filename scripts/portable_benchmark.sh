#!/bin/bash
# Portable benchmark script for hipCOMP/nvCOMP comparison
# Works on both AMD (HIP) and NVIDIA (CUDA) GPUs
#
# Usage: ./scripts/portable_benchmark.sh [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()  { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Default parameters
TESTDATA_DIR="$PROJECT_ROOT/testdata"
RESULTS_DIR="$PROJECT_ROOT/results"
ALGORITHMS="lz4 snappy cascaded"
ITERATIONS=10
WARMUP=2
GPU_DEVICE=0
OUTPUT_PREFIX="benchmark"

# Detect GPU platform
detect_platform() {
    if command -v rocm-smi &> /dev/null; then
        if rocm-smi --showproductname 2>/dev/null | grep -qi "GPU"; then
            echo "amd"
            return
        fi
    fi
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -qi ""; then
            echo "nvidia"
            return
        fi
    fi
    echo "unknown"
}

# Get GPU name
get_gpu_name() {
    local platform="$1"
    if [ "$platform" = "amd" ]; then
        rocm-smi --showproductname --device $GPU_DEVICE 2>/dev/null | grep "GPU" | awk -F: '{print $2}' | xargs || echo "AMD GPU"
    elif [ "$platform" = "nvidia" ]; then
        nvidia-smi --query-gpu=name --format=csv,noheader -i $GPU_DEVICE 2>/dev/null | xargs || echo "NVIDIA GPU"
    else
        echo "Unknown GPU"
    fi
}

# Parse arguments
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Portable compression benchmark for AMD and NVIDIA GPUs.
Runs LZ4, Snappy, and Cascaded algorithms for comparison.

OPTIONS:
    -d, --testdata DIR      Test data directory (default: testdata)
    -o, --output DIR        Results output directory (default: results)
    -a, --algorithms ALGOS  Space-separated algorithms (default: "lz4 snappy cascaded")
    -i, --iterations N      Number of iterations per test (default: 10)
    -w, --warmup N          Number of warmup iterations (default: 2)
    -g, --gpu N             GPU device ID (default: 0)
    -p, --prefix NAME       Output file prefix (default: benchmark)
    -h, --help              Show this help message

EXAMPLES:
    # Run all portable benchmarks
    $0

    # Run only LZ4 with more iterations
    $0 -a "lz4" -i 20

    # Specify custom test data and output
    $0 -d /path/to/data -o /path/to/results

OUTPUT:
    Results are saved in CSV format for easy comparison between platforms.
    
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--testdata)  TESTDATA_DIR="$2"; shift 2 ;;
        -o|--output)    RESULTS_DIR="$2"; shift 2 ;;
        -a|--algorithms) ALGORITHMS="$2"; shift 2 ;;
        -i|--iterations) ITERATIONS="$2"; shift 2 ;;
        -w|--warmup)    WARMUP="$2"; shift 2 ;;
        -g|--gpu)       GPU_DEVICE="$2"; shift 2 ;;
        -p|--prefix)    OUTPUT_PREFIX="$2"; shift 2 ;;
        -h|--help)      show_help; exit 0 ;;
        *)              print_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# Detect platform
PLATFORM=$(detect_platform)
GPU_NAME=$(get_gpu_name "$PLATFORM")

print_header "Portable Compression Benchmark"
echo ""
print_info "Platform: $PLATFORM"
print_info "GPU: $GPU_NAME"
print_info "Device ID: $GPU_DEVICE"
print_info "Algorithms: $ALGORITHMS"
print_info "Iterations: $ITERATIONS"
print_info "Warmup: $WARMUP"
echo ""

# Validate test data directory
if [ ! -d "$TESTDATA_DIR" ]; then
    print_error "Test data directory not found: $TESTDATA_DIR"
    print_info "Generate test data with: ./scripts/generate_testdata.sh"
    exit 1
fi

# Find build directory and benchmarks
if [ -d "$PROJECT_ROOT/build/bin" ]; then
    BENCHMARK_DIR="$PROJECT_ROOT/build/bin"
elif [ -d "$PROJECT_ROOT/build/benchmarks" ]; then
    BENCHMARK_DIR="$PROJECT_ROOT/build/benchmarks"
else
    print_error "Benchmarks not found. Build with: cmake -DBUILD_BENCHMARKS=ON .. && make"
    exit 1
fi

# Validate benchmarks exist
for algo in $ALGORITHMS; do
    exe="$BENCHMARK_DIR/benchmark_${algo}_chunked"
    if [ ! -f "$exe" ]; then
        print_error "Benchmark not found: $exe"
        print_info "Build with: cmake -DBUILD_BENCHMARKS=ON .. && make"
        exit 1
    fi
done

# Create results directory
mkdir -p "$RESULTS_DIR"

# Generate timestamp and output file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PLATFORM_SAFE=$(echo "$PLATFORM" | tr '[:upper:]' '[:lower:]')
GPU_SAFE=$(echo "$GPU_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')
OUTPUT_CSV="$RESULTS_DIR/${OUTPUT_PREFIX}_${PLATFORM_SAFE}_${GPU_SAFE}_${TIMESTAMP}.csv"

# Write CSV header
cat > "$OUTPUT_CSV" << EOF
# Portable Benchmark Results
# Platform: $PLATFORM
# GPU: $GPU_NAME
# Timestamp: $(date)
# Iterations: $ITERATIONS
# Warmup: $WARMUP
#
Algorithm,TestFile,FileSizeBytes,FileSizeMB,CompressionRatio,CompressionThroughputGBs,DecompressionThroughputGBs,Platform,GPU
EOF

print_header "Running Benchmarks"
echo ""

# Find test files
mapfile -t TEST_FILES < <(find "$TESTDATA_DIR" -name "*.bin" -type f | sort)

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    print_error "No test files (*.bin) found in $TESTDATA_DIR"
    exit 1
fi

print_info "Found ${#TEST_FILES[@]} test file(s)"
echo ""

# Run benchmarks
for algo in $ALGORITHMS; do
    print_header "Algorithm: ${algo^^}"
    
    exe="$BENCHMARK_DIR/benchmark_${algo}_chunked"
    
    for testfile in "${TEST_FILES[@]}"; do
        testfile_name=$(basename "$testfile")
        testfile_size=$(stat -c%s "$testfile" 2>/dev/null || stat -f%z "$testfile" 2>/dev/null || echo "0")
        testfile_mb=$(echo "scale=2; $testfile_size / 1048576" | bc)
        
        print_info "Testing: $testfile_name (${testfile_mb} MB)"
        
        # Run benchmark with CSV output
        temp_output=$(mktemp)
        
        if $exe -f "$testfile" -i $ITERATIONS -w $WARMUP -g $GPU_DEVICE -c true -t false > "$temp_output" 2>&1; then
            # Parse CSV output (skip header line)
            # Format: Files,Duplicate,SizeMB,Pages,AvgPage,MaxPage,Uncompressed,Compressed,Ratio,CompGB,DecompGB
            result_line=$(tail -n 1 "$temp_output" 2>/dev/null)
            
            if [[ -n "$result_line" && "$result_line" != *"Files"* ]]; then
                # Extract fields from CSV
                IFS=',' read -ra fields <<< "$result_line"
                
                comp_ratio="${fields[8]:-N/A}"
                comp_throughput="${fields[9]:-N/A}"
                decomp_throughput="${fields[10]:-N/A}"
                
                # Write to output CSV
                echo "$algo,$testfile_name,$testfile_size,$testfile_mb,$comp_ratio,$comp_throughput,$decomp_throughput,$PLATFORM,$GPU_NAME" >> "$OUTPUT_CSV"
                
                print_info "  Ratio: ${comp_ratio}x, Comp: ${comp_throughput} GB/s, Decomp: ${decomp_throughput} GB/s"
            else
                print_warn "  Could not parse results"
                echo "$algo,$testfile_name,$testfile_size,$testfile_mb,ERROR,ERROR,ERROR,$PLATFORM,$GPU_NAME" >> "$OUTPUT_CSV"
            fi
        else
            print_warn "  Benchmark failed"
            echo "$algo,$testfile_name,$testfile_size,$testfile_mb,FAILED,FAILED,FAILED,$PLATFORM,$GPU_NAME" >> "$OUTPUT_CSV"
        fi
        
        rm -f "$temp_output"
    done
    echo ""
done

print_header "Benchmark Complete"
print_info "Results saved to: $OUTPUT_CSV"
echo ""

# Print summary
print_header "Quick Summary"
if command -v column &> /dev/null; then
    grep -v "^#" "$OUTPUT_CSV" | column -t -s ','
else
    grep -v "^#" "$OUTPUT_CSV"
fi
echo ""

# Print comparison instructions
print_header "Comparison Instructions"
cat << EOF
To compare AMD vs NVIDIA results:

1. Run this script on both platforms with same test data
2. Combine CSV files:
   cat results/*_amd_*.csv results/*_nvidia_*.csv > combined.csv

3. Use the comparison script:
   python3 scripts/compare_platforms.py combined.csv

4. Or analyze in any spreadsheet/data tool
EOF
