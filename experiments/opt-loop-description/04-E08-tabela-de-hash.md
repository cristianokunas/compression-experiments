# E08: o desacoplamento tabela/chunk e o efeito medido

## A pergunta

Se `HT = min(roundUpPow2(chunk), MAX_HASH_TABLE_SIZE)` solda a tabela ao chunk,
qual das duas variáveis as varreduras de chunk estavam de fato medindo?

## O que foi feito

Um patch de sete linhas (commit `f3e70b7`) tornou `MAX_HASH_TABLE_SIZE`
sobrescrevível em tempo de build (`-D ARCTO_LZ4_MAX_HASH_TABLE_SIZE=N`), com o
padrão reproduzindo o valor herdado do nvCOMP exatamente. Um build por tamanho
de tabela, chunk fixo, e a varredura roda com o rótulo derivado de um carimbo
`HT_SIZE` gravado no diretório de build (nunca digitado; ver lições).

Campanhas em três arquiteturas, entrada TTI densa, chunk fixo em 64 KiB:

| GPU | arquitetura | tabela herdada (16384) | melhor medida | ganho |
|---|---|---|---|---|
| RX 7900 XT | gfx1100, wave32, L1 32 KB | 6,88 GB/s | 30,80 (ht128) | +348 % |
| MI210 | gfx90a, wave64, L1 16 KB | 2,40 GB/s | 44,28 (ht256) | **+1745 %** |
| MI50 | gfx906, wave64, L1 16 KB | 1,86 GB/s | 8,12 (ht64) | +337 % |

Com a tabela dimensionada, a MI210 sai de 4x mais lenta que a RX 7900 XT para
mais rápida, no mesmo caso. Quanto maior a razão tabela/L1, pior o baseline e
maior o ganho.

## O portão de razão

Verificado em **bytes exatos**, não razão arredondada, na escada de
compressibilidade completa (zeros, binary, random, TTI esparso, TTI denso):
o pior custo de encolher de 16384 para 128 entradas é **+0,0075 %** de tamanho
de saída, e no TTI esparso a saída é **byte-idêntica em todos os tamanhos**.
A tabela grande não comprava nada neste dado: os matches de longa distância
que ela reteria não existem no wavefield. De quebra, o TTI denso comprime a
0,9961x (o LZ4 o expande levemente), medindo em vez de afirmar o regime onde
a tese argumenta que lossless byte-level não se paga.

## Pontos positivos

- Efeito grande, reprodutível (as medições de agosto batem com as de maio
  dentro do ruído) e barato de aplicar: um flag de build, nenhum redesenho.
- O portão de bytes exatos fechou de saída a objeção "troca razão por
  velocidade".
- A assinatura entre arquiteturas (ganho cresce com tabela/L1) já apontava a
  família de explicação certa antes de E09 ser formulada.

## Pontos negativos

- A campanha nasceu **não versionada**: patch solto na árvore de três nós de
  cluster, resultados em diretórios sem git. Só depois do resgate (299 arquivos
  de lunaris, 163 de luxembourg, 22 de lyon) o achado ficou seguro. O maior
  risco de perda de toda a investigação foi este.
- Efeito sem explicação é meio resultado: por si só, E08 não dizia por que a
  tabela importa, e a primeira explicação proposta (E09 na forma estrita)
  quase foi descartada por erro de análise.
- A MI210 nunca foi medida abaixo de 256 entradas; o "ótimo" dela é, em parte,
  artefato do alcance da varredura. Pendente no replay CDNA.

## Direção seguida

O efeito abriu três explicações candidatas: ocupação (E06, já refutada),
inicialização da tabela (E10), e residência de cache das sondas (E09). As duas
últimas foram testadas em sequência, e a atribuição fechou em E09/A4.
