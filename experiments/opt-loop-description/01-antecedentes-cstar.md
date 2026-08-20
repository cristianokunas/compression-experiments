# Antecedentes: o c\* e por que ele caiu

## O que era

O c\* era o "primeiro resultado concreto do método guiado por perfilamento" que
a proposta apresentou: uma varredura de tamanhos de chunk por arquitetura e
codec, selecionando o máximo de vazão, com um argumento de saturação
explicando por que o ótimo seria uma constante pequena de cada parte. O número
citado era de até 1,6x para o LZ4 no gfx1100 ao sair do padrão herdado de
64 KiB para 8 KiB (verificado no dado: 1,59x; na MI210, 1,33x). A explicação
atribuía o ótimo a um piso de custo por chunk (`c_floor`): overhead de
lançamento e metadados, reset do dicionário, perda de razão em janela pequena,
cauda descoalescida.

## Por que caiu

Dois defeitos independentes, cada um suficiente.

**O botão movia duas variáveis.** `LZ4Types.h` calcula
`HT = min(roundUpPow2(chunk), MAX_HASH_TABLE_SIZE)`: o tamanho da tabela de
hash é soldado ao tamanho do chunk. Encolher o chunk aumenta o número de waves
(mais paralelismo) e ao mesmo tempo encolhe a tabela por wave (menos pegada de
cache). A varredura caminhava numa diagonal de uma superfície bidimensional e
reportava a diagonal como se fosse um eixo. Ao fixar o chunk em 64 KiB e variar
só a tabela (E08), o ganho apareceu inteiro na tabela: a varredura de c\*
encontrou 1,33x na MI210 onde havia 18,5x parados.

**A explicação não batia com os contadores.** O perfilamento na MI300X mediu
`MemUnitStalled` em 2,29 % e `VALUUtilization` em 94,54 % no kernel de
compressão: nenhuma assinatura de overhead por chunk dominando. O que os
contadores mostravam era outra coisa (fome de waves, que por sua vez também
se revelou insuficiente; ver E06).

## A decisão de remover

O c\* foi removido por completo: da tese em elaboração, do repositório do
artigo e das ferramentas. Dois critérios pesaram. Primeiro, o dono do trabalho
não conseguia derivar o resultado, e um resultado que não se sabe derivar é
passivo numa defesa, não ativo. Segundo, o critério prospectivo que também
removeu o ZFP reversible: material cuja conclusão está errada ancora qualquer
retomada futura num ponto de partida quebrado. O índice do que foi removido e
como recuperar está em `compression-experiments/HISTORY.md` (tudo alcançável
no commit `674fe50`).

## Pontos positivos

- A medição em si estava correta; o erro era de atribuição. Os dados das
  varreduras seguem recuperáveis no histórico.
- A queda fornece a posição de defesa mais forte que o resultado original:
  "estávamos medindo a variável errada, e substituímos olhando para o lugar
  certo" é uma demonstração do método funcionando, não um recuo.
- A remoção forçou a formalização do laço (`OPTIMIZATION-LOOP.md`), com
  hipótese falsificável nomeando contador antes de qualquer edição.

## Pontos negativos

- O resultado viveu meses como "completo" na proposta e no texto, incluindo um
  modelo derivado (`W_kernel_sat` no `HostBatchAdaptive`) construído sobre a
  variável errada, que precisa ser revisitado antes de qualquer uso.
- A proposta defendida cita o c\* como peça central da RQ2 e não pode mais ser
  alterada. A tese final precisa narrar a substituição explicitamente.

## Direção seguida

O desacoplamento das duas variáveis virou o experimento E08, e a pergunta
"o que o tamanho da tabela realmente faz" virou a linha E09/E10/A4 que ocupou
o restante da investigação.
