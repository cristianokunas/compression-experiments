#!/bin/bash
# =============================================================================
# Generate test data for hipCOMP compression benchmarks
#
# Creates synthetic data (zeros, random, binary) and extracts TTI simulation
# data from RSF files. All files follow naming convention:
#   <size>_<datatype>_<sizeMB>.bin
#
# Usage:
#   ./scripts/generate_testdata.sh [OPTIONS]
#
# Examples:
#   # Synthetic only (no RSF needed)
#   ./scripts/generate_testdata.sh -o testdata
#
#   # Synthetic + TTI from RSF
#   ./scripts/generate_testdata.sh -o testdata -r /path/to/fletcher-io/original/run
#
#   # Skip xlarge (4GB) files
#   ./scripts/generate_testdata.sh -o testdata --no-xlarge
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -------------------- Defaults --------------------
OUTPUT_DIR="${PROJECT_ROOT}/testdata"
RSF_DIR=""
RSF_START_FRACTION=0.5
GENERATE_XLARGE=true

# -------------------- Help --------------------
show_help() {
    cat << 'EOF'
Generate test data for hipCOMP compression benchmarks.

Usage: generate_testdata.sh [OPTIONS]

OPTIONS:
    -o, --output DIR     Output directory (default: testdata/)
    -r, --rsf-dir DIR    RSF source directory for TTI data extraction
                         (e.g., /path/to/fletcher-io/original/run)
    -s, --start-frac F   RSF extraction start fraction (default: 0.5 = middle)
    --no-xlarge          Skip 4GB (xlarge) file generation
    -h, --help           Show this help

DATA TYPES:
    zeros   - All zeros (best case, maximum compression)
    random  - Pseudo-random data (worst case, incompressible)
    binary  - Mixed patterns + random (70%/30%, realistic synthetic)
    TTI     - Real seismic simulation data from RSF (requires --rsf-dir)

SIZE TIERS:
    small    10 MB
    medium  100 MB
    large  1024 MB (1 GB)
    xlarge 4096 MB (4 GB)

FILE NAMING:
    <size>_<datatype>_<sizeMB>.bin
    Examples: small_zeros_10.bin, large_TTI_1024.bin, xlarge_random_4096.bin
EOF
}

# -------------------- Parse Args --------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)     OUTPUT_DIR="$2"; shift 2 ;;
        -r|--rsf-dir)    RSF_DIR="$2"; shift 2 ;;
        -s|--start-frac) RSF_START_FRACTION="$2"; shift 2 ;;
        --no-xlarge)     GENERATE_XLARGE=false; shift ;;
        -h|--help)       show_help; exit 0 ;;
        *)               print_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# -------------------- Size definitions --------------------
# Ordered: label sizeMB
SIZE_ORDER=(small medium large)
declare -A SIZES
SIZES[small]=10
SIZES[medium]=100
SIZES[large]=1024
if [ "$GENERATE_XLARGE" = true ]; then
    SIZE_ORDER=(small medium large xlarge)
    SIZES[xlarge]=4096
fi

# Synthetic data types
SYNTHETIC_TYPES=(zeros random binary)

# -------------------- Generator Functions --------------------
generate_synthetic() {
    local filepath="$1"
    local size_mb="$2"
    local data_type="$3"
    local filename
    filename=$(basename "$filepath")

    if [ -f "$filepath" ]; then
        print_warn "  $filename already exists, skipping"
        return 0
    fi

    print_step "  Generating $filename (${size_mb} MB, $data_type)..."

    case "$data_type" in
        zeros)
            dd if=/dev/zero of="$filepath" bs=1M count="$size_mb" 2>/dev/null
            ;;
        random)
            dd if=/dev/urandom of="$filepath" bs=1M count="$size_mb" 2>/dev/null
            ;;
        binary)
            # 70% patterned (repeating 0x00..0xFF blocks) + 30% random
            local pattern_mb=$((size_mb * 7 / 10))
            local random_mb=$((size_mb - pattern_mb))
            local tmp_pattern="${filepath}.tmp_pattern"
            local tmp_random="${filepath}.tmp_random"

            python3 -c "
import sys
block = bytes(range(256))
target = ${pattern_mb} * 1024 * 1024
with open('${tmp_pattern}', 'wb') as f:
    written = 0
    while written < target:
        f.write(block)
        written += 256
" 2>/dev/null || dd if=/dev/zero of="$tmp_pattern" bs=1M count="$pattern_mb" 2>/dev/null

            dd if=/dev/urandom of="$tmp_random" bs=1M count="$random_mb" 2>/dev/null
            cat "$tmp_pattern" "$tmp_random" > "$filepath"
            rm -f "$tmp_pattern" "$tmp_random"
            truncate -s "${size_mb}M" "$filepath"
            ;;
        *)
            print_error "  Unknown data type: $data_type"
            return 1
            ;;
    esac

    local actual_size
    actual_size=$(stat -c%s "$filepath" 2>/dev/null || echo "?")
    local actual_mb=$((actual_size / 1048576))
    print_info "  Created $filename (${actual_mb} MB)"
}

