# E11: a tabela em LDS, a direção aberta

## O que é

O redesenho que a proposta de tese promete textualmente: mover a tabela de
match-finding do LZ4 da memória global para a Local Data Share, o scratchpad
gerenciado por software da unidade de computação, reestruturando a cooperação
de threads para a wavefront de 64 lanes da CDNA. É a próxima edição de código
do laço.

## Por que agora ela tem justificativa quantitativa

Quando a proposta foi escrita, a motivação era qualitativa (LDS é mais rápida
que memória global) e havia uma objeção concreta de ocupação: com a tabela
herdada de 16384 entradas, 32 KB de LDS por chunk deixariam pouquíssimos
workgroups por CU. A investigação mudou os dois lados dessa conta:

1. **A objeção de ocupação dissolveu.** E08 mostrou que os tamanhos úteis são
   256 a 512 entradas (512 B a 1 KB de LDS por chunk), com custo de razão
   máximo de +0,0075 % em bytes exatos. Nesses tamanhos, dezenas de waves por
   CU cabem com folga.
2. **O mecanismo que a LDS remove é exatamente o que foi medido.** E09/A4
   estabeleceram que a vazão é governada pela pegada de linhas de cache das
   sondas contra o cache vetorial por CU: 2,1x de variação só por layout de
   memória, com saída byte-idêntica. A LDS tira as sondas do cache contendido
   por completo; não é uma esperança de que "memória mais rápida ajude", é a
   remoção do gargalo demonstrado.

## Predições a registrar antes de medir

- Com a tabela em LDS, a vazão deve ficar **insensível ao tamanho da tabela**
  na faixa que cabe (a curva monotônica de E08 deve achatar), porque a LDS não
  compete com a janela de dados pelo cache vetorial.
- O ganho sobre o melhor caso global (ht128 contíguo) deve ser positivo mas
  menor que o fosso contig/spread, já que ht128 contíguo já quase não erra
  cache: a LDS ganha nas arquiteturas e tamanhos onde o cache por CU é
  disputado (MI210 com L1 de 16 KB é a melhor candidata a ganho grande).
- Interação com E06 reaberta: com as sondas fora do cache vetorial, elevar a
  ocupação (empacotar chunks) deixa de multiplicar a pegada agregada no L1,
  então o empacotamento pode deixar de ser neutro. Medir separado e depois
  combinado, para a atribuição não se perder.

## Cuidados herdados

- O invariante descoberto por A1 (entradas velhas na primeira janela estouram
  o `convertIdx`) vale para qualquer inicialização preguiçosa da tabela em
  LDS. Limpar LDS é barato, mas se a inicialização for omitida, o guarda de A2
  é obrigatório.
- Regra wave32/wave64 de E07: medir nas duas larguras antes de generalizar; o
  histórico mostra regressões de até 43 % ao transplantar otimizações de uma
  para a outra.
- Portão de razão em bytes exatos em toda variante, como sempre.

## Estado

Aberta, ainda sem tentativa. Entra depois do replay CDNA, que fecha os buracos
de medição de E09 (MI210 abaixo de 256, taxas de acerto via `TCP_*`,
contig/spread em wave64) e fornece a linha de base correta para comparar a
versão LDS no container (ROCm 7.0.1), que é o ambiente que a metodologia
declara.
