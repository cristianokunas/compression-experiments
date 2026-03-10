# Compression Experiments

Repositório de experimentação, benchmarking e análise de resultados para o [HIP Compression Toolkit](https://github.com/cristianokunas/hip-compression-toolkit).

Este repositório é **separado da ferramenta** — contém toda a infraestrutura de execução, geração de dados, orquestração de benchmarks, visualização e análise.

## Estrutura

```
compression-experiments/
├── singularity/                    Ambiente de execução (container)
│   ├── defhip_benchmark.def          Definição do container Singularity
│   ├── build_singularity.sh          Script para gerar o .sif
│   └── singularity_entrypoint.sh     Entrypoint do container
├── scripts/                        Orquestração e análise
│   ├── run_benchmarks_auto.sh        Automação de benchmarks
│   ├── run_singularity.sh            Wrapper de execução via container
│   ├── portable_benchmark.sh         Benchmark cross-platform (AMD/NVIDIA)
│   ├── deploy_benchmarks.sh          Deploy multi-cluster (PCAD, Grid5000)
│   ├── build_for_arch.sh             Build nativo para uma arquitetura
│   ├── generate_testdata.sh          Geração de dados de teste sintéticos
│   ├── convert_rsf_to_binary.py      Conversão RSF → binário
│   ├── prepare_rsf_testdata.sh       Wrapper de conversão RSF
│   ├── compare_results.sh            Comparação de resultados
│   ├── compare_platforms.py          Comparação AMD vs NVIDIA
│   ├── compare_features_mi300x.py    Visualização de features MI300X
│   ├── compare_two_features.py       Comparação de duas features
│   ├── complete_viz_suite.py         Suite completa de visualizações
│   ├── visualize_feature2_rsf.py     Visualização Feature 2 + RSF
│   └── analyze_rsf_data_quality.py   Análise de qualidade de dados RSF
├── results/                        Resultados por GPU/timestamp
├── testdata/                       Dados de teste (gerados, não versionados)
├── images/                         Imagens .sif geradas (não versionadas)
├── configs/                        Configurações de experimentos
└── EXECUTION_GUIDE.md              Guia completo de execução
```

## Quick Start

### 1. Gerar a imagem Singularity (uma vez)

```bash
# RX 7900 XT
./singularity/build_singularity.sh --arch gfx1100

# MI300X
./singularity/build_singularity.sh --arch gfx942
```

### 2. Executar benchmark completo

```bash
mkdir -p results testdata

singularity run --rocm \
  --bind /path/to/fletcher-io/original/run:/data/rsf:ro \
  --bind ./results:/data/results \
  --bind ./testdata:/data/testdata \
  images/hipcomp_gfx1100.sif \
  -r /data/rsf \
  -d /data/testdata \
  -o /data/results \
  -a "lz4 snappy cascaded" \
  -i 10 -w 2 -p "65536"
```

### 3. Analisar resultados

```bash
# Comparar dois conjuntos de resultados
./scripts/compare_results.sh results/RX7900XT_run1 results/RX7900XT_run2

# Gerar visualizações
python3 scripts/complete_viz_suite.py results/RX7900XT_latest
```

## Plataformas suportadas

| GPU | Arch | Imagem |
|-----|------|--------|
| RX 7900 XT | `gfx1100` | `hipcomp_gfx1100.sif` |
| MI300X | `gfx942` | `hipcomp_gfx942.sif` |
| MI210/250 | `gfx90a` | `hipcomp_gfx90a.sif` |

## Dependências

- **Singularity/Apptainer** — para execução containerizada
- **ROCm** (driver) — no host para acesso à GPU
- **HIP Compression Toolkit** — compilado dentro do `.sif` automaticamente

Veja o [EXECUTION_GUIDE.md](EXECUTION_GUIDE.md) para detalhes completos.

## Relação com o HIP Compression Toolkit

O `.sif` é **self-contained** — o `defhip_benchmark.def` faz `git clone` e compila o toolkit automaticamente durante o build da imagem. Não é necessário ter o código-fonte do toolkit localmente para executar experimentos.

```
[hip-compression-toolkit]        [compression-experiments]
      (API/Biblioteca)             (Experimentação)
           │                              │
     CMake build puro              singularity/def
     src/ include/                 ↓ git clone + build
     benchmarks/                   images/*.sif (self-contained)
     tests/                        ↓
           │                       scripts/ → executa via singularity
           └──── compilado em ────→ results/ → análise + visualização
```
