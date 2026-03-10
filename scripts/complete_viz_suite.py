#!/usr/bin/env python3
"""
Feature 2 Wave64 - Complete Advanced Visualization Suite

Generates 10 strategic visualizations that extract maximum insights from benchmark data:
1. Heatmap de Performance
2. Pareto Front (Speed vs Ratio)
3. Scalability Curves
4. Efficiency Ratio (Comp/Decomp)
5. Compression Effectiveness (composite metric)
6. Small File Penalty
7. Data Type Sensitivity
8. TTI-Specific Spotlight
9. Bandwidth Utilization
10. Decision Flowchart
"""

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import numpy as np
from pathlib import Path
import sys

def load_and_prepare_data(csv_path):
    """Load and enrich benchmark data."""
    df = pd.read_csv(csv_path)
    
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
    
    def get_size_order(cat):
        order = {'Small': 1, 'Medium': 2, 'Large': 3, 'XLarge': 4}
        return order.get(cat, 0)
    
    df['SizeCategory'] = df['TestFile'].apply(get_size_category)
    df['DataType'] = df['TestFile'].apply(get_data_type)
    df['SizeMB'] = df['FileSize'] / (1024 * 1024)
    df['SizeGB'] = df['FileSize'] / (1024 * 1024 * 1024)
    df['SizeOrder'] = df['SizeCategory'].apply(get_size_order)
    
    # Derived metrics
    df['EfficiencyRatio'] = df['CompressionThroughput_GBps'] / df['DecompressionThroughput_GBps']
    df['Effectiveness'] = df['CompressionThroughput_GBps'] * np.log2(df['CompressionRatio'] + 1)
    df['TotalThroughput'] = df['CompressionThroughput_GBps'] + df['DecompressionThroughput_GBps']
    
    return df

# Color schemes - Light and modern palette
COLORS = {
    'lz4': '#5DADE2',      # Light blue
    'snappy': '#EC7063',   # Light red/coral
    'cascaded': '#58D68D'  # Light green
}

SYMBOLS = {
    'TTI': 'circle',
    'Binary': 'square',
    'Random': 'diamond',
    'Zeros': 'triangle-up'
}

