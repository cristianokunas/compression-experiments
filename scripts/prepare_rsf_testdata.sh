#!/bin/bash
# Prepare RSF test data for hipCOMP benchmarks
# Converts RSF format (header + binary) to simple binary files

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default paths
DEFAULT_RSF_BASE="${PROJECT_ROOT}/../fletcher-io/original/run"
OUTPUT_DIR="${1:-${PROJECT_ROOT}/testdata}"

print_info "=== RSF to Binary Converter for hipCOMP Benchmarks ==="
echo ""

# Check if Python script exists
CONVERTER="${SCRIPT_DIR}/convert_rsf_to_binary.py"
if [ ! -f "$CONVERTER" ]; then
    print_warn "Converter script not found: $CONVERTER"
    exit 1
fi

# Make it executable
chmod +x "$CONVERTER"

# Create output directory structure
mkdir -p "$OUTPUT_DIR"
print_info "Output directory: $OUTPUT_DIR"
echo ""

# Function to convert RSF file
convert_rsf() {
    local rsf_file="$1"
    local output_name="$2"
    local validate="$3"
    
    if [ ! -f "$rsf_file" ]; then
        print_warn "RSF file not found: $rsf_file"
        return 1
    fi
    
    local output_file="${OUTPUT_DIR}/${output_name}"
    
    if [ -f "$output_file" ]; then
        print_warn "$output_name already exists, skipping"
        return 0
    fi
    
    print_step "Converting: $(basename $rsf_file) → $output_name"
    
    if [ "$validate" = "true" ]; then
        python3 "$CONVERTER" "$rsf_file" "$output_file"
    else
        python3 "$CONVERTER" "$rsf_file" "$output_file" --no-validate
    fi
    
    echo ""
}

# Function to create size-limited chunks from RSF
# Extracts from the MIDDLE of simulation (n4/2+) for more representative data
create_chunks_from_rsf() {
    local rsf_file="$1"
    local size_label="$2"
    local target_size_mb="$3"
    local start_fraction="${4:-0.5}"  # Default: start from middle
    
    if [ ! -f "$rsf_file" ]; then
        print_warn "RSF file not found: $rsf_file"
        return 1
    fi
    
    # Get base name without extension
    local basename_rsf=$(basename "$rsf_file" .rsf)
    
    # Output file name indicates extraction region
    local output_name="${size_label}_${basename_rsf}_${target_size_mb}mb_mid.bin"
    local output_file="${OUTPUT_DIR}/${output_name}"
    
    if [ -f "$output_file" ]; then
        print_warn "  $output_name already exists, skipping"
        return 0
    fi
    
    local target_bytes=$((target_size_mb * 1024 * 1024))
    
    print_step "Converting RSF: $(basename $rsf_file) [start_fraction=${start_fraction}]"
    
    python3 "$CONVERTER" "$rsf_file" "$output_file" \
        --start-fraction "$start_fraction" \
        --max-bytes "$target_bytes" \
        --no-validate
    
    if [ ! -f "$output_file" ]; then
        print_warn "Conversion failed for $rsf_file"
        return 1
    fi
    
    local actual_size_mb=$(du -m "$output_file" | cut -f1)
    print_info "  Created: $output_name (${actual_size_mb} MB, from middle of simulation)"
    
    echo ""
}

# Function to process RSF directory with size limits
process_rsf_directory() {
    local size_dir="$1"
    local size_label="$2"
    local target_size_mb="$3"
    local start_fraction="${4:-0.5}"
    
    if [ ! -d "$size_dir" ]; then
        return
    fi
    
    print_info "Processing $size_label directory: $size_dir (target: ${target_size_mb} MB, from middle)"
    
    # Find all .rsf header files (not .rsf@ binary files)
    local rsf_count=0
    while IFS= read -r -d '' rsf_file; do
        # Skip if it's a binary file (.rsf@)
        if [[ "$rsf_file" == *.rsf@ ]]; then
            continue
        fi
        
        # Create size-limited chunk from middle of simulation
        create_chunks_from_rsf "$rsf_file" "$size_label" "$target_size_mb" "$start_fraction"
        
        rsf_count=$((rsf_count + 1))
    done < <(find "$size_dir" -maxdepth 1 -name "*.rsf" -type f -print0)
    
    if [ $rsf_count -eq 0 ]; then
        print_warn "No RSF files found in $size_dir"
    else
        print_info "Processed $rsf_count file(s) from $size_label"
    fi
    
    echo ""
}

