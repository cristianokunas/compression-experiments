# Conversão de Dados RSF para Benchmarks hipCOMP

## Resumo da Solução

Criei uma infraestrutura completa para converter dados RSF (Madagascar Seismic File Format) em binários puros para uso nos benchmarks do hipCOMP.

## Arquivos Criados

### 1. `scripts/convert_rsf_to_binary.py`
Conversor Python puro (sem dependências externas) que:
- Lê cabeçalhos RSF e extrai metadados (dimensões, tipo de dados)
- Valida o tamanho do arquivo binário
- Calcula estatísticas amostrais (min, max, média, desvio padrão)
- Copia dados binários de forma eficiente (chunks de 64 MB)
- Funciona para arquivos gigantes (testado com ~100 GB)

**Uso:**
```bash
# Conversão com validação
python3 scripts/convert_rsf_to_binary.py input.rsf output.bin

# Conversão rápida sem validação (para arquivos grandes)
python3 scripts/convert_rsf_to_binary.py input.rsf output.bin --no-validate

# Modo silencioso
python3 scripts/convert_rsf_to_binary.py input.rsf output.bin -q
```

### 2. `scripts/prepare_rsf_testdata.sh`
Script bash que automatiza a conversão em lote:
- Busca automaticamente nos diretórios `small/`, `medium/`, `large/`
- Nomeia arquivos com prefixo do tamanho: `{size}_{dataset}_float32.bin`
- Cria documentação automática (`RSF_README.txt`)
- Mostra sumário dos arquivos gerados

**Uso:**
```bash
# Usa diretório padrão (testdata/)
./scripts/prepare_rsf_testdata.sh

# Especifica diretório de saída
./scripts/prepare_rsf_testdata.sh /path/to/output
```

## Estrutura de Dados Gerados

```
testdata/
├── small_TTI_float32.bin     # ~192 MB (256×256×256×3)
├── medium_TTI_float32.bin    # ~6.4 GB (256×256×256×101)
├── large_TTI_float32.bin     # ~99 GB (256×256×256×1563)
└── RSF_README.txt            # Documentação de uso
```

## Organização por Tamanho

Seguindo a ideia do `generate_testdata.sh`:

| Categoria | Tamanho Aproximado | Uso Recomendado |
|-----------|-------------------|-----------------|
| **Small** | ~100-200 MB | Testes rápidos, validação |
| **Medium** | ~1-10 GB | Benchmarks padrão |
| **Large** | ~10-100 GB | Stress testing, performance máximo |

## Uso com Benchmarks

### Teste Individual
```bash
# LZ4 no dataset pequeno
./build/benchmarks/benchmark_lz4_chunked \
    -f testdata/small_TTI_float32.bin \
    -c true -i 5

# Snappy no dataset médio
./build/benchmarks/benchmark_snappy_chunked \
    -f testdata/medium_TTI_float32.bin \
    -c true -i 3 -w 1

# Cascaded no dataset grande
./build/benchmarks/benchmark_cascaded_chunked \
    -f testdata/large_TTI_float32.bin \
    -c true
```

### Teste em Lote (Todos os Algoritmos)
```bash
for size in small medium large; do
    for algo in lz4 snappy cascaded; do
        echo "=== Testing ${algo} on ${size} dataset ==="
        ./build/benchmarks/benchmark_${algo}_chunked \
            -f testdata/${size}_TTI_float32.bin \
            -c true -i 3 -w 1 \
            > results/${algo}_${size}_$(date +%Y%m%d_%H%M%S).csv
    done
done
```

### Com Script de Benchmark
```bash
# Testar algoritmo específico em todos os tamanhos
./scripts/benchmark.sh lz4 testdata/

# Testar em tamanho específico
./scripts/benchmark.sh snappy testdata/small_*.bin
```

## Características dos Dados TTI

- **Formato**: Dados sísmicos 3D (Tilted Transverse Isotropic)
- **Tipo**: Float32 (4 bytes por elemento)
- **Padrão**: Moderate spatial correlation (bom para compressão)
- **Aplicação**: Típico de computação científica (oil & gas, sísmica)

### Expectativas de Compressão para Float32

Com base em dados sísmicos similares:

| Algoritmo | Ratio Esperado | Throughput | Uso |
|-----------|---------------|------------|-----|
| **LZ4** | 1.2-2.0x | Alto (~30+ GB/s) | Rápido, baixa compressão |
| **Snappy** | 1.3-2.2x | Médio-Alto (~20 GB/s) | Balanceado |
| **Cascaded** | 2.0-4.0x | Médio (~10 GB/s) | Melhor compressão |

## Vantagens da Solução

1. **Sem dependências**: Python puro, sem NumPy ou bibliotecas externas
2. **Eficiente**: Processamento em chunks, suporta arquivos de 100+ GB
3. **Validação**: Estatísticas amostrais para verificar integridade
4. **Automático**: Script bash processa diretórios inteiros
5. **Documentado**: Gera README.txt com instruções de uso
6. **Compatível**: Arquivos binários puros funcionam diretamente nos benchmarks

## Próximos Passos Sugeridos

1. **Testar benchmarks**: Executar os 3 algoritmos (LZ4, Snappy, Cascaded) nos 3 tamanhos
2. **Comparar resultados**: Usar `compare_results.sh` para análise
3. **Otimizações**: Testar diferentes chunk sizes (`-p` parameter)
4. **Documentar**: Adicionar resultados ao `OPTIMIZATION_FEATURES.md`

## Exemplo Completo de Workflow

```bash
# 1. Converter dados RSF
cd /ssd/cakunas/hip-compression-toolkit
./scripts/prepare_rsf_testdata.sh

# 2. Verificar arquivos gerados
ls -lh testdata/
cat testdata/RSF_README.txt

# 3. Teste rápido (small dataset, LZ4)
./build/benchmarks/benchmark_lz4_chunked \
    -f testdata/small_TTI_float32.bin \
    -c true -i 10 -w 2

# 4. Benchmark completo (todos algoritmos, medium dataset)
mkdir -p results/rsf_benchmarks
for algo in lz4 snappy cascaded; do
    ./build/benchmarks/benchmark_${algo}_chunked \
        -f testdata/medium_TTI_float32.bin \
        -c true -i 5 -w 2 \
        > results/rsf_benchmarks/${algo}_medium.csv
done

# 5. Análise
./scripts/visualize_results.py results/rsf_benchmarks/
```

## Notas Técnicas

- Os arquivos `.rsf@` contêm dados binários em **native endian**
- O formato RSF é amplamente usado em geofísica computacional
- Dados float32 têm correlação espacial → favorável para compressão
- Arquivos grandes podem levar minutos para converter (I/O bound)
- Validação com estatísticas é opcional (`--no-validate` para pular)
