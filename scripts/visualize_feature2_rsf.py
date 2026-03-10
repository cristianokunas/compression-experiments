#!/usr/bin/env python3
"""
Feature 2 Wave64 Benchmark Visualization with RSF Data

Generates insightful visualizations for Feature 2 benchmarks including RSF/TTI seismic data.
Focus on: performance trends, trade-offs, scalability, and algorithm comparison.
"""

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import numpy as np
from pathlib import Path
import sys

def load_csv_data(csv_path):
    """Load benchmark results from CSV file."""
    df = pd.read_csv(csv_path)
    return df

def add_file_metadata(df):
    """Add metadata columns for categorization."""
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
    
    def get_size_order(cat):
        order = {'Small': 1, 'Medium': 2, 'Large': 3, 'XLarge': 4}
        return order.get(cat, 0)
    
    df['SizeCategory'] = df['TestFile'].apply(get_size_category)
    df['DataType'] = df['TestFile'].apply(get_data_type)
    df['SizeMB'] = df['FileSize'] / (1024 * 1024)
    df['SizeOrder'] = df['SizeCategory'].apply(get_size_order)
    
    return df

def plot_performance_landscape(df, output_dir):
    """
    Main performance landscape: 3D view of throughput vs ratio vs file size.
    Shows the performance-efficiency trade-off space.
    """
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Compression: Speed vs Efficiency Trade-off', 
                       'Decompression: Speed vs File Size'),
        specs=[[{"type": "scatter"}, {"type": "scatter"}]],
        horizontal_spacing=0.12
    )
    
    colors = {'lz4': '#5DADE2', 'snappy': '#EC7063', 'cascaded': '#58D68D'}  # Light modern colors
    symbols = {'TTI': 'circle', 'Binary': 'square', 'Random': 'diamond', 'Zeros': 'triangle-up'}
    
    # Plot 1: Compression throughput vs ratio (bubble size = file size)
    for algo in sorted(df['Algorithm'].unique()):
        for dtype in sorted(df['DataType'].unique()):
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            if len(subset) > 0:
                fig.add_trace(
                    go.Scatter(
                        x=subset['CompressionRatio'],
                        y=subset['CompressionThroughput_GBps'],
                        mode='markers',
                        name=f'{algo.upper()} - {dtype}',
                        marker=dict(
                            size=np.sqrt(subset['SizeMB']) * 2,  # Scale by sqrt for better visibility
                            color=colors.get(algo, '#85929E'),
                            symbol=symbols.get(dtype, 'circle'),
                            opacity=0.7,
                            line=dict(width=1, color='white')
                        ),
                        text=[f'{algo.upper()}<br>{dtype}<br>{size:.0f}MB<br>'
                              f'Comp: {comp:.1f} GB/s<br>Ratio: {ratio:.1f}x'
                              for size, comp, ratio in zip(subset['SizeMB'], 
                                                          subset['CompressionThroughput_GBps'],
                                                          subset['CompressionRatio'])],
                        hovertemplate='%{text}<extra></extra>',
                        legendgroup=algo,
                        showlegend=(dtype == 'Binary')
                    ),
                    row=1, col=1
                )
    
    # Plot 2: Decompression throughput vs file size (log-log for scalability)
    for algo in sorted(df['Algorithm'].unique()):
        for dtype in sorted(df['DataType'].unique()):
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)].sort_values('SizeMB')
            if len(subset) > 0:
                fig.add_trace(
                    go.Scatter(
                        x=subset['SizeMB'],
                        y=subset['DecompressionThroughput_GBps'],
                        mode='lines+markers',
                        name=f'{algo.upper()} - {dtype}',
                        line=dict(color=colors.get(algo, '#85929E'), width=2),
                        marker=dict(size=8, symbol=symbols.get(dtype, 'circle')),
                        text=[f'{algo.upper()}<br>{dtype}<br>{size:.0f}MB<br>Decomp: {decomp:.1f} GB/s'
                              for size, decomp in zip(subset['SizeMB'], 
                                                     subset['DecompressionThroughput_GBps'])],
                        hovertemplate='%{text}<extra></extra>',
                        legendgroup=algo,
                        showlegend=False
                    ),
                    row=1, col=2
                )
    
    fig.update_xaxes(title_text="Compression Ratio (x)", type="log", row=1, col=1)
    fig.update_yaxes(title_text="Compression Throughput (GB/s)", row=1, col=1)
    fig.update_xaxes(title_text="File Size (MB)", type="log", row=1, col=2)
    fig.update_yaxes(title_text="Decompression Throughput (GB/s)", row=1, col=2)
    
    fig.update_layout(
        height=700,
        width=1800,
        title_text="Performance Landscape: Understanding Trade-offs",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=12),
        hovermode='closest'
    )
    
    output_file = output_dir / '01_performance_landscape.png'
    fig.write_image(str(output_file), width=2160, height=840, scale=2)
    print(f"✓ Created: {output_file.name}")

