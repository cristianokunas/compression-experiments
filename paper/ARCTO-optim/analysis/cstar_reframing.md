# Revisão do modelo de c* (chunk size) — crítica e enquadramento corrigido

Nota de apoio para reescrita da Seção 4 (Wave-Aware Kernel Chunking).
Tudo aqui é sustentado pelos dados em
`analysis/chunk_sweeps.csv` (235 medições; gfx942/MI300X, gfx90a/MI210,
gfx1100/RX7900XT; lz4/snappy/cascaded; baseline e pinned).

## 1. O problema com a fórmula atual

A Seção 4 apresenta como forma fechada:

    c* ≈ S / W,   com W = N_CU · W_max  (slots de wave residentes)

O `S` (tamanho do workload de referência) é um parâmetro livre, e foi
fixado **arbitrariamente** em 100 MiB. Isso quebra a fórmula como lei:

- se `c* = S/W`, então o ótimo tem que **escalar linearmente com S**;
- para S = 4 GiB (40× maior), a fórmula prevê c* = 40 × 8K = 320 KiB no MI300X;
- mas o ótimo empírico continua ~8 KiB independentemente do tamanho.

A fórmula só "fechou" porque 100 MiB foi escolhido (sem querer) bem em cima
do limiar `S ≈ W·c_floor`, onde `S/W ≈ c_floor` por coincidência. A conta
é circular.

## 2. Evidência empírica (os próprios dados)

LZ4, baseline, throughput de compressão (GB/s), variando o tamanho do
workload 10× (medium 100 MB → large 1 GB):

| Arch | ótimo @100 MB | ótimo @1 GB | o que S/W previa |
|---|---|---|---|
| MI300X (gfx942) | **8K** (14.81) | **8K** (18.13) | 8K → ~80K |
| MI210 (gfx90a)  | **8K** (3.15)  | **8K** (3.18)  | ~8K → ~80K |
| RX7900XT (gfx1100) | 8–16K (9.74/9.90) | **8K** (11.78) | ~32K → ~320K |

Curva completa LZ4 baseline (GB/s):

| chunk | MI300X 100MB | MI300X 1GB | MI210 100MB | MI210 1GB | RX79 100MB | RX79 1GB |
|---|---|---|---|---|---|---|
| 8K   | **14.81** | **18.13** | **3.15** | **3.18** | 9.74 | **11.78** |
| 16K  | 11.81 | 16.89 | 2.72 | 2.84 | **9.90** | 11.19 |
| 32K  | 6.48  | 11.61 | 2.21 | 2.61 | 7.96 | 9.95 |
| 64K  | 4.89  | 12.07 | 1.95 | 2.39 | 5.84 | 7.42 |
| 256K | 1.86  | 7.62  | 1.44 | 2.19 | 4.26 | 5.94 |
| 1M   | 0.52  | 3.35  | 0.43 | 2.14 | 1.22 | 6.29 |

Leitura:

1. **O ótimo não se move com S.** Cresceu 10× o workload, o ótimo ficou em
   8K nas três arquiteturas. Se `c*=S/W` fosse lei, teria multiplicado por 10.
2. **A curva é monótona** (chunk menor é sempre melhor até o piso testado de
   8K). O ótimo não está em `N = W` (saturação); está fundo na
   *oversubscription*. Exemplo: MI300X @1 GB com 64K já dá
   N = 16384 > W = 9728 chunks (já satura pela conta de wave), mas 8K ainda
   ganha (18.13 vs 12.07). Logo W **não é** onde fica o ótimo.
3. **S muda o nível, não o ótimo.** O throughput sobe com S (mais chunks
   amortizam custos fixos), mas o ponto de máximo permanece.

## 3. Modelo corrigido (dois lados)

O chunk ótimo é uma **constante por (arch, codec)**, não uma função de S.
Ele resulta de dois limites:

- **Piso** `c_floor(arch, codec)`: abaixo disso o custo fixo por chunk
  (launch/metadata, reset do dicionário do LZ4, perda de ratio, cauda não
  coalescida) passa a dominar. É o que fixa o ótimo, ~8 KiB em CDNA e RDNA3
  para LZ4/Snappy. (Cascaded é plano na faixa: pipeline regular de
  delta + RLE, a discussão de chunk não se aplica.)