# Check for RSF base directory
if [ -d "$DEFAULT_RSF_BASE" ]; then
    print_info "Searching for RSF files in: $DEFAULT_RSF_BASE"
    print_info "ALL test sizes are extracted from the LARGE dataset (most representative data)"
    print_info "  -> Large RSF (448x448x448, n4=201) has the richest wavefield"
    print_info "  -> Extracting from middle of simulation (n4/2+) to avoid zero-dominated regions"
    print_info "  -> Small/medium RSF sources are too sparse (too many zeros)"
    echo ""
    
    # Start fraction 0.5 = from the middle of the simulation
    START_FRAC=0.5
    
    # ALWAYS use LARGE source for all sizes
    # Rationale:
    #   - small RSF (n4=11):  ~83-100% zeros even at last timestep
    #   - medium RSF (n4=101): ~8% zeros at ts=50+ (ok but smaller cube 256^3)
    #   - large RSF (n4=201):  ~8% zeros at ts=100+, larger cube 448^3 = best quality
    
    LARGE_DIR="${DEFAULT_RSF_BASE}/large"
    
    if [ -d "$LARGE_DIR" ]; then
        print_info "*** Using LARGE source (448^3 x 201 timesteps) for ALL sizes ***"
        echo ""
        
        # Small: 10 MB chunk (quick validation)
        process_rsf_directory "$LARGE_DIR" "small" 10 "$START_FRAC"
        
        # Medium: 100 MB (standard benchmarks)
        process_rsf_directory "$LARGE_DIR" "medium" 100 "$START_FRAC"
        
        # Large: 1 GB (stress tests)
        process_rsf_directory "$LARGE_DIR" "large" 1024 "$START_FRAC"
        
        # Extra Large: 4 GB (maximum stress)
        print_info "Creating extra-large dataset from large source"
        while IFS= read -r -d '' rsf_file; do
            if [[ "$rsf_file" != *.rsf@ ]]; then
                create_chunks_from_rsf "$rsf_file" "xlarge" 4096 "$START_FRAC"
            fi
        done < <(find "$LARGE_DIR" -maxdepth 1 -name "*.rsf" -type f -print0)
    else
        print_error "LARGE RSF directory not found: $LARGE_DIR"
        print_info "The large dataset is required for representative test data."
        print_info "Expected: ${LARGE_DIR}/TTI.rsf + TTI.rsf@"
        exit 1
    fi
    echo ""
    
else
    print_warn "Default RSF base directory not found: $DEFAULT_RSF_BASE"
    print_info "Usage: $0 [output_directory]"
    print_info "Or manually convert: python3 $CONVERTER input.rsf output.bin"
fi

# Summary
if [ -d "$OUTPUT_DIR" ] && [ "$(ls -A $OUTPUT_DIR 2>/dev/null)" ]; then
    print_info "=== Generated Binary Files ==="
    ls -lh "$OUTPUT_DIR" | grep -v "^total" | grep "\.bin$" | awk '{printf "  %-40s %10s\n", $9, $5}'
    echo ""
    
    total_size=$(du -sh "$OUTPUT_DIR" | awk '{print $1}')
    print_info "Total size: $total_size"
    print_info "Location: $(realpath $OUTPUT_DIR)"
    
    # Create recommendations file
    cat > "${OUTPUT_DIR}/RSF_README.txt" << 'EOF'
# RSF Test Data for hipCOMP Benchmarks

## Files Generated

Binary files are size-limited chunks extracted from RSF format data:

### Small Files (10 MB)
- Quick validation and sanity checks
- Files: testdata/small_*_10mb.bin
- Perfect for rapid iteration and debugging

### Medium Files (100 MB)
- Standard benchmark workloads
- Files: testdata/medium_*_100mb.bin
- Suitable for most GPUs (>4 GB VRAM)

### Large Files (1 GB)
- Performance benchmarking
- Files: testdata/large_*_1024mb.bin
- Requires ~8-16 GB GPU VRAM

### Extra Large Files (4 GB)
- Maximum stress testing
- Files: testdata/xlarge_*_4096mb.bin
- Requires ~32+ GB GPU VRAM (MI300X, A100)

All files are:
- **Format**: Raw binary (native floating point)
- **Type**: 32-bit float (4 bytes per element)
- **Endianness**: Native system endian
- **Source**: RSF (Madagascar Seismic File Format)
- **Structure**: Contiguous chunks from beginning of original data

## Usage with Benchmarks

### LZ4 Benchmark
```bash
# Small dataset (quick test - 10 MB)
./build/benchmarks/benchmark_lz4_chunked -f testdata/small_TTI_10mb.bin -c true

# Medium dataset (standard benchmark - 100 MB)
./build/benchmarks/benchmark_lz4_chunked -f testdata/medium_TTI_100mb.bin -c true -i 5

# Large dataset (1 GB)
./build/benchmarks/benchmark_lz4_chunked -f testdata/large_TTI_1024mb.bin -c true -i 3
```

### Snappy Benchmark
```bash
./build/benchmarks/benchmark_snappy_chunked -f testdata/medium_TTI_100mb.bin -c true
```

### Cascaded Benchmark
```bash
./build/benchmarks/benchmark_cascaded_chunked -f testdata/medium_TTI_100mb.bin -c true
```