def plot_tti_deep_dive(df, output_dir):
    """
    Deep dive into TTI seismic data performance across all algorithms and sizes.
    """
    tti_data = df[df['DataType'] == 'TTI'].copy()
    if len(tti_data) == 0:
        print("⚠ No TTI data found")
        return
    
    tti_data = tti_data.sort_values(['Algorithm', 'SizeOrder'])
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'TTI Compression Performance by Size',
            'TTI Decompression Performance by Size',
            'TTI Compression Efficiency (Ratio)',
            'TTI Performance Summary: Best Choice per Metric'
        ),
        specs=[[{"secondary_y": False}, {"secondary_y": False}],
               [{"secondary_y": False}, {"type": "bar"}]],
        vertical_spacing=0.12,
        horizontal_spacing=0.12
    )
    
    colors = {'lz4': '#5DADE2', 'snappy': '#EC7063', 'cascaded': '#58D68D'}  # Light modern colors
    sizes = sorted(tti_data['SizeCategory'].unique(), key=lambda x: tti_data[tti_data['SizeCategory']==x]['SizeOrder'].iloc[0])
    
    # 1. Compression throughput
    for algo in sorted(tti_data['Algorithm'].unique()):
        algo_data = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Scatter(
                x=algo_data['SizeCategory'],
                y=algo_data['CompressionThroughput_GBps'],
                mode='lines+markers',
                name=algo.upper(),
                line=dict(color=colors.get(algo, '#85929E'), width=3),
                marker=dict(size=12),
                text=[f'{v:.1f} GB/s' for v in algo_data['CompressionThroughput_GBps']],
                textposition='top center'
            ),
            row=1, col=1
        )
    
    # 2. Decompression throughput
    for algo in sorted(tti_data['Algorithm'].unique()):
        algo_data = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Scatter(
                x=algo_data['SizeCategory'],
                y=algo_data['DecompressionThroughput_GBps'],
                mode='lines+markers',
                name=algo.upper(),
                line=dict(color=colors.get(algo, '#85929E'), width=3),
                marker=dict(size=12, symbol='square'),
                text=[f'{v:.1f} GB/s' for v in algo_data['DecompressionThroughput_GBps']],
                textposition='top center',
                showlegend=False
            ),
            row=1, col=2
        )
    
    # 3. Compression ratio
    for algo in sorted(tti_data['Algorithm'].unique()):
        algo_data = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Bar(
                x=algo_data['SizeCategory'],
                y=algo_data['CompressionRatio'],
                name=algo.upper(),
                marker_color=colors.get(algo, '#85929E'),
                text=[f'{v:.1f}x' for v in algo_data['CompressionRatio']],
                textposition='outside',
                showlegend=False
            ),
            row=2, col=1
        )
    
    # 4. Best algorithm per metric (using XLarge data as representative)
    xlarge_tti = tti_data[tti_data['SizeCategory'] == 'XLarge']
    if len(xlarge_tti) == 0:
        xlarge_tti = tti_data[tti_data['SizeCategory'] == 'Large']
    
    metrics = ['Comp Speed', 'Decomp Speed', 'Comp Ratio']
    best_values = []
    best_algos = []
    
    # Best compression speed
    best_comp = xlarge_tti.loc[xlarge_tti['CompressionThroughput_GBps'].idxmax()]
    best_values.append(best_comp['CompressionThroughput_GBps'])
    best_algos.append(best_comp['Algorithm'])
    
    # Best decompression speed
    best_decomp = xlarge_tti.loc[xlarge_tti['DecompressionThroughput_GBps'].idxmax()]
    best_values.append(best_decomp['DecompressionThroughput_GBps'])
    best_algos.append(best_decomp['Algorithm'])
    
    # Best compression ratio
    best_ratio = xlarge_tti.loc[xlarge_tti['CompressionRatio'].idxmax()]
    best_values.append(best_ratio['CompressionRatio'])
    best_algos.append(best_ratio['Algorithm'])
    
    for i, (metric, value, algo) in enumerate(zip(metrics, best_values, best_algos)):
        fig.add_trace(
            go.Bar(
                x=[metric],
                y=[value],
                name=algo.upper(),
                marker_color=colors.get(algo, '#85929E'),
                text=[f'{algo.upper()}<br>{value:.1f}'],
                textposition='inside',
                textfont=dict(color='white', size=14),
                showlegend=False
            ),
            row=2, col=2
        )
    
    fig.update_xaxes(title_text="File Size Category", row=1, col=1, categoryorder='array', categoryarray=sizes)
    fig.update_xaxes(title_text="File Size Category", row=1, col=2, categoryorder='array', categoryarray=sizes)
    fig.update_xaxes(title_text="File Size Category", row=2, col=1, categoryorder='array', categoryarray=sizes)
    fig.update_xaxes(title_text="Performance Metric", row=2, col=2)
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Compression Ratio (x)", row=2, col=1)
    fig.update_yaxes(title_text="Value", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="TTI Seismic Data: Comprehensive Algorithm Analysis",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=12),
        barmode='group'
    )
    
    output_file = output_dir / '02_tti_deep_dive.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"✓ Created: {output_file.name}")

