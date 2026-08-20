# SSCAD 2026 — Plano do Artigo: Compressão Híbrida Adaptativa para Aplicações Stencil

> Versão de trabalho — 05 ago 2026. Documento-fonte para o texto de venda
> (abstract/intro) e para alinhamento com orientador/coautores.

---

## 0. Fatos da conferência

| Item | Valor |
|---|---|
| Evento | SSCAD 2026, Natal/RN, 3–5 nov 2026 |
| Deadline oficial | **07/08/2026** (contamos com prorrogação ≥2 semanas — monitorar https://sscad2026.imd.ufrn.br/cfp/ e JEMS3) |
| Notificação / camera-ready | 28/09 / 19/10 |
| Formato | até 12 páginas + referências, template SBC, PT ou EN |
| Submissão | JEMS3 (https://jems3.sbc.org.br/sscad2026) |
| Anais | SBC OpenLib (SOL) |

## 1. O que estamos vendendo (a tese do artigo)

**Em uma frase:** *nenhum compressor único é bom durante toda uma simulação de
propagação de ondas — um seletor por snapshot, de custo desprezível, escolhe
entre lossless rápido (quando a grid ainda é esparsa) e lossy error-bounded
(quando a grid densifica), obtendo o melhor dos dois regimes sem degradar o
resultado científico final.*

**A observação que sustenta tudo (e vira a figura motivadora):** o campo de
onda nasce zerado e é populado progressivamente conforme a frente de onda se
propaga a partir da fonte. Nos snapshots iniciais, a fração de zeros é altíssima
e um compressor byte-level (LZ4) entrega razões enormes com custo mínimo —
e ainda por cima **lossless**. Conforme a grid densifica, a razão do LZ4
colapsa para ~1,03× (resultado já publicado no nosso ICCSA 2026: lossless
byte-level é inútil em wavefield denso). Nesse regime, só compressão lossy
error-bounded (ZFP fixed-accuracy) rende (16–31× na nossa campanha). O ponto de
cruzamento é detectável de forma trivial e barata: **fração de zeros do frame**
(amostrada) ou feedback da razão obtida no frame anterior.

**Propriedade elegante para vender:** o híbrido é *lossless sempre que
possível, lossy só quando necessário*. Comparado ao ZFP puro, injeta erro em
menos frames (os iniciais ficam bit-exatos de graça); comparado ao LZ4 puro,
entrega a razão que o lossless não consegue nos frames densos. E o stream misto
continua autodescritivo (cada frame declara seu codec no próprio header).

### ⚠ Nuance de honestidade que MOLDA o texto de venda (medido em 05/08)

O ZFP comprime frames esparsos AINDA MELHOR que o LZ4 (blocos 4³ de zeros
viram ~1 bit/bloco): no frame 100% zerado, LZ4 dá 245× e ZFP 2048×. Ou seja,
**o argumento do híbrido NÃO é razão de compressão nos dois regimes** — em
razão pura, ZFP domina sempre. O que o híbrido vende é:

1. **Fidelidade grátis**: nos frames esparsos, LZ4 é bit-exato COM razão alta
   (40× a 98% de zeros). Política "lossless enquanto render" → zero erro
   injetado no início da simulação, importante p/ correlação do RTM e
   reprodutibilidade.
2. **Custo de razão desprezível**: híbrido θ=50% perde só ~9% de volume vs
   ZFP-puro (2,26× vs 2,47× @1e-13) e mantém 19/101 frames bit-exatos.
3. **Velocidade** (a confirmar na campanha GPU): decode LZ4 ≫ decode ZFP,
   relevante no restore do backward (mamute) e no fletcher_decompress.
4. **Generalidade**: byte-level funciona p/ qualquer conteúdo de dump;
   error-bounded exige semântica float — o seletor escolhe o certo por frame.

### Números medidos (TTI 200³/grid 240³, 1000 passos, 101 snapshots, phoenix)

| Política | Volume | Razão | Frames bit-exatos |
|---|---|---|---|
| raw | 5,58 GB | 1× | 101 |
| LZ4 puro | 4,21 GB | 1,33× | 101 (mas volume ruim) |
| ZFP acc 1e-13 puro | 2,26 GB | 2,47× | 0 |
| **Híbrido θ=50% @1e-13** | 2,47 GB | 2,26× | **19** |
| ZFP acc 1e-6 puro | 0,82 GB | 6,84× | 0 |
| **Híbrido θ=50% @1e-6** | 1,04 GB | 5,37× | **19** |

Crossover: LZ4 cai abaixo de 2× no frame 19 (~19% da simulação). Platô de
9,7% de zeros no regime denso = células de halo (4/lado: 1−232³/240³) —
por isso LZ4 denso dá 1,10× aqui vs 1,03× do ICCSA (sem halo no dado).

### Direção v2 (pós-feedback do mecanismo, 05/08 noite)

Fatos medidos no MI210 (c*=8K, por frame) que corrigem o texto de venda:

1. **Encode invertido vs intuição de CPU**: ZFP encode é rápido e quase flat
   (2,6→5,8 ms/frame; 0,49 s total) e LZ4 é o lento e content-dependent
   (9,6→32,3 ms, 3,4×). Frase boa: "na GPU, o encode LZ4 saiu ~6× mais lento
   que o ZFP". O ganho de tempo do híbrido sobre zfp no v1 era dispersão de
   E/S (híbrido escreve +130 MB e gasta +0,15 s de encode) — expectativa p/
   30 reps: empate no IQR.
2. **Piso de ~3 MB do ZFP GPU em frames esparsos**: é o índice variable-rate
   com granularity=1 escolhido PELO NOSSO wrapper (ZFPBatch.cpp:170-176;
   (blocks+1)×8 B = 2,99 MB em 288³; o decoder HIP canônico suporta
   granularity>1). NÃO usar como motivação no paper ("conserte seu ZFP");
   nota de implementação + melhoria futura. Volume esparso = 1,4% do total.
3. **"LZ4 ganha em volume nos esparsos" é FALSO exceto no frame 0** (0,78 vs
   3,0 MB; já no frame 2 ZFP escreve menos). Não entra como claim.
4. **Outliers de encode LZ4 (80-295 ms) são ESTOCÁSTICOS** (frames diferentes
   entre reps; zfp tem zero outliers) — não é realloc determinístico; total
   LZ4 oscila 18% entre reps. Mitigação: medianas POR FRAME sobre 7 reps
   (5 extras já staged) + reportar dispersão.
5. **Ponto de operação defensável: θ=90** (0,54% volume e ~0,5% encode a mais
   que zfp puro, 9 frames bit-exatos; θ=75 cobra 3,5% por 17 frames — o
   joelho é o que a figura do sweep mostra).
6. **Decode é o eixo que pode devolver o claim forte** (backward do mamute lê
   todos os frames): instrumentado (FLETCHER_DECOMP_LOG, commit 954635d),
   bench lz4/zfp/hybrid90 pronto p/ rodar pós-sweep.
7. **Figura de abertura reformulada**: dados de GPU (288³ efetivos, declarar
   halo), 3 painéis com x compartilhado — %zeros (baixo), bytes/frame (meio),
   ms de encode/frame (cima); só acc 1e-13; sem título interno (vira caption
   SBC). A da CPU (240³) não entra no paper. Legenda honesta: ZFP domina em
   razão nos dois regimes; o que muda ao longo da simulação é o custo
   relativo dos codecs.

### Resultados finais v2 (30 reps, c*=8K, MI210, 06/08 ~00h CEST)

| Config | Mediana | IQR | Volume | Razão |
|---|---|---|---|---|
| raw | 14,55 s | 14,41–15,41 | 9,65 GB | 1× |
| lz4 | 15,84 s | 15,62–16,29 | 6,89 GB | 1,40× |
| zfp | 12,79 s | 12,67–13,22 | 3,72 GB | 2,59× |
| **hybrid90** | **12,52 s** | 12,39–12,91 | 3,74 GB | 2,58× |
| hybrid75 | 12,64 s | 12,58–13,04 | 3,85 GB | 2,51× |
| hybrid100 | 12,71 s | 12,50–13,43 | 3,72 GB | 2,60× |

Leituras: (a) hybrid90 ≤ zfp consistentemente mas com IQRs sobrepostos →
claim = "iguala o melhor puro; −14% tempo e −61% volume vs raw; 9 frames
bit-exatos de graça"; (b) custo do seletor ~1% (hybrid0 16,00 vs lz4 15,84,
no ruído); (c) lz4 puro é dominado em TUDO na GPU (encode content-dependent
3,4× e mais lento que zfp, volume pior, decode mais lento) — extensão
temporal do resultado do ICCSA. **Decode (medido, 3 reps): ZFP 0,68–3,8
ms/frame vs LZ4 2,9–4,7; totais 0,38 vs 0,60 s — irrelevante no caso GPU e
SEM dominância lz4; a hipótese decode-domina migra para o caso mamute CPU
(lz4 multi-GB/s vs zfp serial), onde será medida.** Figura do mecanismo
(3 painéis, dados GPU 288³, medianas 7 reps):
`/scratch/cakunas/hybrid-motivating/fig_mecanismo.{png,pdf}` — nota de
caption: pico no frame 0 = warmup de 1ª chamada (ambos os codecs).

### Contribuições (claims)

1. **Caracterização temporal da compressibilidade** de campos de onda em
   aplicações stencil: fração de zeros e razão de compressão por snapshot ao
   longo da simulação, mostrando os dois regimes e o cruzamento (novidade: a
   literatura e nossos papers anteriores tratam a compressibilidade como
   propriedade estática do dado).
2. **Política de seleção híbrida por snapshot** (threshold θ sobre fração de
   zeros; alternativa: feedback da razão anterior) com custo de decisão
   desprezível, e formato de stream misto autodescritivo.
3. **Demonstração em DUAS aplicações reais em pontos diferentes do pipeline**:
   - **Fletcher (GPU/HIP, ARCTO)**: dumps de snapshots para disco na
     propagação forward — reduz tempo total e volume de E/S.
   - **Mamute (LAPPS/UFRN, CPU)**: armazenamento do wavefield forward do
     RTM/FWI consumido pelo backward — reduz E/S, e no tier de memória
     multiplica a capacidade efetiva de RAM pela razão de compressão.
4. **Validação na métrica que importa**: além de erro numérico (max|err|,
   PSNR), a **imagem migrada final do RTM** (`rtm_image.bin`) com e sem
   compressão híbrida — o resultado científico não degrada.
5. Sweep do threshold θ: os extremos recuperam LZ4-puro e ZFP-puro (nossas
   baselines já medidas); o meio mostra o trade-off razão × erro acumulado.

## 2. Framing: Fletcher + mamute confunde?

**Decisão: o paper é sobre a TÉCNICA para a classe "aplicações stencil de
propagação de ondas"; Fletcher e mamute são casos de uso.** Não confunde se a
estrutura deixar claro que cada caso responde uma pergunta diferente:

- O **Fletcher** responde: *quanto tempo e volume o híbrido economiza no
  caminho de produção de snapshots em GPU?* (nosso terreno consolidado — infra
  ARCTO, campanha, baselines medidas)
- O **mamute** responde: *o que acontece com o resultado científico (imagem
  migrada) e como o híbrido se compara às alternativas clássicas de gestão de
  wavefield (disco puro, checkpointing/Revolve, effective boundary)?*

Isso segue exatamente a sugestão da banca da proposta: não vender o Fletcher
como "a aplicação", e sim a ferramenta/técnica como eficaz para o tipo stencil.
Estrutura anti-confusão: uma seção da técnica (agnóstica de aplicação), depois
"Estudos de caso" com subseções separadas e uma discussão unificada no final
(tabela única comparando os dois). Nunca intercalar resultados dos dois casos
numa mesma figura.

**Plano B (gate):** se o mamute atrasar, o paper se sustenta como
Fletcher + framing stencil + qs-rtm como demonstração qualitativa, e o estudo
completo do mamute vira future work. Decente, mas perde o bônus da imagem.

## 3. O que já existe (não precisa fazer)

- ARCTO na main: LZ4/Snappy/Cascaded GPU + ZFP canonical (acc/prec/rate),
  streams autodescritivos; roda em AMD e NVIDIA (branch cuda-portable mergeada).
- fletcher-modern: interface `Compressor` limpa; dumps por frame
  (`[uint64 nbytes][payload]`); overlap de E/S com pool auto-dimensionado;
  `fletcher_decompress` para validação.
- Campanha end-to-end (fletcher-bench): baselines raw/lz4/snappy/cascaded/zfp
  medidas em RX7900XT (lunaris), L40S (grace2), MI300X (vianden) — ex.
  RX7900XT 408³: zfp −31% tempo total, −55% volume vs raw. Rate-distortion do
  ZFP: razão 31×→16× (acc 1e-1→1e-13), erro real acompanha a tolerância até o
  piso do float32.
- Fidelidade ZFP: tabela PSNR/RMSE/MaxAbsDiff (18 linhas) na RX7900XT.
- **Mamute validado NESTA máquina (phoenix, 05/08)**: branch `dev` compila
  limpo (worktree `/scratch/cakunas/mamute-dev`), quick-start RTM ponta a
  ponta OK (20 tiros, 963 s, `rtm_image.bin` gerada). Ponto de integração:
  `src/core/common/wavefield/ManageWavefield{,MD}.{h,cpp}` — interface de 3
  métodos, implementação MD com 164 linhas; knob `memory` no TOML controla o
  split RAM→disco; um manager serve RTM+FWI+LSM. Deps: liblz4 do sistema +
  zfp CPU vendorizado no arcto.
- Publicações do grupo que ancoram related work: SSCAD 2025 (compressão CPU
  p/ E/S sísmica), ICCSA 2026 (caracterização lossless GPUs AMD), CARLA 2024
  (overlap E/S), CARLA 2025 (RTM SYCL).

## 4. O que falta implementar

### 4.1 Fletcher (fácil — 1–2 dias)
- `HybridCompressor` implementando `fletcher::Compressor`: amostra fração de
  zeros do frame na GPU (redução simples/strided) → se ≥ θ usa LZ4, senão ZFP
  acc; registra decisão por frame no log/CSV.
- Ajuste no `fletcher_decompress`: distinguir por frame o magic ARCTO (manager)
  do header ZFP (hoje o codec é único por arquivo, vem do header `.rsf`).
- Figura motivadora: **PRONTA (draft, 05/08)** —
  `/scratch/cakunas/hybrid-motivating/fig_motivadora.{png,pdf}`, dados em
  `frame_analysis.csv` (mesmo dir), gerada de dump CPU (a compressibilidade é
  propriedade do dado, não do dispositivo; refazer estética final no pipeline
  R do grupo). Ferramenta: `analyze_frames.c` (scratchpad da sessão; copiar p/
  repo compression-experiments/scripts).

### 4.2 Mamute (2–3 dias de código + validação)
- `ManageWavefieldCompressed` (≈300 linhas, clonando `ManageWavefieldMD`):
  `copyCurrNoBorders` → staging contíguo → seletor (%zeros) → LZ4
  (liblz4) ou ZFP-acc (libzfp serial) → tier RAM (frames comprimidos em
  `vector<vector<uint8_t>>`) ou append em disco com índice por frame
  (offsets variáveis).
- Registrar `hybrid` (e `lz4`/`zfp` puros p/ ablation) no
  `ManageWavefieldFactory` + parâmetro no TOML + doc em
  `docs/features/_parameters.md`.
- Validar: round-trip bit-exato no caminho LZ4; diff da `rtm_image.bin`
  (max|err|, PSNR, visual) no caminho ZFP/híbrido, via `qs-rtm.sh` e depois
  `qs-fwi.sh`.

## 5. Desenho experimental

### 5.1 Caso Fletcher — **GPU AMD** (decisão 05/08: reservar nó AMD no outro cluster, já que lunaris e nós NVIDIA estão ocupados; ARCTO é a história AMD do doutorado)
| Fator | Níveis |
|---|---|
| Codec | raw, lz4, zfp-acc, **hybrid(θ)** |
| Threshold θ | 0 (≡lz4 sempre; isola custo do seletor), 25%, 50%, 75%, 90%, 100% (≈zfp; LZ4 só em frame 100% zerado) |
| Grid | 248³ e 392³ (presets da campanha) |
| tmax | preset da campanha (~201 frames) |
| Reps | 30, mediana + IQR (protocolo fletcher-bench) |

Métricas: tempo total, tempo de E/S, volume escrito, razão por frame,
distribuição das decisões do seletor, custo do seletor (µs/frame), max|err|
global.

### 5.2 Caso mamute (CPU, phoenix ou nó do PCAD — CPU é escolha deliberada: mostra a política agnóstica de backend; o caminho GPU do mamute é CUDA-only, ignora `wave_manager` e fica p/ o paper grande de RTM)
| Fator | Níveis |
|---|---|
| wave_manager | disk, chk (Revolve), eb, **hybrid**, lz4-puro, zfp-puro |
| Modelo | camadas ~200³ (gerado por `scripts/data/velocity.py`), ns ~1500–2000 |
| memory (TOML) | apertado (força disco) e folgado (só RAM) |
| Tiros | 4–8 (suficiente p/ mediana estável) |

Métricas: tempo total por tiro, bytes escritos/lidos no `wf_history`, pico de
RAM (o log já reporta), nº de frames em RAM vs disco, e **imagem migrada**:
max|err| e PSNR vs baseline `disk`, + figura lado a lado.

### 5.3 Fidelidade
- Reusar tabela de fidelidade ZFP existente para escolher a tolerância de
  operação (ex.: acc 1e-6 como ponto de produção, 1e-13 como conservador).
- Erro acumulado híbrido vs ZFP-puro: mesmo tol, híbrido injeta erro só nos
  frames densos → argumento "lossless quando possível".

## 6. Figuras-alvo (7 + 1–2 tabelas)

1. **Fig. 1 (motivadora)**: %zeros e razão LZ4 por frame ao longo da simulação,
   linha do ZFP constante, zona de cruzamento destacada. *(em produção)*
2. Fig. 2: diagrama da técnica (seletor + stream misto autodescritivo) — os
   dois pontos de integração (dump forward / save-restore RTM).
3. Fig. 3: Fletcher — tempo total e volume vs codec (raw/lz4/zfp/híbrido),
   2 grids, com decisões do seletor anotadas.
4. Fig. 4: sweep de θ — razão total × erro acumulado (Pareto; extremos = puros).
5. Fig. 5: mamute — tempo/bytes/RAM vs wave_manager (disk/chk/eb/híbrido).
6. Fig. 6: imagens migradas lado a lado (baseline vs híbrido) + mapa de
   diferença — **a figura-bônus**.
7. Fig. 7 (opcional): erro acumulado por frame, híbrido vs zfp-puro.

## 7. Cronograma (assumindo deadline ~21/08)

| Dias | Entrega | Gate |
|---|---|---|
| 1–2 | Seletor híbrido no fletcher-modern + decode misto; figura motivadora pronta | G1: híbrido funciona; senão simplificar p/ feedback de razão |
| 3–4 | Sweep θ no lunaris (madrugada) | — |
| 5–7 | `ManageWavefieldCompressed` + validação qs-rtm/qs-fwi | G2: round-trip ok e imagem limpa; senão mamute vira qualitativo (Plano B) |
| 8–10 | Campanha mamute (modelo ~200³) | — |
| 7–13 | Escrita 12 p. PT (paralela às campanhas) | G3 (d11): figuras congeladas |
| 14 | Revisão + submissão | — |

Se a prorrogação for de só 1 semana: Fletcher completo + demo qs-rtm
(integração mamute cabe; campanha grande não).

## 8. Encaixe estratégico (o que este paper NÃO queima)

| Munição reservada | Onde vai |
|---|---|
| Otimização da biblioteca (chunk sizing c*, pinned, adaptive, PMC) | ARCTO-optim → **Euro-Par'27** |
| Estudo cross-vendor AMD vs NVIDIA | paper próprio (venue internacional) |
| ZFP reversible GPU (reimplementação) | diferencial futuro do ARCTO |
| Overlap "Tuning the Overlap" (K*, threads, storage) | CARLA/ERAD futuro — future work mútuo: "compressão reduz t_io e desloca K*" |
| Integração GPU do mamute (d_ckpt, branch 274) | paper grande de RTM (ex-C5) |
| Consolidação | periódico, depois |

O ARCTO aparece aqui como *ferramenta* (citado), sem claims de otimização
interna. Vínculo Petrobras: dados TTI representativos de O&G, decision
rule operacional (θ), agradecimento ao grant.

## 9. Riscos

| Risco | Prob. | Mitigação |
|---|---|---|
| Deadline NÃO prorrogado | média | pacote vai p/ CARLA 2027/SSCAD 2027; nada se perde (tudo serve à tese) |
| Frames iniciais não tão esparsos (fonte injeta cedo) | baixa | figura motivadora (hoje) responde isso ANTES de codar o resto |
| Decode misto no fletcher_decompress complicar | baixa | tag de 1 byte por frame como fallback |
| Restore do mamute com índice variável bugar backward | média | validar round-trip bit-exato antes da campanha (G2) |
| lunaris ocupada/indisponível | baixa | campanha Fletcher também roda em outro nó AMD; CPU do phoenix p/ mamute |
| Revisor: "seletor é simples demais" | média | vender a caracterização temporal + validação de imagem + 2 apps; simplicidade é feature (custo zero, adoção trivial) |

## 10. Título de trabalho (opções)

1. "Compressão Híbrida Adaptativa Lossless/Lossy para Campos de Onda em
   Aplicações Stencil de Alto Desempenho"
2. "Lossless Quando Possível, Lossy Quando Necessário: Seleção Adaptativa de
   Compressores para Simulações de Propagação de Ondas"
3. "Explorando a Esparsidade Temporal de Campos de Onda para Compressão
   Adaptativa em Aplicações Stencil"

## 11. Estrutura sugerida (12 p.)

| Seção | Págs | Conteúdo |
|---|---|---|
| 1. Introdução | 1,5 | dois regimes de compressibilidade; contribuições |
| 2. Fundamentação | 1,5 | stencil/RTM, LZ4 vs ZFP, gestão de wavefield (MD/chk/eb) |
| 3. Trabalhos relacionados | 1,0 | nossos 4 papers + compressão em checkpointing sísmico (Boehm/Calandra/Aupy, Barbosa & Coutinho) |
| 4. Compressão híbrida adaptativa | 2,0 | política, seletor, stream misto, custo |
| 5. Caso 1: Fletcher (GPU) | 2,0 | setup + resultados |
| 6. Caso 2: Mamute RTM/FWI (CPU) | 2,5 | setup + resultados + imagem migrada |
| 7. Discussão | 0,75 | tabela unificada; quando usar; limitações |
| 8. Conclusão | 0,5 | + future work (overlap K*, GPU do mamute, reversible) |
