#!/usr/bin/env python3
"""
Feature Comparison Visualization for MI300X GPU

Compares features 2-5 performance on AMD MI300X GPU with modern, beautiful visualizations.
Uses Plotly for interactive and high-quality PNG exports.
"""

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import numpy as np
from pathlib import Path
import sys

# Modern light color palette
FEATURE_COLORS = {
    'Feature 2 (Wave64)': '#5DADE2',        # Light blue
    'Feature 3 (LDS)': '#EC7063',           # Light coral
    'Feature 4': '#58D68D',                 # Light green
    'Feature 5 (Instructions)': '#F8B739'   # Golden yellow
}

ALGO_COLORS = {
    'lz4': '#5DADE2',
    'snappy': '#EC7063',
    'cascaded': '#58D68D'
}

def load_feature_results(feature_path):
    """Load results from a feature directory."""
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

def plot_feature_comparison_overview(features_data, output_dir):
    """
    Overview comparison: Average performance across all features.
    """
    print("\n[1/8] Gerando Feature Comparison Overview...")
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Compression Throughput by Feature',
            'Decompression Throughput by Feature',
            'Compression Ratio by Feature',
            'Overall Efficiency Score'
        ),
        vertical_spacing=0.12,
        horizontal_spacing=0.12
    )
    
    feature_names = list(features_data.keys())
    algorithms = sorted(features_data[feature_names[0]]['Algorithm'].unique())
    
    # 1. Compression throughput
    for algo in algorithms:
        values = []
        for feat in feature_names:
            avg = features_data[feat][features_data[feat]['Algorithm'] == algo]['CompressionThroughput_GBps'].mean()
            values.append(avg)
        
        fig.add_trace(
            go.Bar(
                x=feature_names,
                y=values,
                name=algo.upper(),
                marker_color=ALGO_COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}' for v in values],
                textposition='outside'
            ),
            row=1, col=1
        )
    
    # 2. Decompression throughput
    for algo in algorithms:
        values = []
        for feat in feature_names:
            avg = features_data[feat][features_data[feat]['Algorithm'] == algo]['DecompressionThroughput_GBps'].mean()
            values.append(avg)
        
        fig.add_trace(
            go.Bar(
                x=feature_names,
                y=values,
                name=algo.upper(),
                marker_color=ALGO_COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}' for v in values],
                textposition='outside',
                showlegend=False
            ),
            row=1, col=2
        )
    
    # 3. Compression ratio
    for algo in algorithms:
        values = []
        for feat in feature_names:
            avg = features_data[feat][features_data[feat]['Algorithm'] == algo]['CompressionRatio'].mean()
            values.append(avg)
        
        fig.add_trace(
            go.Bar(
                x=feature_names,
                y=values,
                name=algo.upper(),
                marker_color=ALGO_COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}x' for v in values],
                textposition='outside',
                showlegend=False
            ),
            row=2, col=1
        )
    
    # 4. Efficiency score (throughput * log(ratio))
    for algo in algorithms:
        values = []
        for feat in feature_names:
            df_algo = features_data[feat][features_data[feat]['Algorithm'] == algo]
            efficiency = (df_algo['CompressionThroughput_GBps'] * np.log2(df_algo['CompressionRatio'] + 1)).mean()
            values.append(efficiency)
        
        fig.add_trace(
            go.Bar(
                x=feature_names,
                y=values,
                name=algo.upper(),
                marker_color=ALGO_COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}' for v in values],
                textposition='outside',
                showlegend=False
            ),
            row=2, col=2
        )
    
    fig.update_xaxes(title_text="Feature", tickangle=45, row=1, col=1)
    fig.update_xaxes(title_text="Feature", tickangle=45, row=1, col=2)
    fig.update_xaxes(title_text="Feature", tickangle=45, row=2, col=1)
    fig.update_xaxes(title_text="Feature", tickangle=45, row=2, col=2)
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Compression Ratio", row=2, col=1)
    fig.update_yaxes(title_text="Efficiency Score", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="MI300X GPU: Feature Comparison Overview<br>"
                   "<sub>Average performance across all test files</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / '01_feature_comparison_overview.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_improvement_heatmap(features_data, baseline_name, output_dir):
    """
    Heatmap showing percentage improvements relative to baseline.
    """
    print("\n[2/8] Gerando Improvement Heatmap...")
    
    baseline = features_data[baseline_name]
    feature_names = [f for f in features_data.keys() if f != baseline_name]
    algorithms = sorted(baseline['Algorithm'].unique())
    
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Compression Throughput Improvement (%)', 
                       'Decompression Throughput Improvement (%)'),
        horizontal_spacing=0.12
    )
    
    # Compression improvement
    comp_matrix = []
    for feat in feature_names:
        row = []
        for algo in algorithms:
            baseline_val = baseline[baseline['Algorithm'] == algo]['CompressionThroughput_GBps'].mean()
            feature_val = features_data[feat][features_data[feat]['Algorithm'] == algo]['CompressionThroughput_GBps'].mean()
            improvement = ((feature_val - baseline_val) / baseline_val) * 100
            row.append(improvement)
        comp_matrix.append(row)
    
    fig.add_trace(
        go.Heatmap(
            z=comp_matrix,
            x=[a.upper() for a in algorithms],
            y=feature_names,
            colorscale='RdYlGn',
            text=[[f'{v:+.1f}%' for v in row] for row in comp_matrix],
            texttemplate='%{text}',
            textfont={"size": 12},
            colorbar=dict(title="% Change", x=0.46)
        ),
        row=1, col=1
    )
    
    # Decompression improvement
    decomp_matrix = []
    for feat in feature_names:
        row = []
        for algo in algorithms:
            baseline_val = baseline[baseline['Algorithm'] == algo]['DecompressionThroughput_GBps'].mean()
            feature_val = features_data[feat][features_data[feat]['Algorithm'] == algo]['DecompressionThroughput_GBps'].mean()
            improvement = ((feature_val - baseline_val) / baseline_val) * 100
            row.append(improvement)
        decomp_matrix.append(row)
    
    fig.add_trace(
        go.Heatmap(
            z=decomp_matrix,
            x=[a.upper() for a in algorithms],
            y=feature_names,
            colorscale='RdYlGn',
            text=[[f'{v:+.1f}%' for v in row] for row in decomp_matrix],
            texttemplate='%{text}',
            textfont={"size": 12},
            colorbar=dict(title="% Change", x=1.0)
        ),
        row=1, col=2
    )
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text=f"Performance Improvement vs {baseline_name}<br>"
                   "<sub>Green = better, Red = worse</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11)
    )
    
    output_file = output_dir / '02_improvement_heatmap.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_tti_seismic_comparison(features_data, output_dir):
    """
    Deep dive into TTI seismic data across all features.
    """
    print("\n[3/8] Gerando TTI Seismic Comparison...")
    
    feature_names = list(features_data.keys())
    
    # Extract TTI data from all features
    tti_data = {}
    for feat, df in features_data.items():
        tti_data[feat] = df[df['DataType'] == 'TTI'].copy()
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'TTI Compression Throughput',
            'TTI Decompression Throughput',
            'TTI Compression Ratio',
            'TTI Best Feature per Algorithm'
        ),
        specs=[[{"secondary_y": False}, {"secondary_y": False}],
               [{"secondary_y": False}, {"type": "bar"}]],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    algorithms = sorted(tti_data[feature_names[0]]['Algorithm'].unique())
    
    # 1. Compression throughput
    for feat in feature_names:
        for algo in algorithms:
            algo_data = tti_data[feat][tti_data[feat]['Algorithm'] == algo]
            if len(algo_data) > 0:
                avg_comp = algo_data['CompressionThroughput_GBps'].mean()
                
                fig.add_trace(
                    go.Bar(
                        x=[f"{feat}<br>{algo.upper()}"],
                        y=[avg_comp],
                        name=feat,
                        marker_color=FEATURE_COLORS.get(feat, '#85929E'),
                        text=f'{avg_comp:.1f}',
                        textposition='outside',
                        legendgroup=feat,
                        showlegend=(algo == algorithms[0])
                    ),
                    row=1, col=1
                )
    
    # 2. Decompression throughput
    for feat in feature_names:
        for algo in algorithms:
            algo_data = tti_data[feat][tti_data[feat]['Algorithm'] == algo]
            if len(algo_data) > 0:
                avg_decomp = algo_data['DecompressionThroughput_GBps'].mean()
                
                fig.add_trace(
                    go.Bar(
                        x=[f"{feat}<br>{algo.upper()}"],
                        y=[avg_decomp],
                        name=feat,
                        marker_color=FEATURE_COLORS.get(feat, '#85929E'),
                        text=f'{avg_decomp:.1f}',
                        textposition='outside',
                        legendgroup=feat,
                        showlegend=False
                    ),
                    row=1, col=2
                )
    
    # 3. Compression ratio
    for feat in feature_names:
        for algo in algorithms:
            algo_data = tti_data[feat][tti_data[feat]['Algorithm'] == algo]
            if len(algo_data) > 0:
                avg_ratio = algo_data['CompressionRatio'].mean()
                
                fig.add_trace(
                    go.Bar(
                        x=[f"{feat}<br>{algo.upper()}"],
                        y=[avg_ratio],
                        name=feat,
                        marker_color=FEATURE_COLORS.get(feat, '#85929E'),
                        text=f'{avg_ratio:.1f}x',
                        textposition='outside',
                        legendgroup=feat,
                        showlegend=False
                    ),
                    row=2, col=1
                )
    
    # 4. Best feature per algorithm
    for algo in algorithms:
        best_feat = None
        best_val = 0
        
        for feat in feature_names:
            algo_data = tti_data[feat][tti_data[feat]['Algorithm'] == algo]
            if len(algo_data) > 0:
                effectiveness = (algo_data['CompressionThroughput_GBps'] * 
                               np.log2(algo_data['CompressionRatio'] + 1)).mean()
                if effectiveness > best_val:
                    best_val = effectiveness
                    best_feat = feat
        
        if best_feat:
            fig.add_trace(
                go.Bar(
                    x=[algo.upper()],
                    y=[best_val],
                    name=best_feat,
                    marker_color=FEATURE_COLORS.get(best_feat, '#85929E'),
                    text=f'{best_feat}<br>{best_val:.1f}',
                    textposition='outside',
                    legendgroup=best_feat,
                    showlegend=False
                ),
                row=2, col=2
            )
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Compression Ratio", row=2, col=1)
    fig.update_yaxes(title_text="Efficiency Score", row=2, col=2)
    
    fig.update_xaxes(tickangle=45, row=1, col=1)
    fig.update_xaxes(tickangle=45, row=1, col=2)
    fig.update_xaxes(tickangle=45, row=2, col=1)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="MI300X GPU: TTI Seismic Data Performance Across Features<br>"
                   "<sub>Real-world seismic data comparison</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=10),
        barmode='group'
    )
    
    output_file = output_dir / '03_tti_seismic_comparison.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_scalability_comparison(features_data, output_dir):
    """
    Compare how features scale with file size.
    """
    print("\n[4/8] Gerando Scalability Comparison...")
    
    feature_names = list(features_data.keys())
    
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Compression Scalability', 'Decompression Scalability'),
        horizontal_spacing=0.12
    )
    
    # For each feature and algorithm, plot throughput vs file size
    for feat in feature_names:
        df = features_data[feat]
        
        for algo in sorted(df['Algorithm'].unique()):
            algo_data = df[df['Algorithm'] == algo].sort_values('SizeMB')
            
            # Compression
            fig.add_trace(
                go.Scatter(
                    x=algo_data['SizeMB'],
                    y=algo_data['CompressionThroughput_GBps'],
                    mode='lines+markers',
                    name=f'{feat} - {algo.upper()}',
                    line=dict(color=FEATURE_COLORS.get(feat, '#85929E'), 
                             width=2,
                             dash='solid' if algo == 'cascaded' else 'dot'),
                    marker=dict(size=8),
                    legendgroup=feat,
                    showlegend=(algo == 'cascaded')
                ),
                row=1, col=1
            )
            
            # Decompression
            fig.add_trace(
                go.Scatter(
                    x=algo_data['SizeMB'],
                    y=algo_data['DecompressionThroughput_GBps'],
                    mode='lines+markers',
                    name=f'{feat} - {algo.upper()}',
                    line=dict(color=FEATURE_COLORS.get(feat, '#85929E'), 
                             width=2,
                             dash='solid' if algo == 'cascaded' else 'dot'),
                    marker=dict(size=8),
                    legendgroup=feat,
                    showlegend=False
                ),
                row=1, col=2
            )
    
    fig.update_xaxes(title_text="File Size (MB)", type='log', row=1, col=1)
    fig.update_xaxes(title_text="File Size (MB)", type='log', row=1, col=2)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    
    fig.update_layout(
        height=700,
        width=1800,
        title_text="MI300X GPU: Scalability Analysis Across Features<br>"
                   "<sub>Solid = CASCADED | Dotted = other algorithms</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11)
    )
    
    output_file = output_dir / '04_scalability_comparison.png'
    fig.write_image(str(output_file), width=2160, height=840, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_data_type_performance(features_data, output_dir):
    """
    Compare performance across different data types.
    """
    print("\n[5/8] Gerando Data Type Performance...")
    
    feature_names = list(features_data.keys())
    data_types = ['Binary', 'Random', 'TTI', 'Zeros']
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=[f'{dtype} Data' for dtype in data_types],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    positions = [(1, 1), (1, 2), (2, 1), (2, 2)]
    
    for (row, col), dtype in zip(positions, data_types):
        for feat in feature_names:
            df_type = features_data[feat][features_data[feat]['DataType'] == dtype]
            
            if len(df_type) > 0:
                avg_comp = df_type['CompressionThroughput_GBps'].mean()
                avg_decomp = df_type['DecompressionThroughput_GBps'].mean()
                
                fig.add_trace(
                    go.Bar(
                        x=['Compression', 'Decompression'],
                        y=[avg_comp, avg_decomp],
                        name=feat,
                        marker_color=FEATURE_COLORS.get(feat, '#85929E'),
                        text=[f'{avg_comp:.1f}', f'{avg_decomp:.1f}'],
                        textposition='outside',
                        legendgroup=feat,
                        showlegend=(dtype == 'Binary')
                    ),
                    row=row, col=col
                )
        
        fig.update_yaxes(title_text="Throughput (GB/s)", row=row, col=col)
    
    fig.update_layout(
        height=1000,
        width=1600,
        title_text="MI300X GPU: Performance by Data Type Across Features<br>"
                   "<sub>Average throughput for each data category</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / '05_data_type_performance.png'
    fig.write_image(str(output_file), width=1920, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_algorithm_winner_analysis(features_data, output_dir):
    """
    Analyze which feature wins for each algorithm.
    """
    print("\n[6/8] Gerando Algorithm Winner Analysis...")
    
    feature_names = list(features_data.keys())
    algorithms = sorted(features_data[feature_names[0]]['Algorithm'].unique())
    
    fig = make_subplots(
        rows=1, cols=3,
        subplot_titles=[f'{algo.upper()}' for algo in algorithms],
        horizontal_spacing=0.10
    )
    
    metrics = ['Compression', 'Decompression', 'Ratio']
    
    for col_idx, algo in enumerate(algorithms, 1):
        for metric in metrics:
            values = []
            
            for feat in feature_names:
                algo_data = features_data[feat][features_data[feat]['Algorithm'] == algo]
                
                if metric == 'Compression':
                    val = algo_data['CompressionThroughput_GBps'].mean()
                elif metric == 'Decompression':
                    val = algo_data['DecompressionThroughput_GBps'].mean()
                else:  # Ratio
                    val = algo_data['CompressionRatio'].mean()
                
                values.append(val)
            
            fig.add_trace(
                go.Bar(
                    x=feature_names,
                    y=values,
                    name=metric,
                    text=[f'{v:.1f}' for v in values],
                    textposition='outside',
                    showlegend=(col_idx == 1)
                ),
                row=1, col=col_idx
            )
        
        fig.update_xaxes(tickangle=45, row=1, col=col_idx)
        fig.update_yaxes(title_text="Value", row=1, col=col_idx)
    
    fig.update_layout(
        height=700,
        width=1800,
        title_text="MI300X GPU: Best Feature Analysis per Algorithm<br>"
                   "<sub>Compression/Decompression in GB/s, Ratio is compression ratio</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / '06_algorithm_winner_analysis.png'
    fig.write_image(str(output_file), width=2160, height=840, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_effectiveness_radar(features_data, output_dir):
    """
    Radar chart comparing overall effectiveness of features.
    """
    print("\n[7/8] Gerando Effectiveness Radar...")
    
    feature_names = list(features_data.keys())
    
    fig = go.Figure()
    
    categories = ['Comp Speed', 'Decomp Speed', 'Comp Ratio', 
                  'TTI Performance', 'Binary Performance', 'Consistency']
    
    for feat in feature_names:
        df = features_data[feat]
        
        # Normalize to 0-100
        all_comp = pd.concat([features_data[f]['CompressionThroughput_GBps'] for f in feature_names])
        all_decomp = pd.concat([features_data[f]['DecompressionThroughput_GBps'] for f in feature_names])
        all_ratio = pd.concat([features_data[f]['CompressionRatio'] for f in feature_names])
        
        values = [
            (df['CompressionThroughput_GBps'].mean() / all_comp.max()) * 100,
            (df['DecompressionThroughput_GBps'].mean() / all_decomp.max()) * 100,
            (df['CompressionRatio'].mean() / all_ratio.max()) * 100,
            (df[df['DataType'] == 'TTI']['CompressionThroughput_GBps'].mean() / 
             all_comp.max()) * 100 if len(df[df['DataType'] == 'TTI']) > 0 else 50,
            (df[df['DataType'] == 'Binary']['CompressionThroughput_GBps'].mean() / 
             all_comp.max()) * 100 if len(df[df['DataType'] == 'Binary']) > 0 else 50,
            100 - (df['CompressionThroughput_GBps'].std() / df['CompressionThroughput_GBps'].mean()) * 50
        ]
        values.append(values[0])  # Close the polygon
        
        fig.add_trace(
            go.Scatterpolar(
                r=values,
                theta=categories + [categories[0]],
                fill='toself',
                name=feat,
                line=dict(color=FEATURE_COLORS.get(feat, '#85929E'), width=3),
                opacity=0.6
            )
        )
    
    fig.update_layout(
        height=800,
        width=1000,
        title_text="MI300X GPU: Feature Effectiveness Radar<br>"
                   "<sub>Normalized performance across key metrics</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=12),
        polar=dict(radialaxis=dict(visible=True, range=[0, 100]))
    )
    
    output_file = output_dir / '07_effectiveness_radar.png'
    fig.write_image(str(output_file), width=1200, height=960, scale=2)
    print(f"  ✓ {output_file.name}")

def plot_recommendation_matrix(features_data, output_dir):
    """
    Decision matrix: which feature to use for different scenarios.
    """
    print("\n[8/8] Gerando Recommendation Matrix...")
    
    feature_names = list(features_data.keys())
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Best Feature for Max Compression Speed',
            'Best Feature for Max Decompression Speed',
            'Best Feature for Best Compression Ratio',
            'Feature Recommendation Summary'
        ),
        specs=[[{"type": "bar"}, {"type": "bar"}],
               [{"type": "bar"}, {"type": "table"}]],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    scenarios = ['Small Files', 'Medium Files', 'Large Files', 'TTI Data', 'Binary Data']
    
    # 1. Best for compression speed
    best_comp = []
    for scenario in scenarios:
        best_feat = None
        best_val = 0
        
        for feat in feature_names:
            df = features_data[feat]
            
            if 'Small' in scenario:
                val = df[df['SizeCategory'] == 'Small']['CompressionThroughput_GBps'].mean()
            elif 'Medium' in scenario:
                val = df[df['SizeCategory'] == 'Medium']['CompressionThroughput_GBps'].mean()
            elif 'Large' in scenario:
                val = df[df['SizeCategory'].isin(['Large', 'XLarge'])]['CompressionThroughput_GBps'].mean()
            elif 'TTI' in scenario:
                val = df[df['DataType'] == 'TTI']['CompressionThroughput_GBps'].mean()
            else:  # Binary
                val = df[df['DataType'] == 'Binary']['CompressionThroughput_GBps'].mean()
            
            if val > best_val:
                best_val = val
                best_feat = feat
        
        best_comp.append((best_feat, best_val))
    
    fig.add_trace(
        go.Bar(
            x=scenarios,
            y=[v for _, v in best_comp],
            marker_color=[FEATURE_COLORS.get(f, '#85929E') for f, _ in best_comp],
            text=[f'{f}<br>{v:.1f} GB/s' for f, v in best_comp],
            textposition='outside'
        ),
        row=1, col=1
    )
    
    # 2. Best for decompression speed
    best_decomp = []
    for scenario in scenarios:
        best_feat = None
        best_val = 0
        
        for feat in feature_names:
            df = features_data[feat]
            
            if 'Small' in scenario:
                val = df[df['SizeCategory'] == 'Small']['DecompressionThroughput_GBps'].mean()
            elif 'Medium' in scenario:
                val = df[df['SizeCategory'] == 'Medium']['DecompressionThroughput_GBps'].mean()
            elif 'Large' in scenario:
                val = df[df['SizeCategory'].isin(['Large', 'XLarge'])]['DecompressionThroughput_GBps'].mean()
            elif 'TTI' in scenario:
                val = df[df['DataType'] == 'TTI']['DecompressionThroughput_GBps'].mean()
            else:  # Binary
                val = df[df['DataType'] == 'Binary']['DecompressionThroughput_GBps'].mean()
            
            if val > best_val:
                best_val = val
                best_feat = feat
        
        best_decomp.append((best_feat, best_val))
    
    fig.add_trace(
        go.Bar(
            x=scenarios,
            y=[v for _, v in best_decomp],
            marker_color=[FEATURE_COLORS.get(f, '#85929E') for f, _ in best_decomp],
            text=[f'{f}<br>{v:.1f} GB/s' for f, v in best_decomp],
            textposition='outside'
        ),
        row=1, col=2
    )
    
    # 3. Best for compression ratio
    best_ratio = []
    for scenario in scenarios:
        best_feat = None
        best_val = 0
        
        for feat in feature_names:
            df = features_data[feat]
            
            if 'Small' in scenario:
                val = df[df['SizeCategory'] == 'Small']['CompressionRatio'].mean()
            elif 'Medium' in scenario:
                val = df[df['SizeCategory'] == 'Medium']['CompressionRatio'].mean()
            elif 'Large' in scenario:
                val = df[df['SizeCategory'].isin(['Large', 'XLarge'])]['CompressionRatio'].mean()
            elif 'TTI' in scenario:
                val = df[df['DataType'] == 'TTI']['CompressionRatio'].mean()
            else:  # Binary
                val = df[df['DataType'] == 'Binary']['CompressionRatio'].mean()
            
            if val > best_val:
                best_val = val
                best_feat = feat
        
        best_ratio.append((best_feat, best_val))
    
    fig.add_trace(
        go.Bar(
            x=scenarios,
            y=[v for _, v in best_ratio],
            marker_color=[FEATURE_COLORS.get(f, '#85929E') for f, _ in best_ratio],
            text=[f'{f}<br>{v:.1f}x' for f, v in best_ratio],
            textposition='outside'
        ),
        row=2, col=1
    )
    
    # 4. Summary table
    recommendations = []
    for scenario in scenarios:
        comp_winner = best_comp[scenarios.index(scenario)][0]
        decomp_winner = best_decomp[scenarios.index(scenario)][0]
        ratio_winner = best_ratio[scenarios.index(scenario)][0]
        
        # Most common winner
        from collections import Counter
        counter = Counter([comp_winner, decomp_winner, ratio_winner])
        overall = counter.most_common(1)[0][0]
        
        recommendations.append([scenario, overall, comp_winner, decomp_winner, ratio_winner])
    
    table_data = list(zip(*recommendations))
    
    fig.add_trace(
        go.Table(
            header=dict(
                values=['<b>Scenario</b>', '<b>Overall Best</b>', 
                       '<b>Best Comp</b>', '<b>Best Decomp</b>', '<b>Best Ratio</b>'],
                fill_color='#5DADE2',
                font=dict(color='white', size=11),
                align='left'
            ),
            cells=dict(
                values=table_data,
                fill_color='#F8F9F9',
                font=dict(size=10),
                align='left',
                height=30
            )
        ),
        row=2, col=2
    )
    
    fig.update_xaxes(tickangle=45, row=1, col=1)
    fig.update_xaxes(tickangle=45, row=1, col=2)
    fig.update_xaxes(tickangle=45, row=2, col=1)
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Compression Ratio", row=2, col=1)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="MI300X GPU: Feature Recommendation Matrix<br>"
                   "<sub>Best feature for different use cases</sub>",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=10)
    )
    
    output_file = output_dir / '08_recommendation_matrix.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def generate_summary_report(features_data, output_dir):
    """Generate comprehensive text report."""
    report = []
    report.append("=" * 100)
    report.append("MI300X GPU - FEATURE COMPARISON ANALYSIS (Features 2-5)")
    report.append("=" * 100)
    report.append("")
    
    feature_names = list(features_data.keys())
    
    report.append("EXECUTIVE SUMMARY")
    report.append("-" * 100)
    report.append(f"Features compared: {', '.join(feature_names)}")
    report.append(f"Total tests per feature: {len(features_data[feature_names[0]])}")
    report.append("")
    
    # Overall rankings
    report.append("OVERALL PERFORMANCE RANKINGS")
    report.append("-" * 100)
    
    # Compression speed
    report.append("\nAverage Compression Speed:")
    comp_ranking = {}
    for feat in feature_names:
        comp_ranking[feat] = features_data[feat]['CompressionThroughput_GBps'].mean()
    
    for i, (feat, val) in enumerate(sorted(comp_ranking.items(), key=lambda x: x[1], reverse=True), 1):
        report.append(f"  {i}. {feat:30s} {val:8.2f} GB/s")
    
    # Decompression speed
    report.append("\nAverage Decompression Speed:")
    decomp_ranking = {}
    for feat in feature_names:
        decomp_ranking[feat] = features_data[feat]['DecompressionThroughput_GBps'].mean()
    
    for i, (feat, val) in enumerate(sorted(decomp_ranking.items(), key=lambda x: x[1], reverse=True), 1):
        report.append(f"  {i}. {feat:30s} {val:8.2f} GB/s")
    
    # Compression ratio
    report.append("\nAverage Compression Ratio:")
    ratio_ranking = {}
    for feat in feature_names:
        ratio_ranking[feat] = features_data[feat]['CompressionRatio'].mean()
    
    for i, (feat, val) in enumerate(sorted(ratio_ranking.items(), key=lambda x: x[1], reverse=True), 1):
        report.append(f"  {i}. {feat:30s} {val:8.2f}x")
    
    # TTI Seismic Performance
    report.append("\n")
    report.append("TTI SEISMIC DATA PERFORMANCE")
    report.append("-" * 100)
    
    for feat in feature_names:
        tti_data = features_data[feat][features_data[feat]['DataType'] == 'TTI']
        if len(tti_data) > 0:
            report.append(f"\n{feat}:")
            report.append(f"  Compression:   {tti_data['CompressionThroughput_GBps'].mean():8.2f} GB/s")
            report.append(f"  Decompression: {tti_data['DecompressionThroughput_GBps'].mean():8.2f} GB/s")
            report.append(f"  Ratio:         {tti_data['CompressionRatio'].mean():8.2f}x")
    
    report.append("")
    report.append("=" * 100)
    
    # Save report
    report_text = "\n".join(report)
    report_file = output_dir / 'mi300x_feature_comparison_report.txt'
    with open(report_file, 'w') as f:
        f.write(report_text)
    
    print(f"\n✓ Generated: {report_file.name}")
    print("\n" + report_text)

def main():
    if len(sys.argv) < 3:
        print("Usage: python compare_features_mi300x.py <feature2_dir> <feature3_dir> [<feature4_dir>] [<feature5_dir>]")
        print("\nExample:")
        print("  python compare_features_mi300x.py \\")
        print("    results/feature2_wave64_mi300x/20251204_231325_0027c79 \\")
        print("    results/feature3_lds_mi300x/20251205_003634_9b15b5f \\")
        print("    results/feature4_mi300x/20251204_235428_2bcc390 \\")
        print("    results/feature5_instructions_mi300x/20251205_002150_5923a6f")
        sys.exit(1)
    
    print("\n" + "=" * 100)
    print("MI300X GPU - FEATURE COMPARISON VISUALIZATION")
    print("=" * 100)
    
    # Load all features
    features_data = {}
    feature_labels = {
        2: 'Feature 2 (Wave64)',
        3: 'Feature 3 (LDS)',
        4: 'Feature 4',
        5: 'Feature 5 (Instructions)'
    }
    
    for i, feature_path in enumerate(sys.argv[1:], 2):
        label = feature_labels.get(i, f'Feature {i}')
        print(f"\nLoading {label}: {feature_path}")
        try:
            df = load_feature_results(feature_path)
            features_data[label] = df
            print(f"  ✓ Loaded {len(df)} tests")
        except Exception as e:
            print(f"  ✗ Error: {e}")
            sys.exit(1)
    
    # Create output directory
    output_dir = Path('mi300x_comparison_output')
    output_dir.mkdir(exist_ok=True)
    
    print(f"\nGenerating visualizations in: {output_dir}")
    print("=" * 100)
    
    # Generate all visualizations
    plot_feature_comparison_overview(features_data, output_dir)
    plot_improvement_heatmap(features_data, list(features_data.keys())[0], output_dir)
    plot_tti_seismic_comparison(features_data, output_dir)
    plot_scalability_comparison(features_data, output_dir)
    plot_data_type_performance(features_data, output_dir)
    plot_algorithm_winner_analysis(features_data, output_dir)
    plot_effectiveness_radar(features_data, output_dir)
    plot_recommendation_matrix(features_data, output_dir)
    
    # Generate report
    print("\n" + "=" * 100)
    print("Generating comprehensive analysis report...")
    print("=" * 100)
    generate_summary_report(features_data, output_dir)
    
    # Summary
    print("\n" + "=" * 100)
    print("✅ COMPLETE! All visualizations generated successfully")
    print("=" * 100)
    print("\nGenerated files:")
    for i, f in enumerate(sorted(output_dir.glob('*.png')), 1):
        print(f"  {i:2d}. {f.name}")
    print(f"   9. mi300x_feature_comparison_report.txt")
    print(f"\n📁 Location: {output_dir.absolute()}")
    print("=" * 100 + "\n")

if __name__ == '__main__':
    main()