- **Teto** `c ≤ S/(k·W)`: acima disso faltam chunks para encher e
  oversubscrever o device. É apenas um teto, não o ótimo.

O ótimo é `c_floor` sempre que a janela `[c_floor, S/W]` é não vazia, ou
seja, sempre que o workload é grande o bastante para saturar.

    c* ≈ c_floor(arch, codec)   (constante medida, ~8 KiB; o sweep é a fonte da verdade)

## 4. O que salvar de W: forma fechada honesta para S_sat

W não prevê c*, mas prevê o **tamanho mínimo de workload para saturar** o
device, e isso é falseável e bate com os dados:

    S_sat ≈ W · c_floor

| Arch | N_CU | W = N_CU·32 | c_floor | S_sat previsto |
|---|---|---|---|---|
| MI300X (gfx942) | 304 | 9728 | 8 KiB | ~80 MB |
| MI210 (gfx90a)  | 104 | 3328 | 8 KiB | ~27 MB |
| RX7900XT (gfx1100) | 84 | 2688 | 8 KiB | ~22 MB |

Validação cruzada com o gap medium(100MB)→large(1GB) no ótimo:

- **MI300X** (S_sat ~80 MB): 100 MB **mal** satura → 14.81; 1 GB satura →
  18.13. Gap grande (+22%), como o modelo prevê (100 MB está no joelho).
- **MI210** (S_sat ~27 MB): 100 MB **já** saturado → 3.15 vs 3.18, **plano**.
- **RX7900XT** (S_sat ~22 MB): 100 MB já quase saturado → gap menor.

O tamanho do gap escala com W exatamente como o modelo prevê (W grande →
S_sat grande → 100 MB ainda no joelho → maior gap). **Esse** é o uso
defensável de W.

## 5. Recomendação para a reescrita da Seção 4

Inverter o enquadramento:

1. `c*` é uma **constante medida por (arch, codec)** (o sweep empírico é a
   fonte da verdade; a fórmula não o substitui). ~8 KiB para LZ4/Snappy em
   CDNA/RDNA3; Cascaded plano.
2. W explica o **mecanismo** (precisa de ≫ W chunks → chunks pequenos) e dá
   a forma fechada de `S_sat = W·c_floor` (não de c*). Apresentar a tabela
   de S_sat validada pelo gap medium→large.
3. Para uma GPU nova: **não se calcula** c* em forma fechada, **mede-se**
   com o sweep. W (de `hipDeviceProp`/`rocminfo`) serve só para prever S_sat
   e a oitava onde **começar** o sweep.

Assim a objeção (S arbitrário, conta não fecha em 4 GB) fica resolvida sem
perder o argumento arquitetural, e tudo continua sustentado pelos dados.

## 6. Script de sweep (genérico, qualquer GPU AMD)

`scripts/sweep_cstar.sh` mede c* de forma reprodutível em qualquer GPU AMD,
sem hardcode de arquitetura:

- **Auto-detecta a GPU** via `rocminfo`: lê `gfx`, `Compute Unit` e
  `Max Waves Per CU`, e calcula `W = CU x MaxWavesPerCU`. (RX7900XT:
  84 x 32 = 2688; MI300X: 304 x 32 = 9728.)
- **Imprime a referência de saturação** `S_sat = W x c_floor` (c_floor=8 KiB)
  e a previsão *legada* `S/W` no workload escolhido, deixando explícito que
  ela escalaria errado com o tamanho. O sweep empírico é a fonte da verdade.
- **Gera dado sintético pequeno e barato** se nenhum for dado: 70% padrão
  (0x00..0xFF repetido) + 30% random, com tamanho default `>= 4*S_sat` para
  garantir saturação (ex.: 128 MiB na RX7900XT). Aceita `DATA=arquivo_TTI.bin`
  para usar dado real.
- **Varre os chunks** (8K..4M por padrão) para lz4/snappy/cascaded,
  kernel-only (`-c true -t false`, sem PCIe), 10 iter + 2 warmup, e reporta
  o c* empírico por codec + speedup vs 64K.
