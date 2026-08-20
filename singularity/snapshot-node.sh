#!/bin/bash
# snapshot-node.sh -- print completo do estado do hardware e do ambiente de
# execucao, no momento da medicao.
#
# A pratica que isto implementa vem da literatura de reprodutibilidade em HPC:
# o protocolo de Hoefler & Belli (SC'15, o hoefler2015 que a metodologia da
# tese ja cita) exige reportar a configuracao completa do sistema junto de
# qualquer numero de desempenho; o Author-Kit da iniciativa de
# reprodutibilidade do SC padroniza exatamente um "collect_environment" por
# experimento; e os apendices de artefato da ACM (badging) pedem a descricao
# do sistema em nivel de maquina. A regra pratica: capture DE TUDO no momento
# da execucao, porque a pergunta "sera que isso foi efeito da CPU?" chega
# meses depois, quando o no ja foi reimageado.
#
# Tudo e best-effort e sem root: cada secao registra o que conseguiu e o rc
# do comando; ausencia registrada e melhor que buraco silencioso.
#
# Uso:
#   ./snapshot-node.sh [--out DIR] [--sif IMAGE] [--results-dir DIR]
#
#   --out DIR          onde escrever (default: ./node-snapshot_<host>_<ts>)
#   --sif IMAGE        tambem captura o userspace ROCm de dentro da imagem
#   --results-dir DIR  disco/fs a caracterizar (default: o proprio --out),
#                      porque "onde o resultado esta sendo salvo" e parte do
#                      experimento quando ha E/S envolvida
set -u

OUT="" SIF="" RESDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --sif) SIF="$2"; shift 2 ;;
    --results-dir) RESDIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
OUT=${OUT:-"./node-snapshot_$(hostname -s)_$(date +%Y%m%d_%H%M%S)"}
RESDIR=${RESDIR:-"$OUT"}
mkdir -p "$OUT"
MANIFEST="$OUT/MANIFEST.txt"
: > "$MANIFEST"

# cap <arquivo> <cmd...>: captura stdout+stderr, registra rc no MANIFEST
cap() {
  local f="$1"; shift
  ( "$@" ) > "$OUT/$f" 2>&1
  printf "%-34s rc=%-3s %s\n" "$f" "$?" "$*" >> "$MANIFEST"
}
# capsh <arquivo> 'pipeline'  (quando precisa de shell)
capsh() {
  local f="$1"; shift
  bash -c "$*" > "$OUT/$f" 2>&1
  printf "%-34s rc=%-3s %s\n" "$f" "$?" "$*" >> "$MANIFEST"
}

# --- identidade e SO ---------------------------------------------------------
cap 00-identity.txt      bash -c 'hostname; date -Is; uptime'
cap 01-os.txt            bash -c 'uname -a; echo; cat /etc/os-release 2>/dev/null; echo; cat /proc/cmdline; echo; ldd --version 2>/dev/null | head -1'

# --- CPU ---------------------------------------------------------------------
cap 10-lscpu.txt         lscpu
capsh 11-cpu-model.txt   'grep -m1 "model name" /proc/cpuinfo; grep -c ^processor /proc/cpuinfo'
capsh 12-cpu-freq.txt    'echo "smt: $(cat /sys/devices/system/cpu/smt/control 2>/dev/null)";
                          echo "boost: $(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null) no_turbo: $(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)";
                          for p in /sys/devices/system/cpu/cpufreq/policy*; do
                            [ -d "$p" ] || continue
                            echo "$(basename $p): governor=$(cat $p/scaling_governor 2>/dev/null) cur=$(cat $p/scaling_cur_freq 2>/dev/null) min=$(cat $p/scaling_min_freq 2>/dev/null) max=$(cat $p/scaling_max_freq 2>/dev/null)"
                          done | head -8; echo "(politicas: $(ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null | wc -l))"'
capsh 13-vulnerabilities.txt 'grep -r . /sys/devices/system/cpu/vulnerabilities/ 2>/dev/null'
cap 14-numa.txt          numactl --hardware
capsh 15-topology.txt    'command -v lstopo-no-graphics >/dev/null && lstopo-no-graphics --no-io || echo "hwloc/lstopo ausente"'

# --- memoria -----------------------------------------------------------------
cap 20-meminfo.txt       cat /proc/meminfo
capsh 21-hugepages.txt   'echo "thp: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)";
                          echo "thp-defrag: $(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)";
                          grep -i huge /proc/meminfo; swapon --show 2>/dev/null'

# --- kernel, limites e ambiente ---------------------------------------------
capsh 30-sysctl.txt      'for k in kernel.perf_event_paranoid vm.swappiness kernel.numa_balancing vm.overcommit_memory; do echo "$k = $(sysctl -n $k 2>/dev/null)"; done'
capsh 31-ulimits.txt     'ulimit -a'
capsh 32-env-relevante.txt 'env | grep -E "^(PATH|LD_LIBRARY_PATH|ROCM|ROCR|HSA|HIP|CUDA|OMP|GOMP|HCC|OAR|SLURM|SINGULARITY|APPTAINER)" | sort'
capsh 33-modules.txt     'lsmod 2>/dev/null | grep -E "^(Module|amdgpu|nvidia|kfd)" '