def plot_data_compressibility(df, output_dir):
    """
    Analyze how different data types compress across algorithms.
    """
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Compression Ratio by Data Type',
            'Compression Speed by Data Compressibility',
            'Decompression Speed by Data Compressibility',
            'Speed-Efficiency Product (Higher = Better)'
        ),
        specs=[[{"type": "bar"}, {"type": "scatter"}],
               [{"type": "scatter"}, {"type": "bar"}]],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    colors = {'lz4': '#5DADE2', 'snappy': '#EC7063', 'cascaded': '#58D68D'}  # Light modern colors
    data_types = ['Random', 'Binary', 'TTI', 'Zeros']  # Ordered by expected compressibility
    
    # 1. Average compression ratio by data type
    for algo in sorted(df['Algorithm'].unique()):
        ratios = []
        for dtype in data_types:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            ratios.append(subset['CompressionRatio'].mean() if len(subset) > 0 else 0)
        
        fig.add_trace(
            go.Bar(
                x=data_types,
                y=ratios,
                name=algo.upper(),
                marker_color=colors.get(algo, '#85929E'),
                text=[f'{v:.1f}x' if v > 0 else '' for v in ratios],
                textposition='outside'
            ),
            row=1, col=1
        )
    
    # 2 & 3. Compression and decompression speed vs compressibility
    for algo in sorted(df['Algorithm'].unique()):
        algo_data = df[df['Algorithm'] == algo]
        avg_by_type = algo_data.groupby('DataType').agg({
            'CompressionRatio': 'mean',
            'CompressionThroughput_GBps': 'mean',
            'DecompressionThroughput_GBps': 'mean'
        }).reset_index()
        
        # Compression speed
        fig.add_trace(
            go.Scatter(
                x=avg_by_type['CompressionRatio'],
                y=avg_by_type['CompressionThroughput_GBps'],
                mode='markers+text',
                name=algo.upper(),
                marker=dict(size=15, color=colors.get(algo, '#85929E')),
                text=avg_by_type['DataType'],
                textposition='top center',
                showlegend=False
            ),
            row=1, col=2
        )
        
        # Decompression speed
        fig.add_trace(
            go.Scatter(
                x=avg_by_type['CompressionRatio'],
                y=avg_by_type['DecompressionThroughput_GBps'],
                mode='markers+text',
                name=algo.upper(),
                marker=dict(size=15, color=colors.get(algo, '#85929E')),
                text=avg_by_type['DataType'],
                textposition='top center',
                showlegend=False
            ),
            row=2, col=1
        )
    
    # 4. Performance product (throughput * ratio) - holistic metric
    for algo in sorted(df['Algorithm'].unique()):
        products = []
        for dtype in data_types:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            if len(subset) > 0:
                # Geometric mean of speed and efficiency
                product = (subset['CompressionThroughput_GBps'] * subset['CompressionRatio']).mean()
                products.append(product)
            else:
                products.append(0)
        
        fig.add_trace(
            go.Bar(
                x=data_types,
                y=products,
                name=algo.upper(),
                marker_color=colors.get(algo, '#85929E'),
                text=[f'{v:.0f}' if v > 0 else '' for v in products],
                textposition='outside',
                showlegend=False
            ),
            row=2, col=2
        )
    
    fig.update_xaxes(title_text="Data Type", row=1, col=1)
    fig.update_xaxes(title_text="Compression Ratio (x)", type="log", row=1, col=2)
    fig.update_xaxes(title_text="Compression Ratio (x)", type="log", row=2, col=1)
    fig.update_xaxes(title_text="Data Type", row=2, col=2)
    
    fig.update_yaxes(title_text="Avg Compression Ratio (x)", type="log", row=1, col=1)
    fig.update_yaxes(title_text="Comp Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Decomp Throughput (GB/s)", row=2, col=1)
    fig.update_yaxes(title_text="Speed × Ratio Product", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="Data Compressibility Analysis: How Data Type Affects Performance",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=12),
        barmode='group'
    )
    
    output_file = output_dir / '03_data_compressibility.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"✓ Created: {output_file.name}")