def viz_01_heatmap_performance(df, output_dir):
    """
    1. HEATMAP DE PERFORMANCE
    Matriz algoritmo × tipo de dado, mostrando throughput médio de compressão.
    """
    print("\n[1/10] Gerando Heatmap de Performance...")
    
    # Create separate heatmaps for compression, decompression, and ratio
    fig = make_subplots(
        rows=1, cols=3,
        subplot_titles=('Compression Speed (GB/s)', 'Decompression Speed (GB/s)', 'Compression Ratio'),
        horizontal_spacing=0.12
    )
    
    algos = sorted(df['Algorithm'].unique())
    dtypes = sorted(df['DataType'].unique())
    
    # Compression heatmap
    comp_matrix = []
    for algo in algos:
        row = []
        for dtype in dtypes:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            row.append(subset['CompressionThroughput_GBps'].mean() if len(subset) > 0 else 0)
        comp_matrix.append(row)
    
    fig.add_trace(
        go.Heatmap(
            z=comp_matrix,
            x=dtypes,
            y=[a.upper() for a in algos],
            colorscale='Teal',
            text=[[f'{v:.1f}' for v in row] for row in comp_matrix],
            texttemplate='%{text}',
            textfont={"size": 18},
            colorbar=dict(title="GB/s", x=0.255)
        ),
        row=1, col=1
    )
    
    # Decompression heatmap
    decomp_matrix = []
    for algo in algos:
        row = []
        for dtype in dtypes:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            row.append(subset['DecompressionThroughput_GBps'].mean() if len(subset) > 0 else 0)
        decomp_matrix.append(row)
    
    fig.add_trace(
        go.Heatmap(
            z=decomp_matrix,
            x=dtypes,
            y=[a.upper() for a in algos],
            colorscale='Peach',
            text=[[f'{v:.1f}' for v in row] for row in decomp_matrix],
            texttemplate='%{text}',
            textfont={"size": 18},
            colorbar=dict(title="GB/s", x=0.627)
        ),
        row=1, col=2
    )
    
    # Ratio heatmap
    ratio_matrix = []
    for algo in algos:
        row = []
        for dtype in dtypes:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            row.append(subset['CompressionRatio'].mean() if len(subset) > 0 else 0)
        ratio_matrix.append(row)
    
    fig.add_trace(
        go.Heatmap(
            z=ratio_matrix,
            x=dtypes,
            y=[a.upper() for a in algos],
            colorscale='Mint',
            text=[[f'{v:.1f}x' for v in row] for row in ratio_matrix],
            texttemplate='%{text}',
            textfont={"size": 18},
            colorbar=dict(title="Ratio", x=1.0)
        ),
        row=1, col=3
    )
    
    fig.update_layout(
        height=500,
        width=1800,
        title_text="Performance Heatmap: Algorithm × Data Type (Average across all sizes)",
        title_font_size=22,
        template='plotly_white',
        font=dict(size=18)
    )
    
    output_file = output_dir / 'viz_01_heatmap_performance.png'
    fig.write_image(str(output_file), width=2160, height=600, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_02_pareto_front(df, output_dir):
    """
    2. PARETO FRONT (Speed vs Ratio)
    Mostra o trade-off fundamental entre velocidade e eficiência.
    """
    print("\n[2/10] Gerando Pareto Front...")
    
    fig = go.Figure()
    
    for algo in sorted(df['Algorithm'].unique()):
        for dtype in sorted(df['DataType'].unique()):
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            
            if len(subset) > 0:
                fig.add_trace(
                    go.Scatter(
                        x=subset['CompressionThroughput_GBps'],
                        y=subset['CompressionRatio'],
                        mode='markers',
                        name=f'{algo.upper()}-{dtype}',
                        marker=dict(
                            size=np.sqrt(subset['SizeMB']) * 1.5,
                            color=COLORS.get(algo, '#85929E'),
                            symbol=SYMBOLS.get(dtype, 'circle'),
                            opacity=0.7,
                            line=dict(width=1, color='white')
                        ),
                        text=[f'<b>{algo.upper()}</b><br>{dtype}<br>{size:.0f}MB<br>'
                              f'Speed: {comp:.1f} GB/s<br>Ratio: {ratio:.1f}x'
                              for size, comp, ratio in zip(subset['SizeMB'], 
                                                          subset['CompressionThroughput_GBps'],
                                                          subset['CompressionRatio'])],
                        hovertemplate='%{text}<extra></extra>',
                        legendgroup=algo,
                        showlegend=(dtype == 'Binary')
                    )
                )
    
    # Add Pareto frontier line
    pareto_points = []
    for _, row in df.iterrows():
        is_pareto = True
        for _, other in df.iterrows():
            if (other['CompressionThroughput_GBps'] > row['CompressionThroughput_GBps'] and 
                other['CompressionRatio'] > row['CompressionRatio']):
                is_pareto = False
                break
        if is_pareto:
            pareto_points.append(row)
    
    if pareto_points:
        pareto_df = pd.DataFrame(pareto_points).sort_values('CompressionThroughput_GBps')
        fig.add_trace(
            go.Scatter(
                x=pareto_df['CompressionThroughput_GBps'],
                y=pareto_df['CompressionRatio'],
                mode='lines',
                name='Pareto Frontier',
                line=dict(color='black', width=2, dash='dash'),
                showlegend=True
            )
        )
    
    fig.update_layout(
        height=700,
        width=1400,
        title_text="Pareto Front: Compression Speed vs Compression Ratio Trade-off<br>"
                   "<sub>Bubble size = file size | Pareto frontier = non-dominated solutions</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=12),
        xaxis=dict(title='Compression Throughput (GB/s)', type='log'),
        yaxis=dict(title='Compression Ratio', type='log'),
        hovermode='closest'
    )
    
    output_file = output_dir / 'viz_02_pareto_front.png'
    fig.write_image(str(output_file), width=1680, height=840, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_03_scalability_curves(df, output_dir):
    """
    3. SCALABILITY CURVES
    Como o throughput muda com o tamanho do arquivo.
    """
    print("\n[3/10] Gerando Scalability Curves...")
    
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Compression Scalability', 'Decompression Scalability'),
        horizontal_spacing=0.12
    )
    
    for algo in sorted(df['Algorithm'].unique()):
        for dtype in sorted(df['DataType'].unique()):
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)].sort_values('SizeMB')
            
            if len(subset) > 1:
                # Compression
                fig.add_trace(
                    go.Scatter(
                        x=subset['SizeMB'],
                        y=subset['CompressionThroughput_GBps'],
                        mode='lines+markers',
                        name=f'{algo.upper()}-{dtype}',
                        line=dict(color=COLORS.get(algo, '#85929E'), 
                                 width=2 if dtype == 'TTI' else 1.5,
                                 dash='solid' if dtype == 'TTI' else 'dot'),
                        marker=dict(size=8, symbol=SYMBOLS.get(dtype, 'circle')),
                        legendgroup=algo,
                        showlegend=(dtype == 'TTI')
                    ),
                    row=1, col=1
                )
                
                # Decompression
                fig.add_trace(
                    go.Scatter(
                        x=subset['SizeMB'],
                        y=subset['DecompressionThroughput_GBps'],
                        mode='lines+markers',
                        name=f'{algo.upper()}-{dtype}',
                        line=dict(color=COLORS.get(algo, '#85929E'), 
                                 width=2 if dtype == 'TTI' else 1.5,
                                 dash='solid' if dtype == 'TTI' else 'dot'),
                        marker=dict(size=8, symbol=SYMBOLS.get(dtype, 'circle')),
                        legendgroup=algo,
                        showlegend=False
                    ),
                    row=1, col=2
                )
    
    fig.update_xaxes(title_text="File Size (MB)", type='log', row=1, col=1)
    fig.update_xaxes(title_text="File Size (MB)", type='log', row=1, col=2)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text="Scalability Analysis: Performance vs File Size<br>"
                   "<sub>Solid lines = TTI data | Dotted = synthetic data</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=11)
    )
    
    output_file = output_dir / 'viz_03_scalability_curves.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_04_efficiency_ratio(df, output_dir):
    """
    4. EFFICIENCY RATIO (Comp/Decomp)
    Mostra se algoritmos são simétricos ou assimétricos.
    """
    print("\n[4/10] Gerando Efficiency Ratio...")
    
    fig = go.Figure()
    
    algos = sorted(df['Algorithm'].unique())
    dtypes = sorted(df['DataType'].unique())
    
    x_pos = 0
    x_labels = []
    x_positions = []
    
    for dtype in dtypes:
        for algo in algos:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            
            if len(subset) > 0:
                ratio = subset['EfficiencyRatio'].mean()
                
                fig.add_trace(
                    go.Bar(
                        x=[x_pos],
                        y=[ratio],
                        name=algo.upper(),
                        marker_color=COLORS.get(algo, '#85929E'),
                        text=f'{ratio:.2f}',
                        textposition='outside',
                        legendgroup=algo,
                        showlegend=(dtype == dtypes[0])
                    )
                )
                
                x_labels.append(f'{algo.upper()}')
                x_positions.append(x_pos)
                x_pos += 1
        
        x_pos += 0.5  # Gap between data types
    
    # Add reference line at 1.0 (symmetric)
    fig.add_hline(y=1.0, line_dash="dash", line_color="#95A5A6", 
                  annotation_text="Symmetric (1.0)", annotation_position="right")
    
    # Add data type separators
    separators = []
    pos = 0
    for i, dtype in enumerate(dtypes):
        n_algos = len(algos)
        if i > 0:
            separators.append(pos - 0.25)
        pos += n_algos + 0.5
    
    for sep in separators:
        fig.add_vline(x=sep, line_dash="dot", line_color="#D5D8DC")
    
    # Add data type labels
    pos = 0
    for dtype in dtypes:
        n_algos = len(algos)
        center = pos + (n_algos - 1) / 2
        fig.add_annotation(
            x=center,
            y=-0.3,
            text=f'<b>{dtype}</b>',
            showarrow=False,
            yref='paper',
            font=dict(size=12)
        )
        pos += n_algos + 0.5
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text="Compression/Decompression Speed Ratio by Algorithm and Data Type<br>"
                   "<sub>Ratio > 1: Compression faster | Ratio < 1: Decompression faster</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=11),
        xaxis=dict(tickmode='array', tickvals=x_positions, ticktext=x_labels, tickangle=45),
        yaxis=dict(title='Compression Speed / Decompression Speed'),
        barmode='group',
        showlegend=True
    )
    
    output_file = output_dir / 'viz_04_efficiency_ratio.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_05_compression_effectiveness(df, output_dir):
    """
    5. COMPRESSION EFFECTIVENESS (composite metric)
    Speed × log(Ratio) = valor holístico.
    """
    print("\n[5/10] Gerando Compression Effectiveness...")
    
    fig = go.Figure()
    
    algos = sorted(df['Algorithm'].unique())
    dtypes = sorted(df['DataType'].unique())
    
    for algo in algos:
        values = []
        labels = []
        
        for dtype in dtypes:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            if len(subset) > 0:
                effectiveness = subset['Effectiveness'].mean()
                values.append(effectiveness)
                labels.append(dtype)
        
        fig.add_trace(
            go.Bar(
                x=labels,
                y=values,
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}' for v in values],
                textposition='outside'
            )
        )
    
    fig.update_layout(
        height=600,
        width=1400,
        title_text="Compression Effectiveness: Speed × log₂(Ratio + 1)<br>"
                   "<sub>Higher = better overall value (balances speed and compression)</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=12),
        xaxis=dict(title='Data Type'),
        yaxis=dict(title='Effectiveness Score'),
        barmode='group'
    )
    
    output_file = output_dir / 'viz_05_compression_effectiveness.png'
    fig.write_image(str(output_file), width=1680, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_06_small_file_penalty(df, output_dir):
    """
    6. SMALL FILE PENALTY
    Quanto se perde com arquivos pequenos vs grandes.
    """
    print("\n[6/10] Gerando Small File Penalty...")
    
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Compression Performance Degradation', 'Decompression Performance Degradation'),
        horizontal_spacing=0.12
    )
    
    algos = sorted(df['Algorithm'].unique())
    dtypes = sorted(df['DataType'].unique())
    
    for algo in algos:
        comp_penalties = []
        decomp_penalties = []
        labels = []
        
        for dtype in dtypes:
            small = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype) & (df['SizeCategory'] == 'Small')]
            large = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype) & 
                      ((df['SizeCategory'] == 'Large') | (df['SizeCategory'] == 'XLarge'))]
            
            if len(small) > 0 and len(large) > 0:
                comp_penalty = (1 - small['CompressionThroughput_GBps'].mean() / large['CompressionThroughput_GBps'].mean()) * 100
                decomp_penalty = (1 - small['DecompressionThroughput_GBps'].mean() / large['DecompressionThroughput_GBps'].mean()) * 100
                
                comp_penalties.append(comp_penalty)
                decomp_penalties.append(decomp_penalty)
                labels.append(dtype)
        
        fig.add_trace(
            go.Bar(
                x=labels,
                y=comp_penalties,
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}%' for v in comp_penalties],
                textposition='outside'
            ),
            row=1, col=1
        )
        
        fig.add_trace(
            go.Bar(
                x=labels,
                y=decomp_penalties,
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}%' for v in decomp_penalties],
                textposition='outside',
                showlegend=False
            ),
            row=1, col=2
        )
    
    fig.update_xaxes(title_text="Data Type", row=1, col=1)
    fig.update_xaxes(title_text="Data Type", row=1, col=2)
    fig.update_yaxes(title_text="Performance Loss (%)", row=1, col=1)
    fig.update_yaxes(title_text="Performance Loss (%)", row=1, col=2)
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text="Small File Penalty: Performance Loss (Small 10MB vs Large/XLarge)<br>"
                   "<sub>Higher = more overhead with small files</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / 'viz_06_small_file_penalty.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_07_data_type_sensitivity(df, output_dir):
    """
    7. DATA TYPE SENSITIVITY
    Box plots mostrando variância através de tipos de dados.
    """
    print("\n[7/10] Gerando Data Type Sensitivity...")
    
    fig = make_subplots(
        rows=1, cols=3,
        subplot_titles=('Compression Speed Stability', 'Decompression Speed Stability', 'Compression Ratio Stability'),
        horizontal_spacing=0.10
    )
    
    algos = sorted(df['Algorithm'].unique())
    
    for algo in algos:
        algo_data = df[df['Algorithm'] == algo]
        
        fig.add_trace(
            go.Box(
                y=algo_data['CompressionThroughput_GBps'],
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                boxmean='sd'
            ),
            row=1, col=1
        )
        
        fig.add_trace(
            go.Box(
                y=algo_data['DecompressionThroughput_GBps'],
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                boxmean='sd',
                showlegend=False
            ),
            row=1, col=2
        )
        
        fig.add_trace(
            go.Box(
                y=algo_data['CompressionRatio'],
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                boxmean='sd',
                showlegend=False
            ),
            row=1, col=3
        )
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Compression Ratio", type='log', row=1, col=3)
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text="Performance Stability Across All Data Types and Sizes<br>"
                   "<sub>Box = IQR | Line = median | Diamond = mean ± std</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=11)
    )
    
    output_file = output_dir / 'viz_07_data_type_sensitivity.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_08_tti_spotlight(df, output_dir):
    """
    8. TTI-SPECIFIC SPOTLIGHT
    Análise profunda APENAS dos dados TTI seismic.
    """
    print("\n[8/10] Gerando TTI Spotlight...")
    
    tti_data = df[df['DataType'] == 'TTI'].copy()
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'TTI: Compression Performance by Size',
            'TTI: Decompression Performance by Size',
            'TTI: Compression Ratio by Size',
            'TTI: Total Throughput (Comp + Decomp)'
        ),
        vertical_spacing=0.12,
        horizontal_spacing=0.12
    )
    
    algos = sorted(tti_data['Algorithm'].unique())
    sizes = sorted(tti_data['SizeCategory'].unique(), 
                  key=lambda x: tti_data[tti_data['SizeCategory']==x]['SizeOrder'].iloc[0])
    
    # 1. Compression
    for algo in algos:
        algo_tti = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Scatter(
                x=algo_tti['SizeCategory'],
                y=algo_tti['CompressionThroughput_GBps'],
                mode='lines+markers',
                name=algo.upper(),
                line=dict(color=COLORS.get(algo, '#85929E'), width=3),
                marker=dict(size=12),
                text=[f'{v:.1f} GB/s' for v in algo_tti['CompressionThroughput_GBps']],
                textposition='top center'
            ),
            row=1, col=1
        )
    
    # 2. Decompression
    for algo in algos:
        algo_tti = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Scatter(
                x=algo_tti['SizeCategory'],
                y=algo_tti['DecompressionThroughput_GBps'],
                mode='lines+markers',
                name=algo.upper(),
                line=dict(color=COLORS.get(algo, '#85929E'), width=3),
                marker=dict(size=12, symbol='square'),
                text=[f'{v:.1f} GB/s' for v in algo_tti['DecompressionThroughput_GBps']],
                textposition='top center',
                showlegend=False
            ),
            row=1, col=2
        )
    
    # 3. Ratio
    for algo in algos:
        algo_tti = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Bar(
                x=algo_tti['SizeCategory'],
                y=algo_tti['CompressionRatio'],
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}x' for v in algo_tti['CompressionRatio']],
                textposition='outside',
                showlegend=False
            ),
            row=2, col=1
        )
    
    # 4. Total throughput
    for algo in algos:
        algo_tti = tti_data[tti_data['Algorithm'] == algo].sort_values('SizeOrder')
        fig.add_trace(
            go.Bar(
                x=algo_tti['SizeCategory'],
                y=algo_tti['TotalThroughput'],
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}' for v in algo_tti['TotalThroughput']],
                textposition='outside',
                showlegend=False
            ),
            row=2, col=2
        )
    
    fig.update_xaxes(title_text="File Size", row=1, col=1, categoryorder='array', categoryarray=sizes)
    fig.update_xaxes(title_text="File Size", row=1, col=2, categoryorder='array', categoryarray=sizes)
    fig.update_xaxes(title_text="File Size", row=2, col=1, categoryorder='array', categoryarray=sizes)
    fig.update_xaxes(title_text="File Size", row=2, col=2, categoryorder='array', categoryarray=sizes)
    
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=1)
    fig.update_yaxes(title_text="Throughput (GB/s)", row=1, col=2)
    fig.update_yaxes(title_text="Compression Ratio", row=2, col=1)
    fig.update_yaxes(title_text="Total Throughput (GB/s)", row=2, col=2)
    
    fig.update_layout(
        height=1000,
        width=1600,
        title_text="TTI Seismic Data Deep Dive: Complete Performance Analysis<br>"
                   "<sub>Focus on real-world seismic data performance</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / 'viz_08_tti_spotlight.png'
    fig.write_image(str(output_file), width=1920, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_09_bandwidth_utilization(df, output_dir):
    """
    9. BANDWIDTH UTILIZATION
    % da bandwidth teórica da GPU (assumindo ~900 GB/s peak para MI250X).
    """
    print("\n[9/10] Gerando Bandwidth Utilization...")
    
    # MI250X theoretical peak: ~1.6 TB/s (bidirectional), ~900 GB/s (unidirectional)
    PEAK_BANDWIDTH_GBps = 900
    
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=('Compression Bandwidth Utilization', 'Decompression Bandwidth Utilization'),
        horizontal_spacing=0.12
    )
    
    algos = sorted(df['Algorithm'].unique())
    dtypes = sorted(df['DataType'].unique())
    
    for algo in algos:
        comp_util = []
        decomp_util = []
        labels = []
        
        for dtype in dtypes:
            subset = df[(df['Algorithm'] == algo) & (df['DataType'] == dtype)]
            if len(subset) > 0:
                comp_util.append((subset['CompressionThroughput_GBps'].max() / PEAK_BANDWIDTH_GBps) * 100)
                decomp_util.append((subset['DecompressionThroughput_GBps'].max() / PEAK_BANDWIDTH_GBps) * 100)
                labels.append(dtype)
        
        fig.add_trace(
            go.Bar(
                x=labels,
                y=comp_util,
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}%' for v in comp_util],
                textposition='outside'
            ),
            row=1, col=1
        )
        
        fig.add_trace(
            go.Bar(
                x=labels,
                y=decomp_util,
                name=algo.upper(),
                marker_color=COLORS.get(algo, '#85929E'),
                text=[f'{v:.1f}%' for v in decomp_util],
                textposition='outside',
                showlegend=False
            ),
            row=1, col=2
        )
    
    # Add reference lines
    fig.add_hline(y=50, line_dash="dash", line_color="#F8B739", row=1, col=1,
                  annotation_text="50% (compute-bound)", annotation_position="right")
    fig.add_hline(y=80, line_dash="dash", line_color="#EC7063", row=1, col=1,
                  annotation_text="80% (near peak)", annotation_position="right")
    fig.add_hline(y=50, line_dash="dash", line_color="#F8B739", row=1, col=2)
    fig.add_hline(y=80, line_dash="dash", line_color="#EC7063", row=1, col=2)
    
    fig.update_xaxes(title_text="Data Type", row=1, col=1)
    fig.update_xaxes(title_text="Data Type", row=1, col=2)
    fig.update_yaxes(title_text="% of Peak Bandwidth (900 GB/s)", row=1, col=1, range=[0, 100])
    fig.update_yaxes(title_text="% of Peak Bandwidth (900 GB/s)", row=1, col=2, range=[0, 100])
    
    fig.update_layout(
        height=600,
        width=1600,
        title_text="GPU Bandwidth Utilization (vs MI250X theoretical peak ~900 GB/s)<br>"
                   "<sub>< 50%: compute-bound | > 80%: memory-bound</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=11),
        barmode='group'
    )
    
    output_file = output_dir / 'viz_09_bandwidth_utilization.png'
    fig.write_image(str(output_file), width=1920, height=720, scale=2)
    print(f"  ✓ {output_file.name}")

