#!/usr/bin/env python3
"""
Analyze RSF datasets: per-timestep statistics (zero fraction, value range, std, etc.)
Outputs CSV suitable for publication / LaTeX tables.

Usage:
    python3 scripts/analyze_rsf_data_quality.py [OPTIONS]

    # Analyze all RSF sizes (small, medium, large)
    python3 scripts/analyze_rsf_data_quality.py -b ../fletcher-io/original/run

    # Analyze a single RSF file
    python3 scripts/analyze_rsf_data_quality.py -f ../fletcher-io/original/run/large/TTI.rsf

    # Custom output
    python3 scripts/analyze_rsf_data_quality.py -b ../fletcher-io/original/run -o results/
"""

import argparse
import csv
import json
import math
import os
import struct
import sys
import time

# ---------------------------------------------------------------------------
# RSF helpers (duplicated from convert_rsf_to_binary.py to keep standalone)
# ---------------------------------------------------------------------------

def parse_rsf_header(rsf_file):
    metadata = {}
    with open(rsf_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, value = line.split('=', 1)
                metadata[key.strip()] = value.strip().strip('"')
    return metadata


def get_data_info(metadata):
    info = {
        'data_format': metadata.get('data_format', 'native_float'),
        'esize': int(metadata.get('esize', 4)),
        'dimensions': [],
        'spacing': [],
        'total_elements': 1,
    }
    i = 1
    while f'n{i}' in metadata:
        dim = int(metadata[f'n{i}'])
        info['dimensions'].append(dim)
        info['total_elements'] *= dim
        i += 1
    i = 1
    while f'd{i}' in metadata:
        info['spacing'].append(float(metadata[f'd{i}']))
        i += 1
    return info

# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def analyze_timestep(fp, offset, spatial_elements, esize, fmt_char,
                     max_samples=5000):
    """Sample a single timestep and return statistics dict."""
    step = max(1, spatial_elements // max_samples)
    values = []
    zeros = 0

    for i in range(0, spatial_elements, step):
        fp.seek(offset + i * esize)
        raw = fp.read(esize)
        if len(raw) < esize:
            break
        val = struct.unpack(fmt_char, raw)[0]
        values.append(val)
        if val == 0.0:
            zeros += 1

    n = len(values)
    if n == 0:
        return None

    min_val = min(values)
    max_val = max(values)
    mean_val = sum(values) / n
    variance = sum((x - mean_val) ** 2 for x in values) / n
    std_val = math.sqrt(variance)
    abs_values = [abs(v) for v in values if v != 0.0]
    abs_mean = sum(abs_values) / len(abs_values) if abs_values else 0.0

    return {
        'samples': n,
        'zeros': zeros,
        'zero_fraction': zeros / n,
        'nonzero_count': n - zeros,
        'min': min_val,
        'max': max_val,
        'mean': mean_val,
        'std': std_val,
        'abs_mean_nonzero': abs_mean,
        'dynamic_range_db': 20 * math.log10(max(abs(max_val), abs(min_val)) /
                                              abs_mean) if abs_mean > 0 else 0.0,
    }


def analyze_rsf_file(rsf_path, max_samples_per_ts=5000, verbose=True):
    """Analyze every timestep in an RSF file.
    
    Returns:
        (file_meta, list_of_per_timestep_dicts)
    """
    metadata = parse_rsf_header(rsf_path)
    info = get_data_info(metadata)

    dims = info['dimensions']
    esize = info['esize']
    n_timesteps = dims[-1] if len(dims) > 1 else 1
    spatial_elements = info['total_elements'] // n_timesteps
    spatial_dims = dims[:-1] if len(dims) > 1 else dims
    timestep_bytes = spatial_elements * esize

    # Determine struct format
    fmt_map = {'native_float': 'f', 'native_double': 'd'}
    fmt_char = fmt_map.get(info['data_format'], 'f')

    # Resolve binary path
    binary_file = metadata.get('in', '').strip('"')
    if binary_file.startswith('./'):
        binary_file = binary_file[2:]
    header_dir = os.path.dirname(os.path.abspath(rsf_path))
    binary_path = os.path.join(header_dir, binary_file)

    if not os.path.exists(binary_path):
        raise FileNotFoundError(f"Binary data not found: {binary_path}")

    file_size = os.path.getsize(binary_path)

    file_meta = {
        'rsf_file': rsf_path,
        'binary_file': binary_path,
        'file_size_bytes': file_size,
        'file_size_gb': file_size / (1024**3),
        'data_format': info['data_format'],
        'esize': esize,
        'spatial_dims': 'x'.join(map(str, spatial_dims)),
        'spatial_elements': spatial_elements,
        'n_timesteps': n_timesteps,
        'timestep_bytes': timestep_bytes,
        'timestep_mb': timestep_bytes / (1024**2),
    }

    if verbose:
        print(f"\nAnalyzing: {rsf_path}")
        print(f"  Dims: {' x '.join(map(str, dims))}")
        print(f"  Spatial cube: {file_meta['spatial_dims']} = {spatial_elements:,} elements")
        print(f"  Timesteps: {n_timesteps}")
        print(f"  File size: {file_meta['file_size_gb']:.2f} GB")
        print(f"  Timestep size: {file_meta['timestep_mb']:.1f} MB")
        print()

    rows = []
    with open(binary_path, 'rb') as fp:
        for ts in range(n_timesteps):
            offset = ts * timestep_bytes
            stats = analyze_timestep(fp, offset, spatial_elements, esize,
                                     fmt_char, max_samples_per_ts)
            if stats is None:
                continue
            stats['timestep'] = ts
            rows.append(stats)
            if verbose:
                pct = 100 * stats['zero_fraction']
                print(f"  ts={ts:4d}  zeros={pct:5.1f}%  "
                      f"range=[{stats['min']:+.4e}, {stats['max']:+.4e}]  "
                      f"std={stats['std']:.4e}")

    return file_meta, rows


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

TIMESTEP_CSV_COLUMNS = [
    'dataset', 'spatial_dims', 'n_timesteps',
    'timestep', 'samples', 'zeros', 'nonzero_count', 'zero_fraction',
    'min', 'max', 'mean', 'std', 'abs_mean_nonzero', 'dynamic_range_db',
]

SUMMARY_CSV_COLUMNS = [
    'dataset', 'spatial_dims', 'n_timesteps',
    'file_size_gb', 'timestep_mb', 'data_format',
    'ts_begin_zero_pct', 'ts_mid_zero_pct', 'ts_end_zero_pct',
    'ts_begin_std', 'ts_mid_std', 'ts_end_std',
    'recommended_start_fraction',
]


def dataset_label(rsf_path):
    """Derive a short label from the path (e.g. 'large/TTI')."""
    parent = os.path.basename(os.path.dirname(rsf_path))
    name = os.path.splitext(os.path.basename(rsf_path))[0]
    return f"{parent}/{name}"


def write_timestep_csv(path, file_meta, rows, label):
    """Write per-timestep statistics to CSV."""
    write_header = not os.path.exists(path)
    with open(path, 'a', newline='') as f:
        w = csv.DictWriter(f, fieldnames=TIMESTEP_CSV_COLUMNS)
        if write_header:
            w.writeheader()
        for r in rows:
            row = {
                'dataset': label,
                'spatial_dims': file_meta['spatial_dims'],
                'n_timesteps': file_meta['n_timesteps'],
                'timestep': r['timestep'],
                'samples': r['samples'],
                'zeros': r['zeros'],
                'nonzero_count': r['nonzero_count'],
                'zero_fraction': f"{r['zero_fraction']:.6f}",
                'min': f"{r['min']:.6e}",
                'max': f"{r['max']:.6e}",
                'mean': f"{r['mean']:.6e}",
                'std': f"{r['std']:.6e}",
                'abs_mean_nonzero': f"{r['abs_mean_nonzero']:.6e}",
                'dynamic_range_db': f"{r['dynamic_range_db']:.2f}",
            }
            w.writerow(row)


def write_summary_csv(path, file_meta, rows, label):
    """Write one summary row per RSF file."""
    n = len(rows)
    if n == 0:
        return

    ts_begin = rows[0]
    ts_mid = rows[n // 2]
    ts_end = rows[-1]

    # Determine recommended start fraction (first ts with <10% zeros)
    rec_frac = 0.0
    threshold = 0.10
    for r in rows:
        if r['zero_fraction'] <= threshold:
            rec_frac = r['timestep'] / file_meta['n_timesteps']
            break
    else:
        # If never below threshold, use last timestep
        rec_frac = (rows[-1]['timestep']) / file_meta['n_timesteps']

    write_header = not os.path.exists(path)
    with open(path, 'a', newline='') as f:
        w = csv.DictWriter(f, fieldnames=SUMMARY_CSV_COLUMNS)
        if write_header:
            w.writeheader()
        w.writerow({
            'dataset': label,
            'spatial_dims': file_meta['spatial_dims'],
            'n_timesteps': file_meta['n_timesteps'],
            'file_size_gb': f"{file_meta['file_size_gb']:.2f}",
            'timestep_mb': f"{file_meta['timestep_mb']:.1f}",
            'data_format': file_meta['data_format'],
            'ts_begin_zero_pct': f"{ts_begin['zero_fraction']*100:.1f}",
            'ts_mid_zero_pct': f"{ts_mid['zero_fraction']*100:.1f}",
            'ts_end_zero_pct': f"{ts_end['zero_fraction']*100:.1f}",
            'ts_begin_std': f"{ts_begin['std']:.4e}",
            'ts_mid_std': f"{ts_mid['std']:.4e}",
            'ts_end_std': f"{ts_end['std']:.4e}",
            'recommended_start_fraction': f"{rec_frac:.2f}",
        })


def write_metadata_json(path, all_meta):
    """Write full analysis metadata as JSON."""
    with open(path, 'w') as f:
        json.dump(all_meta, f, indent=2, default=str)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Analyze RSF data quality per timestep. '
                    'Outputs CSV files suitable for publication.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze all RSF sizes
  %(prog)s -b ../fletcher-io/original/run -o results/

  # Single file
  %(prog)s -f ../fletcher-io/original/run/large/TTI.rsf

  # More samples per timestep (slower but more precise)
  %(prog)s -b ../fletcher-io/original/run --samples 20000
""")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-f', '--file', help='Single RSF header file to analyze')
    group.add_argument('-b', '--basedir',
                       help='Base directory containing small/, medium/, large/ subdirs')
    parser.add_argument('-o', '--output', default='.',
                        help='Output directory for CSV files (default: current dir)')
    parser.add_argument('--samples', type=int, default=5000,
                        help='Samples per timestep (default: 5000)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='Suppress per-timestep console output')

    args = parser.parse_args()
    os.makedirs(args.output, exist_ok=True)

    ts_csv = os.path.join(args.output, 'rsf_timestep_analysis.csv')
    summary_csv = os.path.join(args.output, 'rsf_summary_analysis.csv')
    meta_json = os.path.join(args.output, 'rsf_analysis_metadata.json')

    # Remove old files so headers are written fresh
    for p in [ts_csv, summary_csv]:
        if os.path.exists(p):
            os.remove(p)

    rsf_files = []
    if args.file:
        rsf_files.append(args.file)
    else:
        for subdir in ['small', 'medium', 'large']:
            d = os.path.join(args.basedir, subdir)
            if not os.path.isdir(d):
                continue
            for fname in sorted(os.listdir(d)):
                if fname.endswith('.rsf') and not fname.endswith('.rsf@'):
                    rsf_files.append(os.path.join(d, fname))

    if not rsf_files:
        print("No RSF files found.", file=sys.stderr)
        return 1

    all_meta = []
    t0 = time.time()

    for rsf_path in rsf_files:
        label = dataset_label(rsf_path)
        verbose = not args.quiet

        try:
            file_meta, rows = analyze_rsf_file(rsf_path,
                                                max_samples_per_ts=args.samples,
                                                verbose=verbose)
        except Exception as e:
            print(f"ERROR analyzing {rsf_path}: {e}", file=sys.stderr)
            continue

        write_timestep_csv(ts_csv, file_meta, rows, label)
        write_summary_csv(summary_csv, file_meta, rows, label)

        all_meta.append({
            'label': label,
            **file_meta,
            'timestep_count_analyzed': len(rows),
        })

    elapsed = time.time() - t0
    write_metadata_json(meta_json, {
        'generated_at': time.strftime('%Y-%m-%d %H:%M:%S'),
        'elapsed_seconds': round(elapsed, 1),
        'files_analyzed': len(all_meta),
        'datasets': all_meta,
    })

    print(f"\n{'='*60}")
    print(f"Analysis complete ({elapsed:.1f}s)")
    print(f"  Per-timestep CSV:  {ts_csv}")
    print(f"  Summary CSV:       {summary_csv}")
    print(f"  Metadata JSON:     {meta_json}")
    print(f"{'='*60}")

    # Print summary table
    print(f"\n{'Dataset':<16} {'Dims':<16} {'Steps':>5} {'Size':>7} "
          f"{'Begin%0':>8} {'Mid%0':>7} {'End%0':>7} {'RecFrac':>8}")
    print('-' * 86)
    with open(summary_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            print(f"{row['dataset']:<16} {row['spatial_dims']:<16} "
                  f"{row['n_timesteps']:>5} {row['file_size_gb']:>6}G "
                  f"{row['ts_begin_zero_pct']:>7}% "
                  f"{row['ts_mid_zero_pct']:>6}% "
                  f"{row['ts_end_zero_pct']:>6}% "
                  f"{row['recommended_start_fraction']:>8}")
    print()

    return 0


if __name__ == '__main__':
    sys.exit(main())