# --- GPU AMD -----------------------------------------------------------------
if [ -e /dev/kfd ] || command -v rocm-smi >/dev/null 2>&1; then
  capsh 40-amdgpu-driver.txt 'modinfo amdgpu 2>/dev/null | grep -E "^(version|srcversion|vermagic)"; echo "ppfeaturemask: $(cat /sys/module/amdgpu/parameters/ppfeaturemask 2>/dev/null)"'
  cap 41-rocm-smi.txt      rocm-smi
  cap 42-rocm-smi-all.txt  rocm-smi --showallinfo
  capsh 43-rocminfo.txt    'rocminfo 2>/dev/null | grep -E "Name:|Marketing|Compute Unit|Wavefront|Cache|BDFID|Max Clock|Pool Size|Uuid" '
  capsh 44-amd-smi.txt     'command -v amd-smi >/dev/null && amd-smi static 2>&1 || echo "amd-smi ausente"'
fi
# tambem via imagem, quando o host nao tem o userspace
if [ -n "$SIF" ]; then
  RUNTIME_BIN=$(command -v singularity || command -v apptainer || true)
  if [ -n "$RUNTIME_BIN" ]; then
    capsh 45-rocm-in-sif.txt "'$RUNTIME_BIN' exec --rocm '$SIF' bash -c 'cat /opt/rocm/.info/version; hipcc --version 2>/dev/null | head -2; rocm-smi 2>/dev/null'"
    capsh 46-rocminfo-in-sif.txt "'$RUNTIME_BIN' exec --rocm '$SIF' bash -c 'rocminfo 2>/dev/null' | grep -E 'Name:|Compute Unit|Wavefront|Cache|Max Clock' | head -40"
  fi
fi

# --- GPU NVIDIA --------------------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
  cap 50-nvidia-smi.txt    nvidia-smi
  cap 51-nvidia-smi-q.txt  nvidia-smi -q
  cap 52-nvidia-topo.txt   nvidia-smi topo -m
fi

# --- PCIe (velocidade/largura de link atual vs capacidade) -------------------
capsh 60-pcie-gpus.txt 'for d in /sys/bus/pci/devices/*; do
  cls=$(cat $d/class 2>/dev/null)
  case "$cls" in 0x0300*|0x0302*|0x1200*)
    echo "== $(basename $d) $(cat $d/vendor 2>/dev/null)/$(cat $d/device 2>/dev/null)"
    echo "  link atual: $(cat $d/current_link_speed 2>/dev/null) x$(cat $d/current_link_width 2>/dev/null)"
    echo "  link max:   $(cat $d/max_link_speed 2>/dev/null) x$(cat $d/max_link_width 2>/dev/null)";;
  esac; done'
capsh 61-lspci-gpu.txt   'lspci 2>/dev/null | grep -iE "vga|display|3d|accel"'

# --- armazenamento do resultado ----------------------------------------------
capsh 70-results-fs.txt  "df -hT '$RESDIR'; echo; findmnt -T '$RESDIR' 2>/dev/null"
cap 71-lsblk.txt         lsblk -o NAME,MODEL,SIZE,ROTA,TYPE,FSTYPE,MOUNTPOINT
capsh 72-blockdev.txt    'for b in /sys/block/*/queue; do d=$(dirname $b); echo "$(basename $d): scheduler=$(cat $b/scheduler 2>/dev/null) rotational=$(cat $b/rotational 2>/dev/null) read_ahead_kb=$(cat $b/read_ahead_kb 2>/dev/null)"; done | grep -vE "loop|ram"'

# --- software do host --------------------------------------------------------
capsh 80-toolchain.txt   'for c in gcc g++ cmake git python3 singularity apptainer; do command -v $c >/dev/null && echo "$c: $($c --version 2>/dev/null | head -1)"; done'
capsh 81-cluster.txt     'env | grep -E "^(OAR_|SLURM_)" | sort; echo; who 2>/dev/null | head -5'

# --- resumo de uma tela ------------------------------------------------------
{
  echo "host:    $(hostname)  ($(date -Is))"
  echo "so:      $(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d\" -f2)  kernel $(uname -r)"
  echo "cpu:     $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')  x$(grep -c ^processor /proc/cpuinfo)"
  echo "mem:     $(awk '/MemTotal/{printf "%.0f GiB", $2/1048576}' /proc/meminfo)"
  echo "governor:$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)  smt:$(cat /sys/devices/system/cpu/smt/control 2>/dev/null)"
  if [ -e /dev/kfd ]; then
    echo "gpu:     AMD ($(command -v rocminfo >/dev/null && rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-f]+' || echo via-sif))  driver amdgpu $(modinfo -F version amdgpu 2>/dev/null)"
  fi
  command -v nvidia-smi >/dev/null 2>&1 && echo "gpu:     NVIDIA $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1)"
  echo "result:  $RESDIR em $(findmnt -nT "$RESDIR" -o SOURCE,FSTYPE 2>/dev/null)"
} > "$OUT/SUMMARY.txt"

echo "[snapshot-node] escrito em $OUT ($(ls "$OUT" | wc -l) arquivos; veja SUMMARY.txt e MANIFEST.txt)" >&2