generate_tti() {
    local filepath="$1"
    local size_mb="$2"
    local rsf_dir="$3"
    local start_fraction="$4"
    local filename
    filename=$(basename "$filepath")

    if [ -f "$filepath" ]; then
        print_warn "  $filename already exists, skipping"
        return 0
    fi

    local converter="${SCRIPT_DIR}/convert_rsf_to_binary.py"
    if [ ! -f "$converter" ]; then
        print_error "  RSF converter not found: $converter"
        return 1
    fi

    # Always use LARGE RSF source (most representative - fewest zeros)
    local large_dir="${rsf_dir}/large"
    if [ ! -d "$large_dir" ]; then
        print_error "  Large RSF directory not found: $large_dir"
        return 1
    fi

    local rsf_file
    rsf_file=$(find "$large_dir" -maxdepth 1 -name "*.rsf" -not -name "*.rsf@" -type f | head -1)
    if [ -z "$rsf_file" ]; then
        print_error "  No RSF file found in $large_dir"
        return 1
    fi

    local target_bytes=$((size_mb * 1024 * 1024))
    print_step "  Extracting TTI: $(basename "$rsf_file") -> $filename (${size_mb} MB, from middle)"

    python3 "$converter" "$rsf_file" "$filepath" \
        --start-fraction "$start_fraction" \
        --max-bytes "$target_bytes" \
        --no-validate

    if [ -f "$filepath" ]; then
        local actual_size
        actual_size=$(stat -c%s "$filepath" 2>/dev/null || echo "?")
        local actual_mb=$((actual_size / 1048576))
        print_info "  Created $filename (${actual_mb} MB)"
    else
        print_error "  Failed to create $filename"
        return 1
    fi
}

# =====================================================================
# MAIN
# =====================================================================
echo ""
print_info "=== hipCOMP Test Data Generator ==="
print_info "Output: $OUTPUT_DIR"
print_info "Sizes:  ${SIZE_ORDER[*]}"
if [ -n "$RSF_DIR" ]; then
    print_info "RSF:    $RSF_DIR (start_fraction=$RSF_START_FRACTION)"
    print_info "Types:  ${SYNTHETIC_TYPES[*]} TTI"
else
    print_info "Types:  ${SYNTHETIC_TYPES[*]} (no RSF -> no TTI)"
fi
echo ""

created=0
skipped=0

# -------------------- Synthetic Data --------------------
for size_label in "${SIZE_ORDER[@]}"; do
    size_mb=${SIZES[$size_label]}
    print_info "--- ${size_label} (${size_mb} MB) - Synthetic ---"

    for dtype in "${SYNTHETIC_TYPES[@]}"; do
        filename="${size_label}_${dtype}_${size_mb}.bin"
        filepath="${OUTPUT_DIR}/${filename}"

        if [ -f "$filepath" ]; then
            skipped=$((skipped + 1))
        else
            created=$((created + 1))
        fi
        generate_synthetic "$filepath" "$size_mb" "$dtype"
    done
    echo ""
done

# -------------------- TTI Data (from RSF) --------------------
if [ -n "$RSF_DIR" ]; then
    print_info "--- TTI Data (from RSF simulation, extracted from middle) ---"
    echo ""

    for size_label in "${SIZE_ORDER[@]}"; do
        size_mb=${SIZES[$size_label]}
        filename="${size_label}_TTI_${size_mb}.bin"
        filepath="${OUTPUT_DIR}/${filename}"

        if [ -f "$filepath" ]; then
            skipped=$((skipped + 1))
        else
            created=$((created + 1))
        fi
        generate_tti "$filepath" "$size_mb" "$RSF_DIR" "$RSF_START_FRACTION"
    done
    echo ""
else
    print_warn "No --rsf-dir specified, skipping TTI data generation"
    echo ""
fi

# -------------------- Summary --------------------
print_info "=== Test Data Summary ==="
echo ""
printf "  %-35s %10s\n" "File" "Size"
printf "  %-35s %10s\n" "-----------------------------------" "----------"
for f in "$OUTPUT_DIR"/*.bin; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    fsize=$(du -h "$f" | awk '{print $1}')
    printf "  %-35s %10s\n" "$fname" "$fsize"
done
echo ""

total_size=$(du -sh "$OUTPUT_DIR" | awk '{print $1}')
print_info "Total:   $total_size"
print_info "Created: $created | Skipped: $skipped"
print_info "Done!"