def plot_scalability_analysis(df, output_dir):
    """
    Analyze how performance scales with file size.
    """
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Compression Scalability (by Data Type)',
            'Decompression Scalability (by Data Type)',
            'Performance Stability: Coefficient of Variation',
            'Throughput Heatmap: Algorithm × Size'
        ),
        specs=[[{"type": "scatter"}, {"type": "scatter"}],
               [{"type": "bar"}, {"type": "heatmap"}]],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    colors = {'lz4': '#3498db', 'snappy': '#e74c3c', 'cascaded': '#2ecc71'}
    markers = {'TTI': 'circle', 'Binary': 'square', 'Random': 'diamond', 'Zeros': 'triangle-up'}
    
    # 1. Compression scalability
    for algo in sorted(df['Algorithm'].unique()):
        for dtype in sorted(df['DataType'].unique()):
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)].sort_values('SizeMB')
            if len(subset) > 1:  # Only plot if multiple sizes
                fig.add_trace(
                    go.Scatter(
                        x=subset['SizeMB'],
                        y=subset['CompressionThroughput_GBps'],
                        mode='lines+markers',
                        name=f'{algo.upper()}-{dtype}',
                        line=dict(color=colors.get(algo, '#85929E'), width=2, dash='solid' if dtype=='TTI' else 'dot'),
                        marker=dict(size=10, symbol=markers.get(dtype, 'circle')),
                        legendgroup=algo,
                        showlegend=(dtype == 'TTI')
                    ),
                    row=1, col=1
                )
    
    # 2. Decompression scalability
    for algo in sorted(df['Algorithm'].unique()):
        for dtype in sorted(df['DataType'].unique()):
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)].sort_values('SizeMB')
            if len(subset) > 1:
                fig.add_trace(
                    go.Scatter(
                        x=subset['SizeMB'],
                        y=subset['DecompressionThroughput_GBps'],
                        mode='lines+markers',
                        name=f'{algo.upper()}-{dtype}',
                        line=dict(color=colors.get(algo, '#85929E'), width=2, dash='solid' if dtype=='TTI' else 'dot'),
                        marker=dict(size=10, symbol=markers.get(dtype, 'circle')),
                        legendgroup=algo,
                        showlegend=False
                    ),
                    row=1, col=2
                )
    
    # 3. Coefficient of variation (stability metric)
    cv_data = []
    for algo in sorted(df['Algorithm'].unique()):
        algo_data = df[df['Algorithm'] == algo]
        cv_comp = (algo_data['CompressionThroughput_GBps'].std() / 
                   algo_data['CompressionThroughput_GBps'].mean()) * 100
        cv_decomp = (algo_data['DecompressionThroughput_GBps'].std() / 
                     algo_data['DecompressionThroughput_GBps'].mean()) * 100
        cv_data.append({'Algorithm': algo, 'Compression CV': cv_comp, 'Decompression CV': cv_decomp})
    
    cv_df = pd.DataFrame(cv_data)
    
    fig.add_trace(
        go.Bar(
            x=cv_df['Algorithm'].apply(str.upper),
            y=cv_df['Compression CV'],
            name='Compression',
            marker_color='#3498db',
            text=[f'{v:.1f}%' for v in cv_df['Compression CV']],
            textposition='outside'
        ),
        row=2, col=1
    )
    
    fig.add_trace(
        go.Bar(
            x=cv_df['Algorithm'].apply(str.upper),
            y=cv_df['Decompression CV'],
            name='Decompression',
            marker_color='#e74c3c',
            text=[f'{v:.1f}%' for v in cv_df['Decompression CV']],
            textposition='outside'
        ),
        row=2, col=1
    )
    
    # 4. Heatmap: Algorithm × Size
    sizes = sorted(df['SizeCategory'].unique(), key=lambda x: df[df['SizeCategory']==x]['SizeOrder'].iloc[0])
    algos = sorted(df['Algorithm'].unique())
    
    heatmap_data = []
    for algo in algos:
        row_data = []
        for size in sizes:
            subset = df[(df['Algorithm'] == algo) & (df['SizeCategory'] == size)]
            avg_throughput = subset['CompressionThroughput_GBps'].mean() if len(subset) > 0 else 0
            row_data.append(avg_throughput)
        heatmap_data.append(row_data)
    
    fig.add_trace(
        go.Heatmap(
            z=heatmap_data,
            x=sizes,
            y=[a.upper() for a in algos],
            colorscale='RdYlGn',
            text=[[f'{v:.1f}' for v in row] for row in heatmap_data],
            texttemplate='%{text} GB/s',
            textfont={"size": 11},
            colorbar=dict(title="GB/s")
        ),
        row=2, col=2
    )
    
    fig.update_xaxes(title_text="File Size (MB)", type="log", row=1, col=1)
    fig.update_xaxes(title_text="File Size (MB)", type="log", row=1, col=2)
    fig.update_xaxes(title_text="Algorithm", row=2, col=1)
    fig.update_xaxes(title_text="File Size Category", row=2, col=2)
    
    fig.update_yaxes(title_text="Comp Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Decomp Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Coefficient of Variation (%)", row=2, col=1)
    fig.update_yaxes(title_text="Algorithm", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="Scalability Analysis: Performance Across File Sizes",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11)
    )
    
    output_file = output_dir / '04_scalability_analysis.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"✓ Created: {output_file.name}")

