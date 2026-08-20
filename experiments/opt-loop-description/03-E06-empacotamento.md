# E06: empacotamento de chunks por bloco (hipótese de ocupação)

## A hipótese e de onde ela veio

O perfilamento na MI300X (rocprofv3, duas fases: kernel-trace para localizar,
PMC para diagnosticar) mostrou o kernel de compressão LZ4 como 92 % do tempo
total e 18,5x mais lento por chamada que o Cascaded no mesmo input, com:

- `OccupancyPercent` = 9,35 % contra ~9728 slots de wave
- `SQ_WAVES` = 1600 (uma wave por chunk, 100 MB / 64 KiB)
- `VALUUtilization` = 94,54 % (a wave trabalha duro quando roda)
- `MemUnitStalled` = 2,29 % (não é memória)

Diagnóstico: fome de waves. O kernel lançava um bloco de uma wave por chunk.
Predição registrada: empacotar N=4 chunks por bloco elevaria a ocupação de
9,35 % para ~37 % e a vazão de 4,67 para 18 a 20 GB/s.

## O que foi feito

Commit `84423b4`: `LZ4_COMP_CHUNKS_PER_BLOCK = 4`, lançamento 2D, guarda de
bloco de cauda com retorno uniforme por wave (seguro para os syncwarp
internos). Mudança cirúrgica, quatro pontos no código.

## O que foi medido

**Neutro na MI300X.** O rocprofv3 confirmou que a geometria mudou de fato e que
o tempo de kernel ficou idêntico (~21,8 ms). No gfx1100, razão e vazão
preservadas (sanidade). A tag `archive/wave64-n4-neutral` registra o veredito:
a hipótese de fome de waves foi refutada; a compressão é limitada por VALU por
CU.

## Pontos positivos

- Hipótese quantitativa registrada antes da medição, com contador nomeado.
- O resultado negativo foi arquivado com o mecanismo verificado (geometria
  mudou, tempo não), o que é exatamente o que um controle negativo precisa ter.
- Reinterpretado depois: o neutro de E06 é consistente com qualquer custo que
  seja por chunk e não por wave, o que o tornou evidência também na análise de
  E10.

## Pontos negativos

- O veredito viveu **apenas na mensagem da tag**. Meses depois, o empacotamento
  foi descrito como "diagnosticado, falta implementar" no planejamento, porque
  ninguém lê mensagens de tag antes de planejar. Esse incidente é a
  justificativa direta da existência do `EXPERIMENT-LOG.md`.
- A predição errou por assumir que ocupação era o limitador; o contador que
  distinguiria (tráfego de cache) não foi coletado na época.

## Direção seguida

Com ocupação descartada, as candidatas restantes para o efeito da tabela eram
custo de inicialização (E10) e comportamento de cache das sondas (E09). As
duas foram testadas com experimentos dedicados.

Revisita registrada no log: re-rodar N=4 na CDNA dentro do replay, agora com o
quadro de E09 fechado, para documentar a interação ocupação x pegada de linhas
(mais waves residentes multiplicam a pegada agregada, então as duas alavancas
se opõem).
