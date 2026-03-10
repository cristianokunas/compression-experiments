#!/bin/bash
# Compare benchmark results across features/commits
# Usage: ./scripts/compare_results.sh [baseline_dir] [optimized_dir]

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

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_improvement() {
    local pct=$1
    if (( $(echo "$pct > 0" | bc -l) )); then
        echo -e "${GREEN}+${pct}%${NC}"
    elif (( $(echo "$pct < 0" | bc -l) )); then
        echo -e "${RED}${pct}%${NC}"
    else
        echo -e "${YELLOW}${pct}%${NC}"
    fi
}

# Results directory
RESULTS_DIR="$PROJECT_ROOT/results"

# If arguments provided, use them
if [ $# -eq 2 ]; then
    BASELINE_DIR="$1"
    OPTIMIZED_DIR="$2"
elif [ $# -eq 0 ]; then
    # Auto-detect: find two most recent experiments
    print_info "Auto-detecting experiments to compare..."

    mapfile -t EXPERIMENTS < <(find "$RESULTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | head -2)

    if [ ${#EXPERIMENTS[@]} -lt 2 ]; then
        print_warn "Not enough experiments found. Need at least 2."
        echo ""
        echo "Usage: $0 [baseline_dir] [optimized_dir]"
        echo ""
        echo "Available experiments:"
        ls -1dt "$RESULTS_DIR"/*/ 2>/dev/null | head -10 || echo "  None found"
        exit 1
    fi

    OPTIMIZED_DIR="${EXPERIMENTS[0]}"
    BASELINE_DIR="${EXPERIMENTS[1]}"

    print_info "Baseline:  $(basename $BASELINE_DIR)"
    print_info "Optimized: $(basename $OPTIMIZED_DIR)"
    echo ""
else
    echo "Usage: $0 [baseline_dir] [optimized_dir]"
    echo "   or: $0  (auto-detect latest two experiments)"
    exit 1
fi

# Validate directories
if [ ! -f "$BASELINE_DIR/results.csv" ]; then
    print_warn "Baseline results not found: $BASELINE_DIR/results.csv"
    exit 1
fi

if [ ! -f "$OPTIMIZED_DIR/results.csv" ]; then
    print_warn "Optimized results not found: $OPTIMIZED_DIR/results.csv"
    exit 1
fi

# Create comparison output
COMPARISON_DIR="$RESULTS_DIR/comparison_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$COMPARISON_DIR"

# Show metadata
print_header "Experiment Metadata"

echo -e "${CYAN}BASELINE:${NC}"
if [ -f "$BASELINE_DIR/metadata.json" ]; then
    cat "$BASELINE_DIR/metadata.json" | head -5 | sed 's/^/  /'
fi
echo ""

echo -e "${CYAN}OPTIMIZED:${NC}"
if [ -f "$OPTIMIZED_DIR/metadata.json" ]; then
    cat "$OPTIMIZED_DIR/metadata.json" | head -5 | sed 's/^/  /'
fi
echo ""

# Python script for detailed comparison
cat > "$COMPARISON_DIR/compare.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import csv
import sys
from collections import defaultdict

def load_results(csv_file):
    """Load results from CSV into a dictionary"""
    results = {}
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row['Algorithm'], row['TestFile'])
            results[key] = {
                'comp_throughput': float(row['CompressionThroughput_GBps']) if row['CompressionThroughput_GBps'] not in ['N/A', 'ERROR'] else None,
                'decomp_throughput': float(row['DecompressionThroughput_GBps']) if row['DecompressionThroughput_GBps'] not in ['N/A', 'ERROR'] else None,
                'ratio': float(row['CompressionRatio']) if row['CompressionRatio'] not in ['N/A', 'ERROR'] else None
            }
    return results

def compare_results(baseline, optimized):
    """Compare two result sets"""
    comparisons = []

    for key in sorted(baseline.keys()):
        if key not in optimized:
            continue

        algo, testfile = key
        base = baseline[key]
        opt = optimized[key]

        comp = {
            'algorithm': algo,
            'testfile': testfile,
        }

        # Compression throughput improvement
        if base['comp_throughput'] and opt['comp_throughput']:
            improvement = ((opt['comp_throughput'] - base['comp_throughput']) / base['comp_throughput']) * 100
            comp['comp_improvement'] = improvement
            comp['comp_base'] = base['comp_throughput']
            comp['comp_opt'] = opt['comp_throughput']
        else:
            comp['comp_improvement'] = None

        # Decompression throughput improvement
        if base['decomp_throughput'] and opt['decomp_throughput']:
            improvement = ((opt['decomp_throughput'] - base['decomp_throughput']) / base['decomp_throughput']) * 100
            comp['decomp_improvement'] = improvement
            comp['decomp_base'] = base['decomp_throughput']
            comp['decomp_opt'] = opt['decomp_throughput']
        else:
            comp['decomp_improvement'] = None

        comparisons.append(comp)

    return comparisons

def print_comparison_table(comparisons):
    """Print formatted comparison table"""
    print(f"{'Algorithm':<12} {'Test File':<30} {'Comp (GB/s)':<25} {'Decomp (GB/s)':<25}")
    print(f"{'':12} {'':30} {'Base':>8} {'Opt':>8} {'Δ%':>7} {'Base':>8} {'Opt':>8} {'Δ%':>7}")
    print("-" * 110)

    for comp in comparisons:
        algo = comp['algorithm']
        testfile = comp['testfile'][:28]

        # Compression
        if comp['comp_improvement'] is not None:
            comp_base = f"{comp['comp_base']:7.2f}"
            comp_opt = f"{comp['comp_opt']:7.2f}"
            comp_delta = f"{comp['comp_improvement']:+6.1f}"
        else:
            comp_base = "N/A"
            comp_opt = "N/A"
            comp_delta = "N/A"

        # Decompression
        if comp['decomp_improvement'] is not None:
            decomp_base = f"{comp['decomp_base']:7.2f}"
            decomp_opt = f"{comp['decomp_opt']:7.2f}"
            decomp_delta = f"{comp['decomp_improvement']:+6.1f}"
        else:
            decomp_base = "N/A"
            decomp_opt = "N/A"
            decomp_delta = "N/A"

        print(f"{algo:<12} {testfile:<30} {comp_base:>8} {comp_opt:>8} {comp_delta:>7} {decomp_base:>8} {decomp_opt:>8} {decomp_delta:>7}")

def generate_summary(comparisons):
    """Generate summary statistics"""
    comp_improvements = [c['comp_improvement'] for c in comparisons if c['comp_improvement'] is not None]
    decomp_improvements = [c['decomp_improvement'] for c in comparisons if c['decomp_improvement'] is not None]

    print("\n=== Summary Statistics ===\n")

    if comp_improvements:
        print(f"Compression Throughput:")
        print(f"  Average improvement: {sum(comp_improvements)/len(comp_improvements):+.2f}%")
        print(f"  Best improvement:    {max(comp_improvements):+.2f}%")
        print(f"  Worst improvement:   {min(comp_improvements):+.2f}%")
        print()

    if decomp_improvements:
        print(f"Decompression Throughput:")
        print(f"  Average improvement: {sum(decomp_improvements)/len(decomp_improvements):+.2f}%")
        print(f"  Best improvement:    {max(decomp_improvements):+.2f}%")
        print(f"  Worst improvement:   {min(decomp_improvements):+.2f}%")
        print()

    # Per-algorithm summary
    algo_stats = defaultdict(lambda: {'comp': [], 'decomp': []})
    for comp in comparisons:
        algo = comp['algorithm']
        if comp['comp_improvement'] is not None:
            algo_stats[algo]['comp'].append(comp['comp_improvement'])
        if comp['decomp_improvement'] is not None:
            algo_stats[algo]['decomp'].append(comp['decomp_improvement'])

    print("Per-Algorithm Average Improvement:")
    print(f"{'Algorithm':<15} {'Compression':>15} {'Decompression':>15}")
    print("-" * 45)
    for algo in sorted(algo_stats.keys()):
        comp_avg = sum(algo_stats[algo]['comp']) / len(algo_stats[algo]['comp']) if algo_stats[algo]['comp'] else 0
        decomp_avg = sum(algo_stats[algo]['decomp']) / len(algo_stats[algo]['decomp']) if algo_stats[algo]['decomp'] else 0
        print(f"{algo:<15} {comp_avg:+14.2f}% {decomp_avg:+14.2f}%")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: compare.py baseline.csv optimized.csv")
        sys.exit(1)

    baseline_file = sys.argv[1]
    optimized_file = sys.argv[2]

    baseline = load_results(baseline_file)
    optimized = load_results(optimized_file)

    comparisons = compare_results(baseline, optimized)

    print("\n=== Detailed Comparison ===\n")
    print_comparison_table(comparisons)

    generate_summary(comparisons)
PYTHON_EOF

chmod +x "$COMPARISON_DIR/compare.py"

# Run comparison
print_header "Performance Comparison"
if command -v python3 &> /dev/null; then
    python3 "$COMPARISON_DIR/compare.py" "$BASELINE_DIR/results.csv" "$OPTIMIZED_DIR/results.csv" | tee "$COMPARISON_DIR/comparison_report.txt"
else
    print_warn "Python3 not available, showing basic comparison"

    # Simple bash-based comparison
    echo "Algorithm,TestFile,Baseline_Comp,Optimized_Comp,Improvement%" > "$COMPARISON_DIR/simple_comparison.csv"

    # This is a very basic comparison - the Python version above is much better
    print_info "Install Python3 for detailed analysis"
fi

print_header "Comparison Complete"
print_info "Results saved to: $COMPARISON_DIR"
