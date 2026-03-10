# HIP Compression Toolkit — Guia de Execução

Guia de como executar benchmarks de compressão (LZ4, Snappy, Cascaded) em GPUs AMD usando o **HIP Compression Toolkit**.

---

## Arquitetura: Ferramenta vs Experimentos

A separação é clara — **a ferramenta é apenas a biblioteca e seus benchmarks**, tudo o resto é infraestrutura de experimentação:

### `hip-compression-toolkit/` — FERRAMENTA (API + Biblioteca)

Projeto CMake puro. Nenhum script é necessário para build ou funcionamento.

```
hip-compression-toolkit/
├── CMakeLists.txt              Build system (cmake + make é tudo que precisa)
├── src/                        Código da biblioteca (libhipcomp.so)
├── include/                    Headers públicos (hipcomp.h, hipcomp.hpp, hipcomp/)
├── benchmarks/                 Fontes dos benchmarks (compilam para executáveis)
├── tests/                      Testes unitários
├── cmake/                      Módulos CMake
├── README.md                   Documentação da API
└── LICENSE
```

**Build direto (sem nenhum script):**
```bash
cd hip-compression-toolkit
mkdir -p build && cd build
cmake .. \
  -DCMAKE_PREFIX_PATH=/opt/rocm \
  -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
  -DBUILD_BENCHMARKS=ON \
  -DBUILD_TESTS=ON \
  -DCMAKE_INSTALL_PREFIX=/opt/hipcomp
make -j$(nproc)
make install
```

**Produz:**
- `lib/libhipcomp.so` — biblioteca compartilhada
- `bin/benchmark_lz4_chunked` — benchmark LZ4
- `bin/benchmark_snappy_chunked` — benchmark Snappy
- `bin/benchmark_cascaded_chunked` — benchmark Cascaded

### `hip-compression-experiments/` — EXPERIMENTOS (repo separado)

Responsável por **ambiente de execução**, Singularity, geração de dados, orquestração de benchmarks, análise e visualização.

```
hip-compression-experiments/
├── singularity/
│   ├── defhip_benchmark.def        Definição do container (clona e builda o toolkit)
│   ├── build_singularity.sh        Script para gerar o .sif
│   └── singularity_entrypoint.sh   Entrypoint do container
├── scripts/
│   ├── run_benchmarks_auto.sh      Automação de benchmarks (orchestração)
│   ├── run_singularity.sh          Wrapper de execução via container
│   ├── portable_benchmark.sh       Benchmark cross-platform (AMD/NVIDIA)
│   ├── deploy_benchmarks.sh        Deploy multi-cluster (PCAD, Grid5000)
│   ├── generate_testdata.sh        Geração de dados de teste sintéticos
│   ├── convert_rsf_to_binary.py    Conversão RSF → binário
│   ├── prepare_rsf_testdata.sh     Wrapper de conversão RSF
│   ├── compare_results.sh          Comparação de resultados
│   ├── compare_platforms.py        Comparação AMD vs NVIDIA
│   ├── compare_features_mi300x.py  Visualização de features MI300X
│   ├── compare_two_features.py     Comparação de duas features
│   ├── complete_viz_suite.py       Suite de visualizações Plotly
│   ├── visualize_feature2_rsf.py   Visualização Feature 2 + RSF
│   └── analyze_rsf_data_quality.py Análise de qualidade RSF
├── results/                        Resultados por GPU/timestamp
├── testdata/                       Dados de teste gerados/cacheados
├── configs/                        Configurações de experimentos
├── images/                         Imagens .sif geradas (ou links)
└── EXECUTION_GUIDE.md              Este guia
```

**Princípio**: O `.sif` é gerado pelo repo de **experimentos** (que referencia o repo da ferramenta no `def`). A ferramenta não sabe nada sobre Singularity, RSF, Fletcher, ou experimentação.

---

## Pré-requisitos

