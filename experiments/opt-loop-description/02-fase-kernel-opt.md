# E01 a E07: a fase kernel-opt (julho de 2026)

## Contexto

Antes do laço formalizado, uma fase de otimização de kernels correu em julho de
2026 no branch `feature/kernel-opt`, guiada por um mapa de gargalos com
`arquivo:linha` levantado de quatro investigações (kernels do ARCTO, diff do
nvcomp 2.2 para 3.0, guias de otimização da AMD, evolução do nvcomp pós-2.2).
Sete mudanças entraram; cada commit carrega o antes/depois medido e a
arquitetura em que foi validado.

## O que entrou

| Caso | Commit | Mudança | Resultado |
|---|---|---|---|
| E01 | `a3967f3` | `__launch_bounds__` amarrado aos blocos reais | mantido |
| E02 | `cf40a20` | `__restrict__` nos ponteiros de kernel e stream | mantido |
| E03 | `9ced960` | guarda de wavefront em tempo de execução | mantido (correção, não desempenho) |
| E04 | `2e2b74e` | `warpMatchAny` removido do laço quente de compressão | mantido |
| E05 | `e3293a1` | kernel de compressão fixado no degrau de 64 VGPR (wave64) | mantido |
| E07 | `df13f11` | tabela de claim em LDS com 256 buckets substituindo a busca all-to-all de 64 lanes | MI300X 4,85 para 11,7 GB/s a 64K |
| E07 | `61218f5` | conjunto wave32-only: cópia vetorizada, repeat híbrido, LSIC por warp | gfx1100 descompressão de zeros +20 % |

## O achado central da fase

**wave64/CDNA3 rejeitou todas as variantes de cópia vetorizada, doubling e
LSIC-warp na descompressão**, com regressões de 5 % a 43 %, a ponto de até uma
indireção de função sobre um laço idêntico regredir. O caminho de descompressão
wave64 manteve os laços originais literalmente. Disso nasceu a disciplina que
o laço formalizado herdou como regra: toda tentativa é medida nas duas larguras
de wave antes de qualquer generalização, e o veredito é por arquitetura, nunca
global.

## Pontos positivos

- Ganhos reais e arquitetura-conscientes, com o antes/depois preservado nas
  mensagens de commit.
- A lição wave32/wave64 evitou, nas fases seguintes, o erro de generalizar um
  ganho de uma largura para a outra.

## Pontos negativos

- Várias das mudanças mantidas têm o mecanismo **assumido, não medido**: E01 e
  E02 nunca foram verificadas contra o assembly gerado ou contra a contagem de
  VGPR, e E05 pode ter sido deslocada por mudanças posteriores de pressão de
  registradores. O log registra a revisita pendente de cada uma.
- O registro vivia em mensagens de commit e de tag, sem um log central. O custo
  disso apareceu depois (ver E06 e as lições metodológicas).

## Direção seguida

A fase apontava "tabela de hash em memória global" como gargalo desde julho.
A linha E08/E09/E10 é a retomada dessa pista com o método formalizado.