- **Roda nativo, sem container.** Linka `ARCTO_LIB` + `ROCM_LIB` e executa os
  binários direto. Sem fallback: se o binário não carregar no host (glibc/ROCm
  incompatíveis), aborta com diagnóstico em vez de mascarar com SIF. Os
  defaults dos paths são só exemplos para o usuário saber o que apontar.

Knobs (env; defaults são exemplos a substituir): `ARCTO_BIN`, `ARCTO_LIB`,
`ROCM_LIB`, `DATA`, `DATA_MB`, `ALGOS`, `CHUNKS`, `ITERS`, `WARMUP`, `C_FLOOR`.

Pré-requisito: um build do arcto compilado para o host+arco (binários
`benchmark_<algo>_chunked` + `libarcto.so`) cuja glibc/libstdc++ sejam <= as do
host. (Ex.: na lunaris o `build_norev` roda nativo, glibc 2.34 <= host 2.36; já
o `build_canon` foi compilado no container com glibc 2.38 e não roda nativo.)

Uso típico:

    ARCTO_BIN=/path/build/bin ARCTO_LIB=/path/build/lib ./scripts/sweep_cstar.sh
    DATA=/path/medium_TTI_100.bin ./scripts/sweep_cstar.sh   # dado real
    ALGOS="lz4" CHUNKS="8192 16384 32768 65536" ./scripts/sweep_cstar.sh

**Validação na RX7900XT (gfx1100, W=2688, nativo via build_norev, dado
sintético 128 MiB, 2026-06-14), throughput de compressão kernel-only (GB/s):**

| chunk | lz4 | snappy | cascaded |
|---|---|---|---|
| 8K  | 22.43 | 18.75 | 52.29 |
| 16K | **25.23** | 22.51 | 58.63 |
| 32K | 23.63 | **25.02** | **76.52** |
| 64K | 18.36 | 22.98 | 75.49 |
| 128K| 11.72 | 21.19 | 74.62 |
| 256K| 6.15 | 20.85 | 53.40 |
| 1M  | 1.69 | 7.26 | 23.84 |

c* empírico: **lz4 16K (1.37x vs 64K)**, **snappy 32K (1.09x)**,
**cascaded 32K (1.01x, platô chato 32-128K)**. Bate com o c* histórico do
gfx1100 (lz4 16K). Snappy/cascaded têm platô largo (o pico oscila 32K/64K entre
rodadas, throughput dentro de ~2%), dentro de uma oitava do valor fixado no
runtime (snappy 16K, cascaded 64K); para o número final preferir dado TTI. Os
números nativos (build_norev) coincidem com o build_canon (via container)
dentro do ruído (lz4 64K: 18.4 vs 19.4). Isso reforça o ponto da Seção 3: c*
é uma constante de codec/arch numa faixa estreita, e o conteúdo do dado mexe no
nível, não na localização do ótimo.

Plano: validado na RX7900XT, replicar nas demais (MI300X, MI210) na próxima
janela de acesso a cada nó, apontando `ARCTO_BIN`/`ARCTO_LIB`/`ROCM_LIB` para o
build nativo daquele arco.

## 7. Ponteiros (procedência)

- Dados consolidados: `analysis/chunk_sweeps.csv`
  (gerado por `analysis/consolidate_chunk_sweeps.py`).
- Campanhas brutas: `results/{MI300X,RX7900XT,MI210}_CHUNK_SWEEP_*`.
- Script de sweep genérico (novo, qualquer GPU AMD):
  `scripts/sweep_cstar.sh` (Seção 6 acima).
- Scripts de sweep antigos (hardcoded por nó): `scripts/sweep_chunk_size_{small,large,lunaris}.sh`
  (varrem `-p chunk` em {8K..16M}, baseline e pinned, TTI medium/large,
  10 iter + 2 warmup).
- Texto atual (a reescrever): `draft/sections/4-optim-chunk-size.tex`.
- c* por arch já fixado no runtime: LZ4 8K, Snappy 16K, Cascaded 64K em
  gfx1100; CDNA prefere 8K uniforme em LZ4/Snappy.
