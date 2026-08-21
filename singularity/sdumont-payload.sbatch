#!/bin/bash
# Payload Slurm para o SDumont 2nd (nos MI300A, gfx942).
# Conta avalgpu, fila ict-mi300a; --exclusive e --time sao obrigatorios la.
# Detalhes: experiments/ht-occupancy/sdumont-mi300a-playbook.md
#
# Submissao:  sbatch sdumont-payload.sbatch
# Variaveis:  BASE (default: diretorio da submissao) precisa conter
#             commit-sweep.sh, check-node.sh, snapshot-node.sh,
#             o bundle e a lista de commits.
#SBATCH -J arcto-mi300a
#SBATCH --account=avalgpu
#SBATCH --partition=ict-mi300a
#SBATCH --exclusive
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --gpus=2
#SBATCH --time=01:30:00
#SBATCH -o %x_%j.out

set -u
BASE=${BASE:-$SLURM_SUBMIT_DIR}
cd "$BASE"

# plano A: toolchain ROCm do proprio no (o sweep roda com --sif none)
module load rocm/7.0.2 2>/dev/null || module load rocm 2>/dev/null || true
export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0}
command -v hipcc >/dev/null || export PATH="$ROCM_PATH/bin:$PATH"
command -v hipcc >/dev/null || { echo "hipcc indisponivel: confira module avail rocm"; exit 1; }

BUNDLE=${BUNDLE:-vianden.bundle}
LISTA=${LISTA:-commits-vianden.txt}

srun --ntasks=1 --gpus=2 ./commit-sweep.sh --sif none \
  --source "./$BUNDLE" --commits "./$LISTA" \
  --out "$BASE/sweep_mi300a_${SLURM_JOB_ID}"
