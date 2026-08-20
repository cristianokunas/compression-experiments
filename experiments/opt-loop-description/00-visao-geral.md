# A história do laço de otimização, contada para a tese

Este diretório documenta, em prosa, a investigação que substituiu o resultado de
c\* na tese: o que foi tentado, o que cada tentativa mediu, o que caiu, o que
sobreviveu, e por quê. É material-fonte para a escrita dos capítulos de
metodologia e de resultados. Os dados brutos, os commits e os vereditos formais
estão em `../EXPERIMENT-LOG.md` e `../OPTIMIZATION-LOOP.md`; aqui está a
narrativa.

## O arco em um parágrafo

A tese propôs otimização guiada por perfilamento (RQ2). O primeiro resultado
apresentado sob essa bandeira, o dimensionamento de chunk c\*, revelou-se um
ajuste por varredura que movia duas variáveis ao mesmo tempo e creditava a
errada. Ao desacoplar as variáveis, o tamanho da tabela de hash do LZ4 emergiu
como o fator real, com ganhos de +85 % no gfx1100 e +1745 % na MI210 sem custo
de razão de compressão. Três explicações candidatas para esse efeito foram
testadas com experimentos dedicados: ocupação de waves (refutada), custo de
inicialização da tabela (refutada), e residência de cache das sondas
(inicialmente descartada por erro de análise, depois reaberta e validada). O
estado final é uma predição derivável de duas propriedades do dispositivo,
`tabela* ≈ L1 / waves_por_CU`, confirmada no ponto de inflexão em três
arquiteturas, com o mecanismo isolado por um experimento controlado de saída
byte-idêntica. Esse resultado é a justificativa quantitativa do redesenho
LDS que a proposta promete (E11), que passa a ser a próxima edição do laço.

## Ordem de leitura

| Arquivo | Conteúdo |
|---|---|
| `01-antecedentes-cstar.md` | o resultado que caiu e por que a queda fortalece a tese |
| `02-fase-kernel-opt.md` | E01 a E07, a fase de julho e a lição wave32/wave64 |
| `03-E06-empacotamento.md` | a hipótese de ocupação e o resultado neutro |
| `04-E08-tabela-de-hash.md` | o desacoplamento e o efeito medido |
| `05-E09-residencia-de-cache.md` | a hipótese central: queda errada, reabertura, validação |
| `06-E10-laco-de-limpeza.md` | A1 e A2, a falha do portão e a refutação limpa |
| `07-E11-direcao-lds.md` | a direção aberta e sua motivação quantitativa |
| `08-licoes-metodologicas.md` | o que o processo ensinou, positivo e negativo |

## Linha do tempo

| Data | Evento |
|---|---|
| jul/2026 | fase kernel-opt (E01 a E07); E06 medido neutro na MI300X |
| 2026-08-19 | descoberta do acoplamento tabela/chunk (E08); campanhas em lunaris, luxembourg e lyon; decisão de remover c\* e reversible |
| 2026-08-20 | resgate das campanhas dos três nós; E09 formulada, "refutada" e reaberta; E10 formulada, A1 falha o portão, A2 refuta E10; A3 encontra a parede de PMC; A4 valida E09 na forma revisada |

## O que cada caso entrega para o texto da tese

- **Metodologia (cap. 5)**: o laço em quatro passos com portão de correção,
  uma tentativa por commit, veredito por arquitetura, replay entre GPUs por
  hash. `08-licoes-metodologicas.md` traz os incidentes que justificam cada
  regra, o que é mais convincente do que declarar as regras em abstrato.
- **Resultados (cap. 6)**: E08 é o efeito; E09 é a explicação; E06 e E10 são
  os controles negativos que descartam as explicações rivais; A4 é o
  experimento controlado que fecha a atribuição.
- **Próximos passos**: E11 e a fila de replay CDNA, com as predições já
  registradas antes da medição.