def plot_algorithm_recommendations(df, output_dir):
    """
    Decision matrix: which algorithm to choose based on use case.
    """
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Use Case Recommendation Matrix',
            'Performance Profiles (Radar Chart)',
            'Relative Performance: Normalized to Best',
            'Winner Count: How Often Each Algorithm Wins'
        ),
        specs=[[{"type": "table"}, {"type": "scatterpolar"}],
               [{"type": "bar"}, {"type": "bar"}]],
        vertical_spacing=0.12,
        horizontal_spacing=0.12
    )
    
    colors = {'lz4': '#3498db', 'snappy': '#e74c3c', 'cascaded': '#2ecc71'}
    
    # 1. Decision table
    use_cases = [
        'Need Max Compression Speed',
        'Need Max Decompression Speed',
        'Need Best Compression Ratio',
        'Balanced Performance',
        'TTI Seismic Data (Speed)',
        'TTI Seismic Data (Ratio)'
    ]
    
    recommendations = []
    
    # Max compression speed
    best_comp = df.loc[df['CompressionThroughput_GBps'].idxmax()]
    recommendations.append(f"{best_comp['Algorithm'].upper()} ({best_comp['CompressionThroughput_GBps']:.1f} GB/s)")
    
    # Max decompression speed
    best_decomp = df.loc[df['DecompressionThroughput_GBps'].idxmax()]
    recommendations.append(f"{best_decomp['Algorithm'].upper()} ({best_decomp['DecompressionThroughput_GBps']:.1f} GB/s)")
    
    # Best ratio
    best_ratio = df.loc[df['CompressionRatio'].idxmax()]
    recommendations.append(f"{best_ratio['Algorithm'].upper()} ({best_ratio['CompressionRatio']:.1f}x)")
    
    # Balanced (harmonic mean of comp, decomp, ratio)
    df['BalancedScore'] = 3 / (1/df['CompressionThroughput_GBps'] + 
                                1/df['DecompressionThroughput_GBps'] + 
                                1/(df['CompressionRatio']+1))
    best_balanced = df.loc[df['BalancedScore'].idxmax()]
    recommendations.append(f"{best_balanced['Algorithm'].upper()} (Score: {best_balanced['BalancedScore']:.1f})")
    
    # TTI speed
    tti_data = df[df['DataType'] == 'TTI']
    best_tti_speed = tti_data.loc[tti_data['CompressionThroughput_GBps'].idxmax()]
    recommendations.append(f"{best_tti_speed['Algorithm'].upper()} ({best_tti_speed['CompressionThroughput_GBps']:.1f} GB/s)")
    
    # TTI ratio
    best_tti_ratio = tti_data.loc[tti_data['CompressionRatio'].idxmax()]
    recommendations.append(f"{best_tti_ratio['Algorithm'].upper()} ({best_tti_ratio['CompressionRatio']:.1f}x)")
    
    fig.add_trace(
        go.Table(
            header=dict(values=['<b>Use Case</b>', '<b>Recommended Algorithm</b>'],
                       fill_color='#85929E',
                       font=dict(color='white', size=12),
                       align='left'),
            cells=dict(values=[use_cases, recommendations],
                      fill_color='#ecf0f1',
                      font=dict(size=11),
                      align='left',
                      height=30)
        ),
        row=1, col=1
    )
    
    # 2. Radar chart - performance profiles
    categories = ['Comp Speed', 'Decomp Speed', 'Comp Ratio', 'Stability']
    
    for algo in sorted(df['Algorithm'].unique()):
        algo_data = df[df['Algorithm'] == algo]
        
        # Normalize to 0-100 scale
        max_comp = df['CompressionThroughput_GBps'].max()
        max_decomp = df['DecompressionThroughput_GBps'].max()
        max_ratio = df['CompressionRatio'].max()
        
        values = [
            (algo_data['CompressionThroughput_GBps'].mean() / max_comp) * 100,
            (algo_data['DecompressionThroughput_GBps'].mean() / max_decomp) * 100,
            (algo_data['CompressionRatio'].mean() / max_ratio) * 100,
            100 - ((algo_data['CompressionThroughput_GBps'].std() / 
                    algo_data['CompressionThroughput_GBps'].mean()) * 100)  # Inverse of CV
        ]
        values.append(values[0])  # Close the polygon
        
        fig.add_trace(
            go.Scatterpolar(
                r=values,
                theta=categories + [categories[0]],
                fill='toself',
                name=algo.upper(),
                line=dict(color=colors.get(algo, '#85929E'), width=2),
                opacity=0.6
            ),
            row=1, col=2
        )
    
    # 3. Relative performance (normalized to best in each category)
    metrics = ['Comp Speed', 'Decomp Speed', 'Ratio']
    
    for algo in sorted(df['Algorithm'].unique()):
        algo_data = df[df['Algorithm'] == algo]
        relative = [
            (algo_data['CompressionThroughput_GBps'].mean() / df['CompressionThroughput_GBps'].max()) * 100,
            (algo_data['DecompressionThroughput_GBps'].mean() / df['DecompressionThroughput_GBps'].max()) * 100,
            (algo_data['CompressionRatio'].mean() / df['CompressionRatio'].max()) * 100
        ]
        
        fig.add_trace(
            go.Bar(
                x=metrics,
                y=relative,
                name=algo.upper(),
                marker_color=colors.get(algo, '#85929E'),
                text=[f'{v:.0f}%' for v in relative],
                textposition='outside'
            ),
            row=2, col=1
        )
    
    # 4. Winner count
    winner_counts = {'lz4': 0, 'snappy': 0, 'cascaded': 0}
    
    for _, row in df.iterrows():
        file_subset = df[df['TestFile'] == row['TestFile']]
        
        # Winner in compression speed
        if row['CompressionThroughput_GBps'] == file_subset['CompressionThroughput_GBps'].max():
            winner_counts[row['Algorithm']] += 1
        
        # Winner in decompression speed
        if row['DecompressionThroughput_GBps'] == file_subset['DecompressionThroughput_GBps'].max():
            winner_counts[row['Algorithm']] += 1
        
        # Winner in compression ratio
        if row['CompressionRatio'] == file_subset['CompressionRatio'].max():
            winner_counts[row['Algorithm']] += 1
    
    fig.add_trace(
        go.Bar(
            x=[k.upper() for k in winner_counts.keys()],
            y=list(winner_counts.values()),
            marker_color=[colors.get(k, '#85929E') for k in winner_counts.keys()],
            text=list(winner_counts.values()),
            textposition='outside',
            showlegend=False
        ),
        row=2, col=2
    )
    
    fig.update_xaxes(title_text="Metric", row=2, col=1)
    fig.update_xaxes(title_text="Algorithm", row=2, col=2)
    
    fig.update_yaxes(title_text="Relative Performance (%)", row=2, col=1)
    fig.update_yaxes(title_text="Number of Wins", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="Algorithm Selection Guide: Choose the Right Tool for Your Job",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11),
        barmode='group',
        polar=dict(radialaxis=dict(visible=True, range=[0, 100]))
    )
    
    output_file = output_dir / '05_algorithm_recommendations.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"✓ Created: {output_file.name}")

