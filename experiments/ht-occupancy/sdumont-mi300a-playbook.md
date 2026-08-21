# Playbook SDumont 2nd (MI300A, gfx942): acesso, execução e o que medir

A MI300A é a forma APU da CDNA3: mesmo alvo de compilação da vianden
(gfx942, wave64), 228 CUs por APU, mas com CPU Zen4 e GPU no mesmo pacote
compartilhando 128 GB de HBM3, sem PCIe entre host e device. Para o trabalho
de kernel ela é a coluna gfx942 (substitui ou reforça a vianden); para a
camada de aplicação (mamute, prioridade 2 da tese) ela é um caso próprio,
porque o staging device para host vira zero-cópia e o ganho da compressão se
concentra em capacidade e em I/O de armazenamento.

## Acesso (validado 2026-08-21)

- `ssh sdumont` (alias no ssh config local), **exige a VPN do LNCC ativa**,
  que conflita com o uso simultâneo do G5K. Login node: `sdumont2nd4`.
- Home: `/petrobr/parceirosbr/home/cristiano.kunas` (cota 100 GB, Lustre,
  **sem backup**; colher resultados para o workspace local sempre).
- Fila MI300A: `ict-mi300a`, 11 nós (`sdumont2nd[4006-4012,4014-4017]`),
  TIMELIMIT infinite. Conta: `avalgpu`. **`--exclusive` e `--time` são
  sempre obrigatórios.**

```bash
salloc -p ict-mi300a --account avalgpu -t 4:00:00 --exclusive   # interativo
sbatch singularity/sdumont-payload.sbatch                        # batch
```

## As pegadinhas que custaram a primeira hora

1. **Steps não herdam as GPUs.** O job exclusivo recebe `gres/gpu=2`, mas um
   `srun --overlap` sem `--gpus` roda num cgroup **sem os devices**: o
   rocminfo enumera só os agentes de CPU (que na APU também se chamam "AMD
   Instinct MI300A Accelerator", o que confunde) e nenhum gfx aparece.
   Sempre `srun --gpus=2` no step, mesmo dentro de alocação exclusiva.
2. **rocminfo lista `gfx9` genérico além de `gfx942`**; a detecção do
   check-node usa o match mais específico (`sort -u | tail -1`).
3. **Sem singularity**: containers são enroot+pyxis. O caminho adotado é o
   **modo nativo** do commit-sweep (`--sif none`): `module load rocm/7.0.2`
   (há também 6.3.3; hipcc do sistema em `/usr/bin` existe mas o módulo é o
   controlado) e o toolchain do host constrói. O provenance registra o ROCm
   usado; a comparação fina com as colunas do G5K (container 7.0.1) carrega
   essa diferença de userspace, anotar ao ler os números.
4. O nó tem saída https (clone do submódulo zfp funciona direto).
5. Duas APUs por nó: medir com `HIP_VISIBLE_DEVICES=0` fixo; a outra fica
   para contadores, como nas sessões da neowise.

## Sequência de uma janela de medição

1. Subir da máquina local (VPN ativa): `commit-sweep.sh`, `check-node.sh`,
   `snapshot-node.sh`, o bundle e a lista de commits, mais
   `sdumont-payload.sbatch` para o caminho batch.
2. Interativo: com a alocação feita, na frontend:

```bash
setsid nohup srun --jobid=<JOBID> --overlap -n1 -c48 --gpus=2 \
  bash -l ~/run-mi300a.sh > ~/mi300a_sweep.log 2>&1 < /dev/null &
```

   onde `run-mi300a.sh` faz `module load rocm/7.0.2`, exporta
   `HIP_VISIBLE_DEVICES=0` e chama
   `./commit-sweep.sh --sif none --source ./vianden.bundle --commits
   ./commits-vianden.txt --out ~/sweep_mi300a_<data>`.
3. Batch (sem estar presente): `sbatch sdumont-payload.sbatch`, já com
   conta, fila, exclusive e gpus preenchidos. O payload é o mesmo.
4. O snapshot roda sozinho dentro do sweep e agora captura também os modos
   de partição da MI300 (`rocm-smi --showcomputepartition` e
   `--showmemorypartition`, seção 44b): NPS/SPX-TPX mudam o subsistema de
   memória e duas campanhas em modos diferentes não são comparáveis.
5. Colher com scp para
   `experiments/ht-occupancy/campaign-ladder-2026-08-20/` (ou campanha
   nova) antes de largar a janela; a home não tem backup.

## O que medir, em ordem de valor

A lista `commits-vianden.txt` já está ordenada assim (janela parcial rende):

1. Âncoras `v1` e `v10` e a **linhagem curada** (`35a6442`): fecha a célula
   gfx942 da curadoria E17. Predições a cobrar: curada com paridade ou
   ganho sobre v10 (nas outras wave64 deu paridade), claim table e E04
   essenciais, pino de VGPR pagando junto com o restrict.
2. As 4 linhagens de curadoria (vMin, vMin+E04, +claim, +vgpr+claim):
   replica o add-one-in na quarta GPU.
3. Degraus restantes da escada v2..v9.
4. Regime pequeno (`--dup 16 --reps 10`): com 228 CUs a fome de waves é o
   regime comum aqui, como na MI300X de maio.
5. Contadores: `rocprofv3` do módulo rocm, matriz TCC/TCP nos builds v1,
   v9, v10 (os `build_*` ficam prontos em `work/arcto`).

## Fase 2, o experimento que só a APU permite (a desenhar)

Memória unificada: o protocolo do ARCTO (device in, host out) sem o salto
PCIe. Medir o custo real do caminho comprimido de checkpoint contra o SSD
local de 3.84 TB e contra o Lustre, e o teto de memória unificada (128 GB)
como limite de tamanho de problema do adjoint do mamute. É o candidato a
caso de aplicação da tese na máquina nacional; desenhar como experimento
próprio depois da coluna gfx942.

## Duplo-cego

Em submissão duplo-cega, nunca nomear SDumont/LNCC; descrever como "um nó
com 2 APUs AMD Instinct MI300A". A regra vale igual para os sítios do G5K.
