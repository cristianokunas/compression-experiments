# E09: residência de cache, a hipótese que quase morreu por erro de análise

Este é o caso metodologicamente mais rico da investigação: a hipótese certa foi
declarada refutada por uma leitura errada do que ela prevê, foi reaberta por
questionamento do orientando, e saiu validada por um experimento controlado.
A tese ganha duas coisas aqui: o resultado, e a demonstração de que revisitar
vereditos faz parte do método.

## A hipótese

Cada wave processa um chunk e carrega sua própria tabela
(`temp_space + bidx * hash_table_size`). A quantidade governante seria a
pegada agregada das tabelas das waves concorrentes contra o cache vetorial por
CU, prevendo o ótimo em `tabela_bytes ≈ L1_bytes / waves_por_CU`. Em entradas
de `uint16_t`: gfx1100 (32 KB / 32) prevê 512 entradas; MI210 (16 KB / 32)
prevê 256; MI50 (16 KB / 40) prevê ~205.

## A queda errada

O primeiro veredito foi SUPERSEDED com o argumento: a MI210 acerta exato (256,
com degrau de 4x), mas gfx1100 e gfx906 são monotônicos até o menor tamanho
medido, sem virada; residência prevê joelho; logo, refutada.

O erro: tratar "joelho" como platô. Num sistema real, com hierarquia de vários
níveis e a tabela competindo com a janela de dados de 64 KiB por wave, o
observável que um modelo de residência prevê é o **colapso do ganho marginal**,
não o zero absoluto abaixo do ponto crítico.

## A reabertura

Provocada pela pergunta "qual a garantia de que essa hipótese realmente caiu?".
Recomputando o ganho marginal por halving no dado bruto:

| GPU | previsto | comportamento medido |
|---|---|---|
| gfx1100 | 512 | ganho **sobe** até 1,49x/halving no passo 1024 para 512 e desaba para 1,11x e 1,09x logo abaixo; inflexão exata no previsto |
| MI210 | 256 | acelera até **3,89x** no passo 512 para 256, o previsto (nada medido abaixo) |
| MI50 | ~205 | pico de 1,40x em 512 para 256, decaindo para 1,21x; previsto dentro do intervalo |

A premissa de ocupação máxima no denominador é consistente aqui: as cargas
sobresubscrevem os slots de wave em 3,5 a 4x (10.974 chunks contra 2.688 slots
no gfx1100), diferente do caso MI300X de 100 MB, faminto de waves, onde E06
operou.

## O experimento controlado (A4)

Restava atribuir o resíduo sub-joelho (9 a 20 % por halving) entre duas
contas: localidade das linhas de cache tocadas pelas sondas, ou efeito
algorítmico de colisão (tabela menor recicla entradas mais rápido, mudando a
idade dos candidatos). O desenho (commit `34e623e`): tabela **alocada** em
16384 entradas nas duas variantes, hash mascarado para 128 slots lógicos em
duas geometrias:

- `contig128`: slots contíguos, 4 linhas de cache tocadas por wave
- `spread128`: os mesmos slots lógicos com stride 128, 128 linhas tocadas

A função de slot lógico é idêntica, então colisões e decisões de match são as
mesmas por construção, e o portão comprova: **saída byte-idêntica ao ht128
real nos seis arquivos da escada**, nas duas variantes. Só o layout de memória
difere.

| variante | linhas tocadas | mediana (30 reps) |
|---|---|---|
| contig128 | 4 | 30,75 GB/s ≈ ht128 real (30,94) |
| spread128 | 128 | 14,63 GB/s |

A conta de colisão previa spread ≈ contig e foi **refutada** (fosso de 2,1x
com trabalho idêntico). A conta de linhas previa a faixa da pegada de 8 KB e
foi **confirmada** (14,63 entre ht2048 = 12,74 e ht1024 = 17,16). E
contig ≈ ht128 real prova que o tamanho **alocado** é irrelevante: o conjunto
**tocado** governa.

## Estado final

A E09 fica assim: **a pegada de linhas de cache tocadas pelas sondas, por
wave, contra o cache por CU, governa a vazão de compressão do LZ4 neste dado;
o joelho está em L1/waves (confirmado em 3 de 3 arquiteturas) e abaixo dele o
efeito é a contagem de linhas.**

## Pontos positivos

- Predição derivável de duas propriedades do dispositivo, sem varredura: é o
  formato exato que a RQ2 exige, e o contraste direto com o c\*.
- O experimento A4 tem o controle mais forte possível (saída byte-idêntica), o
  que fecha a atribuição sem depender de contadores.
- O episódio da queda errada virou material de metodologia: o veredito errado
  está registrado no log com nome e data, junto do que o corrigiu.

## Pontos negativos

- O primeiro veredito errado passou pelo próprio autor da análise e só caiu
  por questionamento externo. Um laço sem revisão adversarial teria seguido
  na direção errada (E10 era a aposta seguinte e teria dado neutro).
- Nenhuma taxa de acerto de cache foi medida diretamente: o PMC está morto no
  gfx1100 bare metal (ROCm 7.2.3) e a confirmação por contador (`TCP_*`)
  depende do replay CDNA.
- MI210 abaixo de 256 entradas segue não medida.

## Direções seguidas

1. Replay CDNA: contig/spread em wave64, MI210 abaixo de 256, taxas de acerto
   via `TCP_*` no container (ROCm 7.0.1).
2. E11: o redesenho LDS herda esta validação como motivação quantitativa.
