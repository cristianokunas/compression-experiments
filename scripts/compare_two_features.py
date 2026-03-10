#!/usr/bin/env python3
"""
Two-Feature Comparison Visualization (Plotly version)

Compares two features (baseline vs optimized) with beautiful Plotly visualizations.
Modern color palette and professional charts.
"""

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import numpy as np
from pathlib import Path
import sys

# Modern light color palette
COLORS = {
    'baseline': '#85929E',      # Light gray
    'optimized': '#5DADE2',     # Light blue
    'compression': '#58D68D',    # Light green
    'decompression': '#EC7063',  # Light coral
    'ratio': '#F8B739'          # Golden yellow
}

def load_feature_results(feature_path):
    """Load results from a feature directory or CSV file."""
    if Path(feature_path).is_file():
        results_file = Path(feature_path)
    else:
        results_file = Path(feature_path) / 'results.csv'
    
    if not results_file.exists():
        raise FileNotFoundError(f"Results file not found: {results_file}")
    
    df = pd.read_csv(results_file)
    
    # Add metadata
    def get_size_category(filename):
        if 'xlarge' in filename.lower():
            return 'XLarge'
        elif 'large' in filename.lower():
            return 'Large'
        elif 'medium' in filename.lower() or 'meduim' in filename.lower():
            return 'Medium'
        elif 'small' in filename.lower():
            return 'Small'
        return 'Unknown'
    
    def get_data_type(filename):
        if 'TTI' in filename or 'tti' in filename.lower():
            return 'TTI'
        elif 'binary' in filename.lower():
            return 'Binary'
        elif 'random' in filename.lower():
            return 'Random'
        elif 'zero' in filename.lower():
            return 'Zeros'
        return 'Unknown'
    
    df['SizeCategory'] = df['TestFile'].apply(get_size_category)
    df['DataType'] = df['TestFile'].apply(get_data_type)
    df['SizeMB'] = df['FileSize'] / (1024 * 1024)
    
    return df

def plot_throughput_comparison(df_baseline, df_optimized, baseline_name, optimized_name, output_dir):
    """Side-by-side throughput comparison."""
    print("\n[1/6] Gerando Throughput Comparison...")
    
    algorithms = sorted(df_baseline['Algorithm'].unique())
    
    fig = make_subplots(
        rows=len(algorithms), cols=2,
        subplot_titles=[f'{algo.upper()} - Compression' if i % 2 == 0 else f'{algo.upper()} - Decompression'
                       for algo in algorithms for i in range(2)],
        vertical_spacing=0.10,
        horizontal_spacing=0.12
    )
    
    for idx, algo in enumerate(algorithms, 1):
        algo_baseline = df_baseline[df_baseline['Algorithm'] == algo].sort_values('TestFile')
        algo_optimized = df_optimized[df_optimized['Algorithm'] == algo].sort_values('TestFile')
        
        # Compression
        fig.add_trace(
            go.Bar(
                x=algo_baseline['TestFile'],
                y=algo_baseline['CompressionThroughput_GBps'],
                name=baseline_name,
                marker_color=COLORS['baseline'],
                legendgroup='baseline',
                showlegend=(idx == 1)
            ),
            row=idx, col=1
        )
        
        fig.add_trace(
            go.Bar(
                x=algo_optimized['TestFile'],
                y=algo_optimized['CompressionThroughput_GBps'],
                name=optimized_name,
                marker_color=COLORS['optimized'],
                legendgroup='optimized',
                showlegend=(idx == 1)
            ),
            row=idx, col=1
        )
        
        # Decompression
        fig.add_trace(
            go.Bar(
                x=algo_baseline['TestFile'],
                y=algo_baseline['DecompressionThroughput_GBps'],
                name=baseline_name,
                marker_color=COLORS['baseline'],
                legendgroup='baseline',
                showlegend=False
            ),
            row=idx, col=2
        )
        
        fig.add_trace(
            go.Bar(
                x=algo_optimized['TestFile'],
                y=algo_optimized['DecompressionThroughput_GBps'],
                name=optimized_name,
                marker_color=COLORS['optimized'],
                legendgroup='optimized',
                showlegend=False
            ),
            row=idx, col=2
        )
        
        fig.update_xaxes(tickangle=45, row=idx, col=1)
        fig.update_xaxes(tickangle=45, row=idx, col=2)
        fig.update_yaxes(title_text="Throughput (GB/s)", row=idx, col=1)
        fig.update_yaxes(title_text="Throughput (GB/s)", row=idx, col=2)
    
    fig.update_layout(
        height=400 * len(algorithms),
        width=1800,
        title_text=f"Throughput Comparison: {baseline_name} vs {optimized_name}",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=10),
        barmode='group'
    )
    
    output_file = output_dir / 'throughput_comparison.png'
    fig.write_image(str(output_file), width=2160, height=400 * len(algorithms), scale=2)
    print(f"  ✓ {output_file.name}")