def viz_10_decision_guide(df, output_dir):
    """
    10. DECISION GUIDE
    Matriz de decisão e recomendações práticas.
    """
    print("\n[10/10] Gerando Decision Guide...")
    
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Best Algorithm by Use Case',
            'Performance Radar: Algorithm Profiles',
            'Winner by Category',
            'Recommendation Matrix'
        ),
        specs=[[{"type": "bar"}, {"type": "scatterpolar"}],
               [{"type": "bar"}, {"type": "table"}]],
        vertical_spacing=0.15,
        horizontal_spacing=0.12
    )
    
    # 1. Best by use case
    use_cases = {
        'Max Comp Speed': df.loc[df['CompressionThroughput_GBps'].idxmax()],
        'Max Decomp Speed': df.loc[df['DecompressionThroughput_GBps'].idxmax()],
        'Best Ratio': df.loc[df['CompressionRatio'].idxmax()],
        'TTI Balanced': df[df['DataType'] == 'TTI'].loc[df[df['DataType'] == 'TTI']['Effectiveness'].idxmax()],
        'Small Files': df[df['SizeCategory'] == 'Small'].loc[df[df['SizeCategory'] == 'Small']['CompressionThroughput_GBps'].idxmax()]
    }
    
    labels = list(use_cases.keys())
    values = [row['CompressionThroughput_GBps'] if 'Speed' in case else row['CompressionRatio'] 
              for case, row in use_cases.items()]
    colors_list = [COLORS.get(row['Algorithm'], '#85929E') for row in use_cases.values()]
    text_list = [f"{row['Algorithm'].upper()}<br>{val:.1f}" for row, val in zip(use_cases.values(), values)]
    
    fig.add_trace(
        go.Bar(
            x=labels,
            y=values,
            marker_color=colors_list,
            text=text_list,
            textposition='outside',
            showlegend=False
        ),
        row=1, col=1
    )
    
    # 2. Radar chart
    categories = ['Comp Speed', 'Decomp Speed', 'Ratio', 'Consistency', 'Scalability']
    
    for algo in sorted(df['Algorithm'].unique()):
        algo_data = df[df['Algorithm'] == algo]
        
        # Normalize to 0-100
        values_radar = [
            (algo_data['CompressionThroughput_GBps'].mean() / df['CompressionThroughput_GBps'].max()) * 100,
            (algo_data['DecompressionThroughput_GBps'].mean() / df['DecompressionThroughput_GBps'].max()) * 100,
            (algo_data['CompressionRatio'].mean() / df['CompressionRatio'].max()) * 100,
            100 - (algo_data['CompressionThroughput_GBps'].std() / algo_data['CompressionThroughput_GBps'].mean()) * 100,
            100 - abs(algo_data.groupby('SizeCategory')['CompressionThroughput_GBps'].mean().std() / 
                     algo_data.groupby('SizeCategory')['CompressionThroughput_GBps'].mean().mean()) * 50
        ]
        values_radar.append(values_radar[0])
        
        fig.add_trace(
            go.Scatterpolar(
                r=values_radar,
                theta=categories + [categories[0]],
                fill='toself',
                name=algo.upper(),
                line=dict(color=COLORS.get(algo, '#85929E'), width=2),
                opacity=0.6
            ),
            row=1, col=2
        )
    
    # 3. Winner count
    winner_counts = {'lz4': 0, 'snappy': 0, 'cascaded': 0}
    
    for _, row in df.iterrows():
        file_subset = df[df['TestFile'] == row['TestFile']]
        
        if row['CompressionThroughput_GBps'] == file_subset['CompressionThroughput_GBps'].max():
            winner_counts[row['Algorithm']] += 1
        if row['DecompressionThroughput_GBps'] == file_subset['DecompressionThroughput_GBps'].max():
            winner_counts[row['Algorithm']] += 1
        if row['CompressionRatio'] == file_subset['CompressionRatio'].max():
            winner_counts[row['Algorithm']] += 1
    
    fig.add_trace(
        go.Bar(
            x=[k.upper() for k in winner_counts.keys()],
            y=list(winner_counts.values()),
            marker_color=[COLORS.get(k, '#85929E') for k in winner_counts.keys()],
            text=list(winner_counts.values()),
            textposition='outside',
            showlegend=False
        ),
        row=2, col=1
    )
    
    # 4. Recommendation table
    recommendations = []
    
    # TTI recommendations
    tti_data = df[df['DataType'] == 'TTI']
    best_tti_comp = tti_data.loc[tti_data['CompressionThroughput_GBps'].idxmax()]
    best_tti_decomp = tti_data.loc[tti_data['DecompressionThroughput_GBps'].idxmax()]
    best_tti_ratio = tti_data.loc[tti_data['CompressionRatio'].idxmax()]
    
    recommendations.append(['TTI: Max Compression', best_tti_comp['Algorithm'].upper(), 
                           f"{best_tti_comp['CompressionThroughput_GBps']:.1f} GB/s"])
    recommendations.append(['TTI: Max Decompression', best_tti_decomp['Algorithm'].upper(),
                           f"{best_tti_decomp['DecompressionThroughput_GBps']:.1f} GB/s"])
    recommendations.append(['TTI: Best Ratio', best_tti_ratio['Algorithm'].upper(),
                           f"{best_tti_ratio['CompressionRatio']:.1f}x"])
    
    # General recommendations
    recommendations.append(['Small Files (< 100MB)', 'CASCADED', 'Best avg performance'])
    recommendations.append(['Large Files (> 1GB)', 'CASCADED/LZ4', 'Both scale well'])
    recommendations.append(['Need Fast Decomp', 'LZ4', 'Up to 400+ GB/s'])
    recommendations.append(['Mixed Workload', 'SNAPPY', 'Most consistent'])
    
    table_data = list(zip(*recommendations))
    
    fig.add_trace(
        go.Table(
            header=dict(values=['<b>Use Case</b>', '<b>Algorithm</b>', '<b>Metric</b>'],
                       fill_color='#85929E',
                       font=dict(color='white', size=11),
                       align='left'),
            cells=dict(values=table_data,
                      fill_color='#F8F9F9',
                      font=dict(size=10),
                      align='left',
                      height=25)
        ),
        row=2, col=2
    )
    
    fig.update_xaxes(title_text="Use Case", tickangle=45, row=1, col=1)
    fig.update_yaxes(title_text="Value", row=1, col=1)
    fig.update_xaxes(title_text="Algorithm", row=2, col=1)
    fig.update_yaxes(title_text="Number of Wins", row=2, col=1)
    
    fig.update_layout(
        height=1000,
        width=1800,
        title_text="Algorithm Selection Decision Guide<br>"
                   "<sub>Practical recommendations based on benchmark results</sub>",
        title_font_size=20,
        template='plotly_white',
        font=dict(size=10),
        polar=dict(radialaxis=dict(visible=True, range=[0, 100]))
    )
    
    output_file = output_dir / 'viz_10_decision_guide.png'
    fig.write_image(str(output_file), width=2160, height=1200, scale=2)
    print(f"  ✓ {output_file.name}")