def generate_summary_report(df, output_dir):
    """Generate comprehensive text report."""
    report = []
    report.append("=" * 90)
    report.append("FEATURE 2 WAVE64 - COMPREHENSIVE BENCHMARK ANALYSIS")
    report.append("=" * 90)
    report.append("")
    
    # Executive Summary
    report.append("EXECUTIVE SUMMARY")
    report.append("-" * 90)
    report.append(f"Total benchmark tests: {len(df)}")
    report.append(f"Algorithms evaluated: {', '.join([a.upper() for a in sorted(df['Algorithm'].unique())])}")
    report.append(f"Data types tested: {', '.join(sorted(df['DataType'].unique()))}")
    report.append(f"File size range: {df['SizeMB'].min():.0f} MB to {df['SizeMB'].max():.0f} MB")
    report.append("")
    
    # TTI Seismic Data Analysis
    tti_data = df[df['DataType'] == 'TTI']
    if len(tti_data) > 0:
        report.append("TTI SEISMIC DATA - KEY FINDINGS")
        report.append("-" * 90)
        
        for algo in sorted(tti_data['Algorithm'].unique()):
            algo_tti = tti_data[tti_data['Algorithm'] == algo]
            report.append(f"\n{algo.upper()}:")
            report.append(f"  Compression:   {algo_tti['CompressionThroughput_GBps'].mean():6.2f} GB/s "
                         f"(range: {algo_tti['CompressionThroughput_GBps'].min():.2f} - "
                         f"{algo_tti['CompressionThroughput_GBps'].max():.2f})")
            report.append(f"  Decompression: {algo_tti['DecompressionThroughput_GBps'].mean():6.2f} GB/s "
                         f"(range: {algo_tti['DecompressionThroughput_GBps'].min():.2f} - "
                         f"{algo_tti['DecompressionThroughput_GBps'].max():.2f})")
            report.append(f"  Comp Ratio:    {algo_tti['CompressionRatio'].mean():6.2f}x "
                         f"(range: {algo_tti['CompressionRatio'].min():.2f} - "
                         f"{algo_tti['CompressionRatio'].max():.2f})")
        report.append("")
    
    # Overall Performance Rankings
    report.append("OVERALL PERFORMANCE RANKINGS")
    report.append("-" * 90)
    
    # Compression speed
    comp_ranking = df.groupby('Algorithm')['CompressionThroughput_GBps'].mean().sort_values(ascending=False)
    report.append("\nCompression Speed:")
    for i, (algo, speed) in enumerate(comp_ranking.items(), 1):
        report.append(f"  {i}. {algo.upper():10s} {speed:6.2f} GB/s")
    
    # Decompression speed
    decomp_ranking = df.groupby('Algorithm')['DecompressionThroughput_GBps'].mean().sort_values(ascending=False)
    report.append("\nDecompression Speed:")
    for i, (algo, speed) in enumerate(decomp_ranking.items(), 1):
        report.append(f"  {i}. {algo.upper():10s} {speed:6.2f} GB/s")
    
    # Compression ratio
    ratio_ranking = df.groupby('Algorithm')['CompressionRatio'].mean().sort_values(ascending=False)
    report.append("\nCompression Ratio:")
    for i, (algo, ratio) in enumerate(ratio_ranking.items(), 1):
        report.append(f"  {i}. {algo.upper():10s} {ratio:6.2f}x")
    
    report.append("")
    report.append("=" * 90)
    
    # Save report
    report_text = "\n".join(report)
    report_file = output_dir / 'benchmark_analysis.txt'
    with open(report_file, 'w') as f:
        f.write(report_text)
    
    print(f"✓ Created: {report_file.name}")
    print("\n" + report_text)

