# E10: o laço de limpeza da tabela (A1 e A2)

## A hipótese

`LZ4Kernels.hiph:941` abre o `compressStream` limpando a tabela inteira, em
memória global, uma wave só, uma vez por chunk:

```cpp
for (position_type i = threadIdx.x; i < hash_table_size;
     i += LZ4_COMP_THREADS_PER_CHUNK) {
  hashTable[i] = NULL_OFFSET;
}
SYNCWARP1();
```

No padrão herdado com chunk de 64 KiB, isso são 32 KB de escritas em memória
global para cada 64 KiB de entrada, antes de comprimir um byte. Custo linear no
tamanho da tabela, pago por chunk: era a única candidata que parecia prever a
forma monotônica das curvas (na leitura errada de E09) e a neutralidade de E06
(trabalho por chunk não muda com geometria de lançamento). A predição: remover
o laço com a tabela em 16384 recuperaria a maior parte do ganho do ht128, sem
custo de razão.

## Tentativa A1 (`b9671c5`): remover o laço confiando na revalidação

A leitura do código sugeria que a limpeza era dispensável: todo leitor passa
por `isValidHash`, que rejeita entrada velha pela checagem de `NULL_OFFSET`,
pela janela de `MAX_OFFSET` e por comparação de bytes reais no offset
decodificado. O comentário do próprio caminho de inserção diz que corridas são
toleradas por essa razão. A edição mais simples possível (apagar o laço) era o
experimento.

**Falhou o portão de correção: acesso ilegal à memória.** O post-mortem achou
o mecanismo exato: na primeira janela de 64 KiB do chunk, uma entrada velha em
valor **à frente** da posição atual estoura o `convertIdx`
(`realPos -= OFFSET_SIZE` embrulha abaixo de zero), e o offset embrulhado
**escapa da checagem de janela**: com posição 100 e entrada velha 200,
`decomp_idx - offset` sai 65436, dentro da janela, e o `readWord` derreferencia
um endereço selvagem. O `assert(offset <= pos)` que pegaria isso é compilado
fora em Release. Conclusão colateral importante: o laço de limpeza não era só
custo, ele sustentava silenciosamente um invariante de que a validação
depende.

## Tentativa A2 (`b48397c`): o guarda que torna a validação total

Uma condição antes do `convertIdx`: na primeira janela, rejeitar qualquer
entrada em posição igual ou à frente da atual (entradas legítimas ali estão
sempre estritamente atrás). Nada válido se perde.

**Passou o portão inteiro**: razão byte-idêntica na escada completa e
round-trip bit a bit (o benchmark verifica o descomprimido byte a byte contra
a entrada). E mediu **1,00x**:

| variante (chunk 64K, 30 reps) | mediana |
|---|---|
| baseline ht16384 | 6,87 GB/s |
| A2 ht16384 (sem limpeza) | 6,84 GB/s |
| baseline ht128 | 30,94 GB/s |
| A2 ht128 | 30,08 GB/s |

## Veredito

**E10 refutada.** O laço de limpeza não é o custo. O dado decisivo: a tabela
continua governando **sem limpeza nenhuma dos dois lados** (6,84 contra
30,08), o que desloca o custo para o caminho de leitura e prepara o terreno
que A4 fechou. A remoção é semanticamente correta (saída idêntica), só não
paga nada; foi revertida no branch (`422ec6f`), com os commits preservados
para o replay entre arquiteturas.

Um subproduto: a saída byte-idêntica entre builds com e sem limpeza mostra que
entradas velhas nunca sobrevivem à validação neste dado. A limpeza é
desnecessária semanticamente, além de irrelevante para desempenho.

## A medição A3 e a parede de plataforma

A tentativa seguinte era medição, não edição: contadores para separar as
explicações de leitura. O tempo de kernel confirmou duas vezes que o custo é
interno (4,53x no baseline, 4,37x sem limpeza; nada de lançamento ou
transferência), e `SQ_WAVES` = 43.904 = 10.974 chunks x 4 despachos confirmou
em hardware uma wave por chunk. Mas **todos os contadores de bloco retornam
zero no gfx1100 bare metal em ROCm 7.2.3** (`GL2C_*`, `SQ_INSTS_*`,
`GRBM_GUI_ACTIVE`, `MemUnitBusy`, variantes `_sum`), e o rocprof legado aborta
com SIGABRT. Só valores derivados de despacho saem. O discriminador migrou
para o desenho sem contadores de A4, e a confirmação por contador ficou para o
replay CDNA, onde o PMC comprovadamente funciona (campanha de maio, ROCm 7.0.1
no container).

## Pontos positivos

- O portão de correção fez exatamente o seu trabalho: sem ele, o acesso ilegal
  de A1 teria aparecido semanas depois como corrupção intermitente dentro do
  mamute, sem trilha para o laço de limpeza.
- Um resultado negativo com portão limpo é o controle que fecha a atribuição:
  A2 elimina a explicação de escrita e, junto com E06, deixa E09 como única
  candidata em pé, que A4 então confirma.
- O invariante latente descoberto por A1 está documentado no código e no log;
  qualquer redesenho futuro da tabela (E11 incluído) precisa dele.

## Pontos negativos

- A hipótese A1 ("a revalidação cobre tudo") foi formulada com leitura de
  código otimista; o custo foi um ciclo extra de build e medição. Barato, mas
  evitável com uma análise de casos-limite antes do commit.
- A parede de PMC no gfx1100 só foi descoberta gastando duas rodadas de
  perfilamento; vale registrar como fato de plataforma para não repetir.

## Direção seguida

Com E10 refutada, o caminho de leitura virou a única explicação em pé, e o
experimento A4 (documentado em E09) fechou a questão sem contadores.