def generate_summary_report(df, output_dir):
    """Generate comprehensive analysis report."""
    report = []
    report.append("=" * 100)
    report.append("FEATURE 2 WAVE64 - COMPLETE VISUALIZATION SUITE ANALYSIS")
    report.append("=" * 100)
    report.append("")
    
    report.append("EXECUTIVE SUMMARY")
    report.append("-" * 100)
    report.append(f"Total benchmark tests: {len(df)}")
    report.append(f"Algorithms: {', '.join([a.upper() for a in sorted(df['Algorithm'].unique())])}")
    report.append(f"Data types: {', '.join(sorted(df['DataType'].unique()))}")
    report.append(f"File size range: {df['SizeMB'].min():.0f} MB to {df['SizeMB'].max():.0f} MB ({df['SizeMB'].max()/df['SizeMB'].min():.0f}x variation)")
    report.append("")
    
    # TTI Analysis
    tti = df[df['DataType'] == 'TTI']
    report.append("TTI SEISMIC DATA - KEY METRICS")
    report.append("-" * 100)
    for algo in sorted(tti['Algorithm'].unique()):
        a = tti[tti['Algorithm'] == algo]
        report.append(f"\n{algo.upper()}:")
        report.append(f"  Compression:   {a['CompressionThroughput_GBps'].mean():6.2f} GB/s  (min: {a['CompressionThroughput_GBps'].min():6.2f}, max: {a['CompressionThroughput_GBps'].max():6.2f})")
        report.append(f"  Decompression: {a['DecompressionThroughput_GBps'].mean():6.2f} GB/s  (min: {a['DecompressionThroughput_GBps'].min():6.2f}, max: {a['DecompressionThroughput_GBps'].max():6.2f})")
        report.append(f"  Ratio:         {a['CompressionRatio'].mean():6.2f}x    (min: {a['CompressionRatio'].min():6.2f}, max: {a['CompressionRatio'].max():6.2f})")
    report.append("")
    
    # Performance Rankings
    report.append("OVERALL PERFORMANCE RANKINGS")
    report.append("-" * 100)
    
    comp_rank = df.groupby('Algorithm')['CompressionThroughput_GBps'].mean().sort_values(ascending=False)
    report.append("\nCompression Speed (avg):")
    for i, (algo, val) in enumerate(comp_rank.items(), 1):
        report.append(f"  {i}. {algo.upper():10s} {val:6.2f} GB/s")
    
    decomp_rank = df.groupby('Algorithm')['DecompressionThroughput_GBps'].mean().sort_values(ascending=False)
    report.append("\nDecompression Speed (avg):")
    for i, (algo, val) in enumerate(decomp_rank.items(), 1):
        report.append(f"  {i}. {algo.upper():10s} {val:6.2f} GB/s")
    
    ratio_rank = df.groupby('Algorithm')['CompressionRatio'].mean().sort_values(ascending=False)
    report.append("\nCompression Ratio (avg):")
    for i, (algo, val) in enumerate(ratio_rank.items(), 1):
        report.append(f"  {i}. {algo.upper():10s} {val:6.2f}x")
    
    report.append("")
    report.append("KEY INSIGHTS")
    report.append("-" * 100)
    report.append(f"1. Best overall compression speed: {df.loc[df['CompressionThroughput_GBps'].idxmax(), 'Algorithm'].upper()} "
                 f"({df['CompressionThroughput_GBps'].max():.2f} GB/s on {df.loc[df['CompressionThroughput_GBps'].idxmax(), 'DataType']})")
    report.append(f"2. Best overall decompression speed: {df.loc[df['DecompressionThroughput_GBps'].idxmax(), 'Algorithm'].upper()} "
                 f"({df['DecompressionThroughput_GBps'].max():.2f} GB/s on {df.loc[df['DecompressionThroughput_GBps'].idxmax(), 'DataType']})")
    report.append(f"3. Best compression ratio: {df.loc[df['CompressionRatio'].idxmax(), 'Algorithm'].upper()} "
                 f"({df['CompressionRatio'].max():.2f}x on {df.loc[df['CompressionRatio'].idxmax(), 'DataType']})")
    
    # Scalability
    small = df[df['SizeCategory'] == 'Small']
    large = df[df['SizeCategory'].isin(['Large', 'XLarge'])]
    avg_penalty = ((1 - small['CompressionThroughput_GBps'].mean() / large['CompressionThroughput_GBps'].mean()) * 100)
    report.append(f"4. Average small file penalty: {avg_penalty:.1f}% performance loss (10MB vs 1-4GB)")
    
    report.append("")
    report.append("=" * 100)
    
    # Save
    report_text = "\n".join(report)
    report_file = output_dir / 'visualization_suite_analysis.txt'
    with open(report_file, 'w') as f:
        f.write(report_text)
    
    print(f"\n✓ Generated: {report_file.name}")
    print("\n" + report_text)

