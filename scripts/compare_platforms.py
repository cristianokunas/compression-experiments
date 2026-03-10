#!/usr/bin/env python3
"""
Compare benchmark results between AMD (hipCOMP) and NVIDIA (nvCOMP) platforms.

Usage:
    python3 compare_platforms.py results/*.csv
    python3 compare_platforms.py amd_results.csv nvidia_results.csv
"""

import sys
import csv
import os
from collections import defaultdict

def parse_csv_files(file_paths):
    """Parse CSV files and return structured data."""
    data = []
    
    for filepath in file_paths:
        if not os.path.exists(filepath):
            print(f"Warning: File not found: {filepath}")
            continue
            
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                # Skip header
                if line.startswith('Algorithm'):
                    continue
                    
                parts = line.split(',')
                if len(parts) >= 9:
                    try:
                        entry = {
                            'algorithm': parts[0],
                            'testfile': parts[1],
                            'filesize_bytes': int(parts[2]) if parts[2].isdigit() else 0,
                            'filesize_mb': float(parts[3]) if parts[3].replace('.','').isdigit() else 0,
                            'ratio': float(parts[4]) if parts[4] not in ['ERROR', 'FAILED', 'N/A'] else None,
                            'comp_throughput': float(parts[5]) if parts[5] not in ['ERROR', 'FAILED', 'N/A'] else None,
                            'decomp_throughput': float(parts[6]) if parts[6] not in ['ERROR', 'FAILED', 'N/A'] else None,
                            'platform': parts[7],
                            'gpu': parts[8] if len(parts) > 8 else 'Unknown',
                            'source_file': filepath
                        }
                        data.append(entry)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Could not parse line: {line[:50]}...")
                        
    return data

def group_by_test(data):
    """Group data by algorithm and test file for comparison."""
    grouped = defaultdict(lambda: defaultdict(list))
    
    for entry in data:
        key = (entry['algorithm'], entry['testfile'])
        platform = entry['platform'].lower()
        grouped[key][platform].append(entry)
        
    return grouped

def calculate_stats(entries):
    """Calculate average stats for a list of entries."""
    if not entries:
        return None
        
    valid_entries = [e for e in entries if e['ratio'] is not None]
    if not valid_entries:
        return None
        
    return {
        'ratio': sum(e['ratio'] for e in valid_entries) / len(valid_entries),
        'comp_throughput': sum(e['comp_throughput'] for e in valid_entries if e['comp_throughput']) / len([e for e in valid_entries if e['comp_throughput']]) if any(e['comp_throughput'] for e in valid_entries) else None,
        'decomp_throughput': sum(e['decomp_throughput'] for e in valid_entries if e['decomp_throughput']) / len([e for e in valid_entries if e['decomp_throughput']]) if any(e['decomp_throughput'] for e in valid_entries) else None,
        'gpu': valid_entries[0]['gpu'],
        'filesize_mb': valid_entries[0]['filesize_mb']
    }

def print_comparison_table(grouped):
    """Print comparison table."""
    print("\n" + "=" * 100)
    print("PLATFORM COMPARISON: hipCOMP (AMD) vs nvCOMP (NVIDIA)")
    print("=" * 100)
    
    # Organize by algorithm
    by_algorithm = defaultdict(list)
    for (algo, testfile), platforms in grouped.items():
        by_algorithm[algo].append((testfile, platforms))
    
    for algo in sorted(by_algorithm.keys()):
        print(f"\n{'─' * 100}")
        print(f"Algorithm: {algo.upper()}")
        print(f"{'─' * 100}")
        print(f"{'Test File':<35} {'Size MB':>8} │ {'AMD Ratio':>10} {'AMD Comp':>10} {'AMD Dec':>10} │ {'NV Ratio':>10} {'NV Comp':>10} {'NV Dec':>10} │ {'Speedup':>8}")
        print(f"{'':<35} {'':>8} │ {'':>10} {'GB/s':>10} {'GB/s':>10} │ {'':>10} {'GB/s':>10} {'GB/s':>10} │ {'Comp':>8}")
        print(f"{'─' * 35}─{'─' * 8}─┼{'─' * 10}─{'─' * 10}─{'─' * 10}─┼{'─' * 10}─{'─' * 10}─{'─' * 10}─┼{'─' * 8}")
        
        for testfile, platforms in sorted(by_algorithm[algo]):
            amd_stats = calculate_stats(platforms.get('amd', []))
            nvidia_stats = calculate_stats(platforms.get('nvidia', []))
            
            # Format values
            size_mb = amd_stats['filesize_mb'] if amd_stats else (nvidia_stats['filesize_mb'] if nvidia_stats else 0)
            
            amd_ratio = f"{amd_stats['ratio']:.2f}" if amd_stats and amd_stats['ratio'] else "N/A"
            amd_comp = f"{amd_stats['comp_throughput']:.2f}" if amd_stats and amd_stats['comp_throughput'] else "N/A"
            amd_dec = f"{amd_stats['decomp_throughput']:.2f}" if amd_stats and amd_stats['decomp_throughput'] else "N/A"
            
            nv_ratio = f"{nvidia_stats['ratio']:.2f}" if nvidia_stats and nvidia_stats['ratio'] else "N/A"
            nv_comp = f"{nvidia_stats['comp_throughput']:.2f}" if nvidia_stats and nvidia_stats['comp_throughput'] else "N/A"
            nv_dec = f"{nvidia_stats['decomp_throughput']:.2f}" if nvidia_stats and nvidia_stats['decomp_throughput'] else "N/A"
            
            # Calculate speedup (AMD vs NVIDIA compression throughput)
            speedup = ""
            if amd_stats and nvidia_stats and amd_stats['comp_throughput'] and nvidia_stats['comp_throughput']:
                ratio = amd_stats['comp_throughput'] / nvidia_stats['comp_throughput']
                if ratio > 1:
                    speedup = f"AMD +{(ratio-1)*100:.0f}%"
                else:
                    speedup = f"NV +{(1/ratio-1)*100:.0f}%"
            
            # Truncate filename if too long
            display_file = testfile[:32] + "..." if len(testfile) > 35 else testfile
            
            print(f"{display_file:<35} {size_mb:>8.1f} │ {amd_ratio:>10} {amd_comp:>10} {amd_dec:>10} │ {nv_ratio:>10} {nv_comp:>10} {nv_dec:>10} │ {speedup:>8}")