- **Singularity/Apptainer** instalado no host
- **ROCm** instalado no host (driver + runtime)
- GPU AMD compatível (gfx1100, gfx942, gfx90a, etc.)
- Dados RSF do Fletcher (contendo subpasta `large/` com `TTI.rsf`)

---

## 1. Construir a Imagem Singularity (no repo de experimentos)

O `def` fica no repo de **experimentos**. Ele clona e compila o toolkit automaticamente:

### RX 7900 XT (gfx1100)

```bash
cd hip-compression-experiments

singularity build --fakeroot \
  images/hipcomp_gfx1100.sif \
  singularity/defhip_benchmark.def
# O def file usa GPU_ARCH=gfx1100 como argumento
```

Ou usando o script wrapper:
```bash
./singularity/build_singularity.sh --arch gfx1100
# Gera: images/hipcomp_gfx1100.sif (≈6 GB, self-contained)
```

### MI300X (gfx942)

```bash
./singularity/build_singularity.sh --arch gfx942
```

### MI210/MI250 (gfx90a)

```bash
./singularity/build_singularity.sh --arch gfx90a
```

O `.sif` é portável — copie para qualquer máquina com ROCm + Singularity.

---

## 2. Execução Full (Benchmark Completo)

### RX 7900 XT — Execução completa

```bash
cd hip-compression-experiments
mkdir -p results testdata

singularity run --rocm \
  --bind /ssd/cakunas/fletcher-io/original/run:/data/rsf:ro \
  --bind ./results:/data/results \
  --bind ./testdata:/data/testdata \
  images/hipcomp_gfx1100.sif \
  -r /data/rsf \
  -d /data/testdata \
  -o /data/results \
  -a "lz4 snappy cascaded" \
  -i 10 \
  -w 2 \
  -p "65536"
```

Ou com o wrapper:
```bash
./scripts/run_singularity.sh images/hipcomp_gfx1100.sif \
  /ssd/cakunas/fletcher-io/original/run
```

### Com múltiplos chunk sizes (análise de throughput)

```bash
./scripts/run_singularity.sh images/hipcomp_gfx1100.sif \
  /ssd/cakunas/fletcher-io/original/run \
  -i 20 -p "65536 1048576 16777216"
```

### Com mais iterações para maior precisão estatística

```bash
./scripts/run_singularity.sh images/hipcomp_gfx1100.sif \
  /ssd/cakunas/fletcher-io/original/run \
  -i 50 -w 5
```

---

## 3. Execução Parcial / Algoritmo Específico

### Apenas LZ4

```bash
singularity run --rocm \
  --bind /ssd/cakunas/fletcher-io/original/run:/data/rsf:ro \
  --bind ./results:/data/results \
  --bind ./testdata:/data/testdata \
  images/hipcomp_gfx1100.sif \
  -r /data/rsf -d /data/testdata -o /data/results \
  -a "lz4" -i 10
```

### Apenas Snappy

```bash
singularity run --rocm \
  --bind /ssd/cakunas/fletcher-io/original/run:/data/rsf:ro \
  --bind ./results:/data/results \
  --bind ./testdata:/data/testdata \
  images/hipcomp_gfx1100.sif \
  -r /data/rsf -d /data/testdata -o /data/results \
  -a "snappy" -i 10
```

---

## 4. Dry Run (validar setup sem executar)

```bash
./scripts/run_singularity.sh images/hipcomp_gfx1100.sif \
  /ssd/cakunas/fletcher-io/original/run --dry-run
```

---

## 5. Execução via `singularity exec` (acesso direto aos binários)

Para executar um benchmark individual sem o runner automático:

```bash
singularity exec --rocm \
  --bind ./testdata:/data/testdata \
  images/hipcomp_gfx1100.sif \
  /opt/hipcomp/bin/benchmark_lz4_chunked \
  -f /data/testdata/large_TTI_1024.bin -i 10 -p 65536
```

---