def main():
    if len(sys.argv) < 2:
        print("Usage: python complete_viz_suite.py <path_to_results.csv>")
        print("\nExample:")
        print("  python complete_viz_suite.py results/feature2_wave64/20251202_095500_87a26a0/results.csv")
        sys.exit(1)
    
    csv_path = Path(sys.argv[1])
    
    if not csv_path.exists():
        print(f"Error: File not found: {csv_path}")
        sys.exit(1)
    
    print("\n" + "=" * 100)
    print("FEATURE 2 WAVE64 - COMPLETE VISUALIZATION SUITE")
    print("Generating 10 strategic visualizations + comprehensive report")
    print("=" * 100)
    
    # Load data
    print(f"\nLoading data from: {csv_path}")
    df = load_and_prepare_data(csv_path)
    
    print(f"  ✓ Loaded {len(df)} benchmark results")
    print(f"  ✓ Algorithms: {', '.join(sorted(df['Algorithm'].unique()))}")
    print(f"  ✓ Data types: {', '.join(sorted(df['DataType'].unique()))}")
    print(f"  ✓ File sizes: {df['SizeMB'].min():.0f} MB to {df['SizeMB'].max():.0f} MB")
    
    # Create output directory
    output_dir = csv_path.parent / 'visualizations_mi50'
    output_dir.mkdir(exist_ok=True)
    
    print(f"\nGenerating visualizations in: {output_dir}")
    print("=" * 100)
    
    # Generate all visualizations
    viz_01_heatmap_performance(df, output_dir)
    viz_02_pareto_front(df, output_dir)
    viz_03_scalability_curves(df, output_dir)
    viz_04_efficiency_ratio(df, output_dir)
    viz_05_compression_effectiveness(df, output_dir)
    viz_06_small_file_penalty(df, output_dir)
    viz_07_data_type_sensitivity(df, output_dir)
    viz_08_tti_spotlight(df, output_dir)
    viz_09_bandwidth_utilization(df, output_dir)
    viz_10_decision_guide(df, output_dir)
    
    # Generate report
    print("\n" + "=" * 100)
    print("Generating comprehensive analysis report...")
    print("=" * 100)
    generate_summary_report(df, output_dir)
    
    # Summary
    print("\n" + "=" * 100)
    print("✅ COMPLETE! All visualizations generated successfully")
    print("=" * 100)
    print("\nGenerated files:")
    for i, f in enumerate(sorted(output_dir.glob('viz_*.png')), 1):
        print(f"  {i:2d}. {f.name}")
    print(f"  11. visualization_suite_analysis.txt")
    print(f"\n📁 Location: {output_dir.absolute()}")
    print("=" * 100 + "\n")

if __name__ == '__main__':
    main()