def print_summary(data):
    """Print overall summary."""
    print("\n" + "=" * 100)
    print("SUMMARY")
    print("=" * 100)
    
    # Group by platform
    by_platform = defaultdict(list)
    for entry in data:
        if entry['comp_throughput'] is not None:
            by_platform[entry['platform'].lower()].append(entry)
    
    for platform, entries in sorted(by_platform.items()):
        gpus = set(e['gpu'] for e in entries)
        algorithms = set(e['algorithm'] for e in entries)
        
        avg_comp = sum(e['comp_throughput'] for e in entries) / len(entries)
        avg_dec = sum(e['decomp_throughput'] for e in entries if e['decomp_throughput']) / len([e for e in entries if e['decomp_throughput']])
        avg_ratio = sum(e['ratio'] for e in entries) / len(entries)
        
        print(f"\n{platform.upper()} Platform:")
        print(f"  GPU(s): {', '.join(gpus)}")
        print(f"  Algorithms tested: {', '.join(sorted(algorithms))}")
        print(f"  Tests run: {len(entries)}")
        print(f"  Average compression throughput: {avg_comp:.2f} GB/s")
        print(f"  Average decompression throughput: {avg_dec:.2f} GB/s")
        print(f"  Average compression ratio: {avg_ratio:.2f}x")

def export_combined_csv(data, output_path):
    """Export combined data to CSV for further analysis."""
    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            'Algorithm', 'TestFile', 'FileSizeBytes', 'FileSizeMB',
            'CompressionRatio', 'CompressionThroughputGBs', 'DecompressionThroughputGBs',
            'Platform', 'GPU'
        ])
        for entry in data:
            writer.writerow([
                entry['algorithm'],
                entry['testfile'],
                entry['filesize_bytes'],
                entry['filesize_mb'],
                entry['ratio'] if entry['ratio'] else 'N/A',
                entry['comp_throughput'] if entry['comp_throughput'] else 'N/A',
                entry['decomp_throughput'] if entry['decomp_throughput'] else 'N/A',
                entry['platform'],
                entry['gpu']
            ])
    print(f"\nCombined CSV exported to: {output_path}")

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nExample:")
        print("  python3 compare_platforms.py results/benchmark_amd_*.csv results/benchmark_nvidia_*.csv")
        sys.exit(1)
    
    # Parse all input files
    file_paths = sys.argv[1:]
    print(f"Parsing {len(file_paths)} file(s)...")
    
    data = parse_csv_files(file_paths)
    
    if not data:
        print("Error: No valid data found in input files")
        sys.exit(1)
    
    print(f"Loaded {len(data)} benchmark results")
    
    # Group and compare
    grouped = group_by_test(data)
    
    # Print comparison table
    print_comparison_table(grouped)
    
    # Print summary
    print_summary(data)
    
    # Export combined CSV
    output_path = "combined_benchmark_results.csv"
    export_combined_csv(data, output_path)
    
    print("\n" + "=" * 100)
    print("DONE")
    print("=" * 100)

if __name__ == "__main__":
    main()