## 6. Execução Nativa (sem Singularity, com ROCm local)

Se o ROCm estiver instalado localmente, compilar e executar direto:

```bash
# 1. Buildar a ferramenta
cd hip-compression-toolkit
mkdir -p build && cd build
cmake .. -DCMAKE_PREFIX_PATH=/opt/rocm -DCMAKE_HIP_ARCHITECTURES=gfx1100 \
  -DBUILD_BENCHMARKS=ON -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# 2. Gerar testdata (no repo de experimentos)
cd ../../hip-compression-experiments
./scripts/generate_testdata.sh /ssd/cakunas/fletcher-io/original/run

# 3. Executar benchmarks diretamente
../hip-compression-toolkit/build/bin/benchmark_lz4_chunked -f testdata/large_TTI_1024.bin -i 10
../hip-compression-toolkit/build/bin/benchmark_snappy_chunked -f testdata/large_TTI_1024.bin -i 10
../hip-compression-toolkit/build/bin/benchmark_cascaded_chunked -f testdata/large_TTI_1024.bin -i 10
```

---

## 7. Onde ficam os resultados

Os resultados são salvos em `results/<GPU>_<timestamp>/`:

```
results/
└── RX7900XT_20260308_231534/
    ├── metadata.json           # Info da GPU, parâmetros, etc.
    ├── results.csv             # Resultados consolidados (CSV)
    ├── summary.csv             # Resumo por algoritmo
    ├── lz4_*.log               # Logs individuais por benchmark
    ├── snappy_*.log
    └── cascaded_*.log
```

---

## 8. Resumo Rápido por Plataforma

| Plataforma | Arch | Imagem SIF | Comando |
|---|---|---|---|
| RX 7900 XT | `gfx1100` | `hipcomp_gfx1100.sif` | `./scripts/run_singularity.sh images/hipcomp_gfx1100.sif <rsf_dir>` |
| MI300X | `gfx942` | `hipcomp_gfx942.sif` | `./scripts/run_singularity.sh images/hipcomp_gfx942.sif <rsf_dir>` |
| MI210/250 | `gfx90a` | `hipcomp_gfx90a.sif` | `./scripts/run_singularity.sh images/hipcomp_gfx90a.sif <rsf_dir>` |

Todos os comandos são executados **de dentro do repo `hip-compression-experiments/`**.

---

## Notas

- A flag `--rocm` é **obrigatória** para dar acesso à GPU dentro do container.
- O `.sif` é **self-contained**: contém ROCm, biblioteca compilada e benchmarks. Não depende de nenhum código-fonte no host.
- O `def` no repo de experimentos faz `git clone` do toolkit durante o build — a ferramenta não precisa estar localmente.
- O bind mount `:ro` no RSF é read-only (os dados originais não são modificados).
- Os testdata são cacheados entre execuções — a geração só ocorre se ausentes.
- Para chunk sizes maiores (ex: 16MB), os dados de teste precisam ter tamanho >= chunk size.

---

## TODO / Pendências

- [ ] **Criar repo `hip-compression-experiments`**: Mover toda a infra de experimentação (scripts, singularity, results, testdata, visualização) para repositório separado.
- [ ] **Limpar `hip-compression-toolkit/scripts/`**: Remover todos os scripts — a ferramenta é CMake puro. Nenhum script é referenciado pelo build system.
- [ ] **Renomear referências "hipCOMP"**: O projeto evoluiu a partir da base nvCOMP/hipCOMP, mas atualmente é o **HIP Compression Toolkit**. Referências internas (variáveis `HIPCOMP_*`, prints, nomes de funções) devem ser atualizadas.
- [ ] **Comparação hipify vs port manual**: Avaliar se um port automático via `hipify-perl`/`hipify-clang` dos fontes CUDA originais do nvCOMP produziria resultados equivalentes, documentando as correções manuais necessárias (wave size, shared memory, etc.) e diferenças de performance.