def main():
    if len(sys.argv) < 2:
        print("Usage: python visualize_feature2_rsf.py <path_to_results.csv>")
        print("\nExample:")
        print("  python visualize_feature2_rsf.py results/feature2_wave64/20251201_170939_87a26a0/results.csv")
        sys.exit(1)
    
    csv_path = Path(sys.argv[1])
    
    if not csv_path.exists():
        print(f"Error: File not found: {csv_path}")
        sys.exit(1)
    
    print(f"\n{'='*90}")
    print(f"Feature 2 Wave64 Benchmark Visualization - Advanced Analysis")
    print(f"{'='*90}")
    print(f"\nLoading data from: {csv_path}")
    
    # Load and process data
    df = load_csv_data(csv_path)
    df = add_file_metadata(df)
    
    print(f"  Total tests: {len(df)}")
    print(f"  Algorithms: {', '.join(sorted(df['Algorithm'].unique()))}")
    print(f"  Data types: {', '.join(sorted(df['DataType'].unique()))}")
    
    # Create output directory
    output_dir = csv_path.parent / 'visualizations'
    output_dir.mkdir(exist_ok=True)
    
    print(f"\nGenerating advanced visualizations in: {output_dir}")
    print(f"{'-'*90}")
    
    # Generate all plots
    plot_performance_landscape(df, output_dir)
    plot_tti_deep_dive(df, output_dir)
    plot_data_compressibility(df, output_dir)
    plot_scalability_analysis(df, output_dir)
    plot_algorithm_recommendations(df, output_dir)
    
    # Generate report
    print(f"{'-'*90}")
    generate_summary_report(df, output_dir)
    
    print(f"\n{'='*90}")
    print(f"✅ Advanced visualization complete!")
    print(f"\nGenerated visualizations:")
    for f in sorted(output_dir.glob('*.png')):
        print(f"  📊 {f.name}")
    print(f"  📄 benchmark_analysis.txt")
    print(f"\nLocation: {output_dir.absolute()}")
    print(f"{'='*90}\n")

if __name__ == '__main__':
    main()
