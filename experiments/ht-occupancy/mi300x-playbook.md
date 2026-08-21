# Playbook MI300X (vianden-1): o que rodar quando a reserva sair

A quarta arquitetura (gfx942, CDNA3, wave64, 304 CUs, ~9728 slots de wave) é a
única do enxame ainda sem os resultados da campanha da tabela. Este arquivo é o
roteiro pronto para gastar bem a reserva, na ordem de valor.

## Antes de reservar

- Tentar **ambiente padrão primeiro** (`oarsub -p vianden -t exotic -l ...` sem
  `-t deploy`): em neowise e larochette o std-env tinha driver amdgpu,
  singularity e `sudo-g5k`, que destrava a coleta de PMC. Só cair para kadeploy
  (`ubuntu2404-rocm` + postinstall) se o std-env da vianden não tiver o driver.
- A imagem de toolchain está em `luxembourg:~/arcto_toolchain.sif` (mesma home
  NFS que a vianden enxerga). Bundle e scripts idem (`~/ladder.bundle`,
  `~/commits-ladder.txt`, `~/commit-sweep.sh`, `~/check-node.sh`,
  `~/snapshot-node.sh`, `~/read_pmc.py`).

## Sequência (uma linha cada)

1. **Sonda e snapshot** (2 min):
   `bash ~/check-node.sh --sif ~/arcto_toolchain.sif`
   O snapshot roda sozinho dentro do sweep; não precisa de passo próprio.
2. **A escada completa v1→v10** (~1h30 nos 96+ núcleos):
   `./commit-sweep.sh --sif ~/arcto_toolchain.sif --source ~/ladder.bundle --commits ~/commits-ladder.txt --out ~/ladder_gfx942`
   Predições a cobrar: v9 (tabela 64) resolve a fome de 4,67 GB/s diagnosticada
   em maio; v10 (LDS) soma por cima como nas outras wave64; v5 (warpMatchAny)
   deve ser o degrau grande da fase antiga, era o gargalo apontado pela tag
   `archive/wave64-n4-neutral`.
3. **Regime pequeno** (30 min): o caso de maio era faminto de waves (100 MB,
   1600 chunks contra 9728 slots). Repetir a escada com `--dup 16 --reps 10
   --out ~/ladder_gfx942_small`; a MI300X é a arquitetura onde este regime é o
   comum, não o raro.
4. **Contadores com sudo-g5k** (20 min): matriz `TCC_HIT TCC_MISS SQ_WAVES` +
   passe `TCP_TCC_READ_REQ_sum TCP_TOTAL_CACHE_ACCESSES_sum` sobre os builds
   v1, v9 e v10 da escada (os diretórios `work/arcto/build_*` ficam prontos
   pelo passo 2; adaptar `~/mi210_pmc_matrix.sh`, trocando os nomes de build).
   Fecha a assinatura das duas camadas na quarta arquitetura, com os nomes
   `TCP_*` que a CDNA3 comprovadamente expõe (campanha de maio).

## Curadoria (adicionado 2026-08-21)

Depois da escada, rodar as duas linhagens de curadoria (bundles `minlin.bundle`
e `minlin2.bundle`, tags `ladder-min` e `ladder-min-e04`): no gfx1100 a linhagem
`main + E04 + O1 + O2` superou o v10 em +10,6 % com bytes idênticos. Em wave64
a pergunta é se E05/E07-claim sobrevivem no tip; é o experimento E17 repetido.

## Cuidados específicos da vianden

- `HIP_VISIBLE_DEVICES` fixo: o nó tem 8 aceleradores; medir num, contadores
  noutro, como nas sessões da neowise.
- O joelho previsto para gfx942 saturado: L1 16 KB / 32 waves = 256 entradas de
  teto; ótimo esperado em 64 pela regra joelho/4. Em regime pequeno o joelho
  desloca para a direita (denominador menor), o que o caso de maio já insinuava.
- Colher com rsync para `experiments/ht-occupancy/` antes de largar a reserva;
  nada fica só no nó.