def plot_improvement_summary(df_baseline, df_optimized, baseline_name, optimized_name, output_dir):
    """Summary statistics of improvements."""
    print("\n[2/6] Gerando Improvement Summary...")
    
    # Merge datasets
    merged = df_baseline.merge(df_optimized, on=['Algorithm', 'TestFile'], suffixes=('_base', '_opt'))
    
    merged['CompImprovement'] = ((merged['CompressionThroughput_GBps_opt'] - 
                                  merged['CompressionThroughput_GBps_base']) / 
                                 merged['CompressionThroughput_GBps_base']) * 100
    merged['DecompImprovement'] = ((merged['DecompressionThroughput_GBps_opt'] - 
                                    merged['DecompressionThroughput_GBps_base']) / 
                                   merged['DecompressionThroughput_GBps_base']) * 100
    
    algorithms = sorted(merged['Algorithm'].unique())
    
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Average Improvement', 'Maximum Improvement'),
        horizontal_spacing=0.12
    )
    
    # Average improvements
    avg_comp = [merged[merged['Algorithm'] == a]['CompImprovement'].mean() for a in algorithms]
    avg_decomp = [merged[merged['Algorithm'] == a]['DecompImprovement'].mean() for a in algorithms]
    
    fig.add_trace(
        go.Bar(
            x=[a.upper() for a in algorithms],
            y=avg_comp,
            name='Compression',
            marker_color=COLORS['compression'],
            text=[f'{v:+.1f}%' for v in avg_comp],
            textposition='outside'
        ),
        row=1, col=1
    )
    
    fig.add_trace(
        go.Bar(
            x=[a.upper() for a in algorithms],
            y=avg_decomp,
            name='Decompression',
            marker_color=COLORS['decompression'],
            text=[f'{v:+.1f}%' for v in avg_decomp],
            textposition='outside'
        ),
        row=1, col=1
    )
    
    # Maximum improvements
    max_comp = [merged[merged['Algorithm'] == a]['CompImprovement'].max() for a in algorithms]
    max_decomp = [merged[merged['Algorithm'] == a]['DecompImprovement'].max() for a in algorithms]
    
    fig.add_trace(
        go.Bar(
            x=[a.upper() for a in algorithms],
            y=max_comp,
            name='Compression',
            marker_color=COLORS['compression'],
            text=[f'{v:+.1f}%' for v in max_comp],
            textposition='outside',
            showlegend=False
        ),
        row=1, col=2
    )
    
    fig.add_trace(
        go.Bar(
            x=[a.upper() for a in algorithms],
            y=max_decomp,
            name='Decompression',
            marker_color=COLORS['decompression'],
            text=[f'{v:+.1f}%' for v in max_decomp],
            textposition='outside',
            showlegend=False
        ),
        row=1, col=2
    )
    
    # Add zero line
    for col in [1, 2]:
        fig.add_hline(y=0, line_dash="dash", line_color="#95A5A6", row=1, col=col)
    
    fig.update_yaxes(title_text="Improvement (%)", row=1, col=1)
    fig.update_yaxes(title_text="Improvement (%)", row=1, col=2)
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text=f"Performance Improvement: {optimized_name} vs {baseline_name}",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=12),
        barmode='group'
    )
    
    output_file = output_dir / 'improvement_summary.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_by_file_size(df_baseline, df_optimized, baseline_name, optimized_name, output_dir):
    """Comparison grouped by file size."""
    print("\n[3/6] Gerando File Size Comparison...")
    
    algorithms = sorted(df_baseline['Algorithm'].unique())
    size_categories = ['Small', 'Medium', 'Large', 'XLarge']
    
    fig = make_subplots(
        rows=len(algorithms), cols=2,
        subplot_titles=[f'{algo.upper()} - Compression by Size' if i % 2 == 0 
                       else f'{algo.upper()} - Decompression by Size'
                       for algo in algorithms for i in range(2)],
        vertical_spacing=0.12,
        horizontal_spacing=0.12
    )
    
    for idx, algo in enumerate(algorithms, 1):
        comp_base = []
        comp_opt = []
        decomp_base = []
        decomp_opt = []
        
        for size_cat in size_categories:
            base_data = df_baseline[(df_baseline['Algorithm'] == algo) & 
                                   (df_baseline['SizeCategory'] == size_cat)]
            opt_data = df_optimized[(df_optimized['Algorithm'] == algo) & 
                                   (df_optimized['SizeCategory'] == size_cat)]
            
            comp_base.append(base_data['CompressionThroughput_GBps'].mean() if len(base_data) > 0 else 0)
            comp_opt.append(opt_data['CompressionThroughput_GBps'].mean() if len(opt_data) > 0 else 0)
            decomp_base.append(base_data['DecompressionThroughput_GBps'].mean() if len(base_data) > 0 else 0)
            decomp_opt.append(opt_data['DecompressionThroughput_GBps'].mean() if len(opt_data) > 0 else 0)
        
        # Compression
        fig.add_trace(
            go.Bar(
                x=size_categories,
                y=comp_base,
                name=baseline_name,
                marker_color=COLORS['baseline'],
                text=[f'{v:.1f}' if v > 0 else '' for v in comp_base],
                textposition='outside',
                legendgroup='baseline',
                showlegend=(idx == 1)
            ),
            row=idx, col=1
        )
        
        fig.add_trace(
            go.Bar(
                x=size_categories,
                y=comp_opt,
                name=optimized_name,
                marker_color=COLORS['optimized'],
                text=[f'{v:.1f}' if v > 0 else '' for v in comp_opt],
                textposition='outside',
                legendgroup='optimized',
                showlegend=(idx == 1)
            ),
            row=idx, col=1
        )
        
        # Decompression
        fig.add_trace(
            go.Bar(
                x=size_categories,
                y=decomp_base,
                name=baseline_name,
                marker_color=COLORS['baseline'],
                text=[f'{v:.1f}' if v > 0 else '' for v in decomp_base],
                textposition='outside',
                legendgroup='baseline',
                showlegend=False
            ),
            row=idx, col=2
        )
        
        fig.add_trace(
            go.Bar(
                x=size_categories,
                y=decomp_opt,
                name=optimized_name,
                marker_color=COLORS['optimized'],
                text=[f'{v:.1f}' if v > 0 else '' for v in decomp_opt],
                textposition='outside',
                legendgroup='optimized',
                showlegend=False
            ),
            row=idx, col=2
        )
        
        fig.update_yaxes(title_text="Throughput (GB/s)", row=idx, col=1)
        fig.update_yaxes(title_text="Throughput (GB/s)", row=idx, col=2)
    
    fig.update_layout(
        height=400 * len(algorithms),
        width=1600,
        title_text=f"Performance by File Size: {baseline_name} vs {optimized_name}",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / 'filesize_comparison.png'
    fig.write_image(str(output_file), width=1920, height=400 * len(algorithms), scale=2)
    print(f"  ✓ {output_file.name}")

def plot_ratio_comparison(df_baseline, df_optimized, baseline_name, optimized_name, output_dir):
    """Compare compression ratios."""
    print("\n[4/6] Gerando Compression Ratio Comparison...")
    
    algorithms = sorted(df_baseline['Algorithm'].unique())
    
    fig = make_subplots(
        rows=1, cols=len(algorithms),
        subplot_titles=[algo.upper() for algo in algorithms],
        horizontal_spacing=0.10
    )
    
    for col_idx, algo in enumerate(algorithms, 1):
        base_data = df_baseline[df_baseline['Algorithm'] == algo].sort_values('TestFile')
        opt_data = df_optimized[df_optimized['Algorithm'] == algo].sort_values('TestFile')
        
        fig.add_trace(
            go.Bar(
                x=base_data['TestFile'],
                y=base_data['CompressionRatio'],
                name=baseline_name,
                marker_color=COLORS['baseline'],
                legendgroup='baseline',
                showlegend=(col_idx == 1)
            ),
            row=1, col=col_idx
        )
        
        fig.add_trace(
            go.Bar(
                x=opt_data['TestFile'],
                y=opt_data['CompressionRatio'],
                name=optimized_name,
                marker_color=COLORS['ratio'],
                legendgroup='optimized',
                showlegend=(col_idx == 1)
            ),
            row=1, col=col_idx
        )
        
        fig.update_xaxes(tickangle=45, row=1, col=col_idx)
        fig.update_yaxes(title_text="Compression Ratio" if col_idx == 1 else "", 
                        type='log', row=1, col=col_idx)
    
    fig.update_layout(
        height=600,
        width=600 * len(algorithms),
        title_text=f"Compression Ratio Comparison: {baseline_name} vs {optimized_name}",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=10),
        barmode='group'
    )
    
    output_file = output_dir / 'ratio_comparison.png'
    fig.write_image(str(output_file), width=720 * len(algorithms), height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_data_type_analysis(df_baseline, df_optimized, baseline_name, optimized_name, output_dir):
    """Analyze performance by data type."""
    print("\n[5/6] Gerando Data Type Analysis...")
    
    data_types = ['Binary', 'Random', 'TTI', 'Zeros']
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=[f'{dtype} Data' for dtype in data_types],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    positions = [(1, 1), (1, 2), (2, 1), (2, 2)]
    
    for (row, col), dtype in zip(positions, data_types):
        base_data = df_baseline[df_baseline['DataType'] == dtype]
        opt_data = df_optimized[df_optimized['DataType'] == dtype]
        
        if len(base_data) > 0 and len(opt_data) > 0:
            fig.add_trace(
                go.Bar(
                    x=['Compression', 'Decompression'],
                    y=[base_data['CompressionThroughput_GBps'].mean(),
                       base_data['DecompressionThroughput_GBps'].mean()],
                    name=baseline_name,
                    marker_color=COLORS['baseline'],
                    legendgroup='baseline',
                    showlegend=(dtype == 'Binary')
                ),
                row=row, col=col
            )
            
            fig.add_trace(
                go.Bar(
                    x=['Compression', 'Decompression'],
                    y=[opt_data['CompressionThroughput_GBps'].mean(),
                       opt_data['DecompressionThroughput_GBps'].mean()],
                    name=optimized_name,
                    marker_color=COLORS['optimized'],
                    legendgroup='optimized',
                    showlegend=(dtype == 'Binary')
                ),
                row=row, col=col
            )
        
        fig.update_yaxes(title_text="Throughput (GB/s)", row=row, col=col)
    
    fig.update_layout(
        height=1000,
        width=1600,
        title_text=f"Performance by Data Type: {baseline_name} vs {optimized_name}",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / 'datatype_analysis.png'
    fig.write_image(str(output_file), width=1920, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_overall_dashboard(df_baseline, df_optimized, baseline_name, optimized_name, output_dir):
    """Create comprehensive dashboard."""
    print("\n[6/6] Gerando Overall Dashboard...")
    
    fig = make_subplots(
        rows=2, cols=3,
        subplot_titles=(
            'Average Compression Throughput',
            'Average Decompression Throughput',
            'Average Compression Ratio',
            'Best Improvements',
            'Performance Distribution',
            'Summary Statistics'
        ),
        specs=[[{"type": "bar"}, {"type": "bar"}, {"type": "bar"}],
               [{"type": "bar"}, {"type": "box"}, {"type": "table"}]],
        vertical_spacing=0.15,
        horizontal_spacing=0.10
    )
    
    algorithms = sorted(df_baseline['Algorithm'].unique())
    
    # 1. Average compression
    comp_base = [df_baseline[df_baseline['Algorithm'] == a]['CompressionThroughput_GBps'].mean() 
                 for a in algorithms]
    comp_opt = [df_optimized[df_optimized['Algorithm'] == a]['CompressionThroughput_GBps'].mean() 
                for a in algorithms]
    
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=comp_base, name=baseline_name,
                        marker_color=COLORS['baseline'], legendgroup='baseline'), row=1, col=1)
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=comp_opt, name=optimized_name,
                        marker_color=COLORS['optimized'], legendgroup='optimized'), row=1, col=1)
    
    # 2. Average decompression
    decomp_base = [df_baseline[df_baseline['Algorithm'] == a]['DecompressionThroughput_GBps'].mean() 
                   for a in algorithms]
    decomp_opt = [df_optimized[df_optimized['Algorithm'] == a]['DecompressionThroughput_GBps'].mean() 
                  for a in algorithms]
    
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=decomp_base, name=baseline_name,
                        marker_color=COLORS['baseline'], legendgroup='baseline', showlegend=False), row=1, col=2)
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=decomp_opt, name=optimized_name,
                        marker_color=COLORS['optimized'], legendgroup='optimized', showlegend=False), row=1, col=2)
    
    # 3. Average ratio
    ratio_base = [df_baseline[df_baseline['Algorithm'] == a]['CompressionRatio'].mean() 
                  for a in algorithms]
    ratio_opt = [df_optimized[df_optimized['Algorithm'] == a]['CompressionRatio'].mean() 
                 for a in algorithms]
    
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=ratio_base, name=baseline_name,
                        marker_color=COLORS['baseline'], legendgroup='baseline', showlegend=False), row=1, col=3)
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=ratio_opt, name=optimized_name,
                        marker_color=COLORS['ratio'], legendgroup='optimized', showlegend=False), row=1, col=3)
    
    # 4. Best improvements
    merged = df_baseline.merge(df_optimized, on=['Algorithm', 'TestFile'], suffixes=('_base', '_opt'))
    merged['CompImprovement'] = ((merged['CompressionThroughput_GBps_opt'] - 
                                  merged['CompressionThroughput_GBps_base']) / 
                                 merged['CompressionThroughput_GBps_base']) * 100
    
    best_improvements = [merged[merged['Algorithm'] == a]['CompImprovement'].max() for a in algorithms]
    
    fig.add_trace(go.Bar(x=[a.upper() for a in algorithms], y=best_improvements,
                        marker_color=COLORS['compression'],
                        text=[f'{v:+.1f}%' for v in best_improvements],
                        textposition='outside'), row=2, col=1)
    
    # 5. Performance distribution
    for algo in algorithms:
        fig.add_trace(go.Box(y=df_optimized[df_optimized['Algorithm'] == algo]['CompressionThroughput_GBps'],
                            name=algo.upper(), marker_color=COLORS['optimized']), row=2, col=2)
    
    # 6. Summary table
    summary_data = [
        ['Tests', str(len(df_baseline)), str(len(df_optimized))],
        ['Avg Comp (GB/s)', f"{df_baseline['CompressionThroughput_GBps'].mean():.2f}",
         f"{df_optimized['CompressionThroughput_GBps'].mean():.2f}"],
        ['Avg Decomp (GB/s)', f"{df_baseline['DecompressionThroughput_GBps'].mean():.2f}",
         f"{df_optimized['DecompressionThroughput_GBps'].mean():.2f}"],
        ['Avg Ratio', f"{df_baseline['CompressionRatio'].mean():.2f}x",
         f"{df_optimized['CompressionRatio'].mean():.2f}x"]
    ]
    
    table_data = list(zip(*summary_data))
    
    fig.add_trace(go.Table(
        header=dict(values=['<b>Metric</b>', f'<b>{baseline_name}</b>', f'<b>{optimized_name}</b>'],
                   fill_color='#5DADE2', font=dict(color='white', size=11)),
        cells=dict(values=table_data, fill_color='#F8F9F9', font=dict(size=10), height=30)
    ), row=2, col=3)
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Ratio", row=1, col=3)
    fig.update_yaxes(title_text="Improvement (%)", row=2, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text=f"Performance Dashboard: {baseline_name} vs {optimized_name}",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=10),
        barmode='group',
        showlegend=True
    )
    
    output_file = output_dir / 'overall_dashboard.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python compare_two_features.py <baseline_path> <optimized_path> [baseline_name] [optimized_name]")
        print("\nExample:")
        print("  python compare_two_features.py \\")
        print("    results/feature1_baseline/results.csv \\")
        print("    results/feature2_wave64/results.csv \\")
        print("    \"Feature 1 (Baseline)\" \"Feature 2 (Wave64)\"")
        sys.exit(1)
    
    baseline_path = sys.argv[1]
    optimized_path = sys.argv[2]
    baseline_name = sys.argv[3] if len(sys.argv) > 3 else "Baseline"
    optimized_name = sys.argv[4] if len(sys.argv) > 4 else "Optimized"
    
    print("\n" + "=" * 100)
    print("TWO-FEATURE COMPARISON VISUALIZATION")
    print("=" * 100)
    
    # Load data
    print(f"\nLoading {baseline_name}: {baseline_path}")
    df_baseline = load_feature_results(baseline_path)
    print(f"  ✓ Loaded {len(df_baseline)} tests")
    
    print(f"\nLoading {optimized_name}: {optimized_path}")
    df_optimized = load_feature_results(optimized_path)
    print(f"  ✓ Loaded {len(df_optimized)} tests")
    
    # Create output directory
    output_dir = Path('comparison_output')
    output_dir.mkdir(exist_ok=True)
    
    print(f"\nGenerating visualizations in: {output_dir}")
    print("=" * 100)
    
    # Generate all visualizations
    plot_throughput_comparison(df_baseline, df_optimized, baseline_name, optimized_name, output_dir)
    plot_improvement_summary(df_baseline, df_optimized, baseline_name, optimized_name, output_dir)
    plot_by_file_size(df_baseline, df_optimized, baseline_name, optimized_name, output_dir)
    plot_ratio_comparison(df_baseline, df_optimized, baseline_name, optimized_name, output_dir)
    plot_data_type_analysis(df_baseline, df_optimized, baseline_name, optimized_name, output_dir)
    plot_overall_dashboard(df_baseline, df_optimized, baseline_name, optimized_name, output_dir)
    
    # Summary
    print("\n" + "=" * 100)
    print("✅ COMPLETE! All visualizations generated successfully")
    print("=" * 100)
    print("\nGenerated files:")
    for i, f in enumerate(sorted(output_dir.glob('*.png')), 1):
        print(f"  {i}. {f.name}")
    print(f"\n📁 Location: {output_dir.absolute()}")
    print("=" * 100 + "\n")

if __name__ == '__main__':
    main()