### Batch Testing All Sizes
```bash
# Quick validation on small (10 MB)
for algo in lz4 snappy cascaded; do
    ./build/benchmarks/benchmark_${algo}_chunked \
        -f testdata/small_TTI_10mb.bin \
        -c true -i 10 -w 2
done

# Standard benchmarks on medium (100 MB)
for algo in lz4 snappy cascaded; do
    ./build/benchmarks/benchmark_${algo}_chunked \
        -f testdata/medium_TTI_100mb.bin \
        -c true -i 5 -w 2
done

# Performance testing on large (1 GB)
for algo in lz4 snappy cascaded; do
    ./build/benchmarks/benchmark_${algo}_chunked \
        -f testdata/large_TTI_1024mb.bin \
        -c true -i 3 -w 1
done

# Stress testing on xlarge (4 GB) - if GPU has enough memory
for algo in lz4 snappy; do  # Cascaded may be too slow
    ./build/benchmarks/benchmark_${algo}_chunked \
        -f testdata/xlarge_TTI_4096mb.bin \
        -c true -i 1
done
```

### Using the benchmark.sh Script
```bash
# Run on specific size
./scripts/benchmark.sh lz4 testdata/small_*.bin
./scripts/benchmark.sh lz4 testdata/medium_*.bin
./scripts/benchmark.sh lz4 testdata/large_*.bin
```

## Compression Expectations for Floating Point Data

Seismic/scientific floating point data typically has:
- **LZ4**: ~1.2-2.0x compression (fast, lower ratio)
- **Snappy**: ~1.3-2.2x compression (balanced)
- **Cascaded**: ~2.0-4.0x compression (slower, higher ratio)

Actual results depend on:
- Data patterns and spatial correlation
- Chunk size configuration
- GPU architecture (MI300X, MI50, etc.)

## Benchmark Chunk Size Parameter

The `-p` parameter controls how data is split for compression (not file size):

- **64 KB (65536)**: Default, better for random access
- **1 MB (1048576)**: Balanced performance/compression
- **16 MB (16777216)**: Better compression ratios, higher throughput

Example with custom chunk size:
```bash
./build/benchmarks/benchmark_lz4_chunked \
    -f testdata/small_TTI_100mb.bin \
    -p 1048576  # 1 MB compression chunks
```

## GPU Memory Considerations

| Dataset Size | GPU VRAM Required | Recommended GPUs |
|--------------|-------------------|------------------|
| **Small (10 MB)** | ~1 GB | Any modern GPU |
| **Medium (100 MB)** | ~4 GB | RX 580, GTX 1060+, MI50 |
| **Large (1 GB)** | ~8-12 GB | RTX 3080, RX 7900 XT, MI50 |
| **XLarge (4 GB)** | ~32+ GB | MI300X, A100, H100 |

Memory requirements include:
- Input buffer
- Compressed output buffer (estimate 2x input for safety)
- Temp workspace for compression
- Decompression buffers

**Always start with small dataset to verify functionality before scaling up!**

## Converting Your Own RSF Files

```bash
# Using the Python converter (single file)
python3 scripts/convert_rsf_to_binary.py your_data.rsf output.bin

# Using the batch script (scans small/medium/large directories)
./scripts/prepare_rsf_testdata.sh /path/to/output/dir

# Expected directory structure:
# fletcher-io/original/run/
# ├── small/
# │   └── TTI.rsf + TTI.rsf@
# ├── medium/
# │   └── TTI.rsf + TTI.rsf@
# └── large/
#     └── TTI.rsf + TTI.rsf@
```

## Data Characteristics

TTI (Tilted Transverse Isotropic) seismic data represents:
- 3D velocity model with anisotropy parameters
- Typical scientific computing workload
- Moderate to high spatial correlation (favorable for compression)
- Realistic floating point value distribution
- Common in oil & gas exploration and seismic imaging

## File Naming Convention

Files follow the pattern: `{size_category}_{dataset}_{size_mb}mb.bin`

Examples:
- `small_TTI_10mb.bin` - 10 MB chunk from small source
- `medium_TTI_100mb.bin` - 100 MB chunk from medium source
- `large_TTI_1024mb.bin` - 1 GB chunk from large source
- `xlarge_TTI_4096mb.bin` - 4 GB chunk from large source (stress test)

All chunks are extracted from the beginning of the original RSF data,
maintaining data continuity and spatial correlation properties.

## Recommended Workflow

1. **Start Small**: Test with 10 MB to verify correctness
2. **Scale to Medium**: Run benchmarks with 100 MB for performance data
3. **Go Large**: Use 1 GB for realistic workloads
4. **Stress Test**: Try 4 GB only if you have high-end GPU (MI300X, A100)
EOF
    
    print_info "Documentation created: ${OUTPUT_DIR}/RSF_README.txt"
else
    print_warn "No binary files were generated"
fi

print_info "Done!"
