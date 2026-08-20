# Lições metodológicas: o que o processo ensinou

Cada regra do `OPTIMIZATION-LOOP.md` existe porque um incidente concreto a
justificou. Este arquivo conta os incidentes, porque para o capítulo de
metodologia eles valem mais do que as regras enunciadas em abstrato.

## 1. O rótulo tem que derivar do build, nunca ser digitado

No primeiro teste da saída por repetição, duas configurações rotuladas
`ht16384` e `ht512` reportaram ambas ~6,9 GB/s: as duas tinham invocado o
mesmo binário padrão, e o rótulo mentiu na primeira oportunidade. Desde então
cada diretório de build carrega um carimbo (`HT_SIZE`, `ATTEMPT` com o commit)
e o runner lê de lá. Ainda assim o incidente se repetiu em forma branda: os
tags `a1_*` nos resultados de A2 vieram do nome da árvore, não da tentativa, e
a atribuição correta dependeu do carimbo. Rótulo que não deriva do artefato
medido eventualmente mente.

## 2. O portão de correção antes de qualquer número de desempenho

A tentativa A1 falhou com acesso ilegal à memória na primeira execução. Sem o
portão, essa mudança teria parecido boa (ou neutra) em algum caso pequeno e o
acesso selvagem apareceria semanas depois, como corrupção intermitente dentro
da aplicação, sem trilha de volta ao laço de limpeza. O portão tem três
camadas, e as três trabalharam: round-trip bit a bit (o benchmark compara o
descomprimido byte a byte com a entrada), status de decompressão por item, e
razão em **bytes exatos** na escada de compressibilidade. A camada de bytes
exatos existe porque perda de match é silenciosa: a saída continua válida, o
round-trip passa, e só o tamanho se move.

## 3. Resultado registrado só em mensagem de tag se perde

O empacotamento de chunks (E06) foi implementado, medido neutro e arquivado
com um post-mortem excelente na mensagem da tag `archive/wave64-n4-neutral`.
Meses depois, o planejamento o listou como "diagnosticado, falta implementar".
Ninguém lê mensagens de tag antes de planejar. Disso nasceu o
`EXPERIMENT-LOG.md`: tentativas revertidas ficam no log com o mesmo peso das
mantidas, porque o valor de um resultado nulo é ninguém repeti-lo.

## 4. Vereditos precisam de revisita adversarial

O caso E09 é o exemplo com data e nome: a hipótese certa foi declarada
refutada por uma leitura errada do observável (joelho tratado como platô), e o
veredito errado só caiu porque foi questionado de fora ("qual a garantia de
que essa hipótese realmente caiu?"). A recomputação do ganho marginal mostrou
a inflexão no ponto previsto nas três arquiteturas. Regra derivada: veredito
de refutação declara explicitamente qual observável a hipótese prevê e qual
foi medido, e o log preserva o veredito errado corrigido em vez de reescrevê-lo.

## 5. Dado de campanha não versionado é o maior risco do projeto

A descoberta mais forte da investigação (E08) existiu por um dia inteiro como
patch não commitado e diretórios soltos em três nós de cluster (lunaris,
luxembourg, lyon), qualquer um deles a um reimage de distância da perda. O
resgate rendeu 484 arquivos e a regra: resultado nasce dentro de
`compression-experiments/experiments/`, com `provenance.txt` por campanha
(HEAD do git, estado sujo completo, ROCm, dispositivo, entrada, repetições).
Corolário da mesma família: o `.gitignore` do centralizador ignorava
`results/` em qualquer nível, forçando silenciosamente o dado para os repos de
artigo ou para nó nenhum; 182 CSVs quase se perderam num commit por causa
disso.

## 6. Sanidade do stack antes de qualquer campanha

Um driver travado na lunaris fez 17 de 19 casos do ctest falharem e parecia
exatamente uma regressão do branch. Desde então todo runner chama um programa
mínimo (`hipMalloc` + kernel) e aborta se ele falhar. Na mesma família: 18/19
com só o `BitPackGPU_test` falhando é o estado esperado do ctest, não uma
regressão; está documentado para não disparar investigação de novo.

## 7. Contadores são um recurso por plataforma, não um dado garantido

No gfx1100 bare metal com ROCm 7.2.3, todos os contadores de bloco retornam
zero pelo rocprofv3 e o rocprof legado aborta; só tempo de kernel e `SQ_WAVES`
saem. O experimento A4 teve que ser desenhado para decidir a questão **sem
contadores** (saída byte-idêntica + geometria de layout como única variável),
o que acabou produzindo um controle mais forte do que a versão com contadores
teria sido. Lição dupla: registrar a disponibilidade de contadores por
plataforma antes de desenhar o experimento, e preferir desenhos cuja conclusão
não dependa deles quando possível.

## 8. Uma tentativa por commit paga no replay

O desenho de uma tentativa por commit (A1 = `b9671c5`, A2 = `b48397c`,
A4 = `34e623e`, knob E08 = `f3e70b7`) permite reproduzir qualquer ponto da
investigação em outra GPU com `git checkout <hash>` e o mesmo runner, que é
como o replay CDNA vai comparar wave32 contra wave64 sem reimplementar nada.
O custo é disciplina na hora (commitar antes de medir, nunca emendar depois de
medido); o retorno é a comparabilidade.

## 9. Ferramenta acelera, não assina

Duas regras de fronteira mantidas durante toda a investigação: quem executa o
commit é o pesquisador, nunca o agente; e assistente ou agente (Claude, GEAK)
entra como acelerador do ciclo experimental, nunca como a contribuição, sob
pena de esvaziar a RQ2. O mesmo vale para a fronteira de repositórios: o
`arcto` recebe só mudança de biblioteca; campanha, runner, resultado e análise
vivem no `compression-experiments`; e material só migra para repo de artigo
quando entra de fato no artigo.

## 10. Bare metal para ver, container para publicar

A campanha rodou deliberadamente em bare metal (ROCm 7.2.3) para ver o
comportamento primeiro, sabendo que a metodologia declara ROCm 7.0.1 em
Singularity. A regra registrada: nada do que for adotado entra no texto sem
re-medição no container, e nunca misturar toolchains dentro de uma mesma
comparação. A parede de PMC do item 7 é ela própria um argumento para o
container, onde a campanha de maio coletou contadores reais.
