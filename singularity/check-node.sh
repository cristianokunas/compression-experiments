#!/bin/bash
# check-node.sh -- probe a node for the container-first measurement flow.
#
# Reports, as KEY=VALUE lines on stdout (script-consumable) plus a human
# summary on stderr:
#   RUNTIME        singularity | apptainer | none
#   RUNTIME_BIN    absolute path of the runtime
#   GPU_DEV        yes|no      (/dev/kfd present -- amdgpu driver loaded)
#   GFX_ARCH       gfxNNNN     (from rocminfo, host or via --sif)
#   WAVE32_FLAG    the cmake flag the detected arch requires ("" or -DUSE_WARPSIZE_32=ON)
#   NPROC          build parallelism available
#   BUILD_MODE     how a .sif can be built here: root | sudo-g5k | sudo | fakeroot | none
#
# Usage:
#   ./check-node.sh [--sif IMAGE]     # IMAGE lets GFX detection run through the container
#
# Exit status: 0 if the node can RUN measurements (runtime + GPU); nonzero otherwise.
# Being unable to BUILD an image (BUILD_MODE=none) is not a failure: images are
# usually built once elsewhere and copied -- they cross Grid'5000 sites in seconds.
set -u

SIF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sif) SIF="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

info() { echo "[check-node] $*" >&2; }

# --- container runtime -------------------------------------------------------
RUNTIME_BIN=$(command -v singularity || command -v apptainer || true)
if [ -n "$RUNTIME_BIN" ]; then
  RUNTIME=$(basename "$RUNTIME_BIN")
  info "runtime: $RUNTIME ($("$RUNTIME_BIN" --version 2>/dev/null))"
else
  RUNTIME=none
  info "runtime: NENHUM (singularity/apptainer ausentes)"
fi

# --- GPU / driver ------------------------------------------------------------
if [ -e /dev/kfd ]; then GPU_DEV=yes; else GPU_DEV=no; fi
info "driver amdgpu (/dev/kfd): $GPU_DEV"

# --- gfx arch: prefer host rocminfo, fall back to running it inside the image
GFX_ARCH=""
if command -v rocminfo >/dev/null 2>&1; then
  GFX_ARCH=$(rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-f]+' || true)
fi
if [ -z "$GFX_ARCH" ] && [ -n "$SIF" ] && [ "$RUNTIME" != none ] && [ "$GPU_DEV" = yes ]; then
  GFX_ARCH=$("$RUNTIME_BIN" exec --rocm "$SIF" rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-f]+' || true)
fi
info "gfx: ${GFX_ARCH:-nao detectado}"

WAVE32_FLAG=""
case "$GFX_ARCH" in gfx10*|gfx11*|gfx12*) WAVE32_FLAG="-DUSE_WARPSIZE_32=ON" ;; esac
[ -n "$WAVE32_FLAG" ] && info "arquitetura RDNA: builds precisam de $WAVE32_FLAG"

# --- image build capability --------------------------------------------------
BUILD_MODE=none
if [ "$RUNTIME" != none ]; then
  if [ "$(id -u)" = 0 ]; then BUILD_MODE=root
  elif command -v sudo-g5k >/dev/null 2>&1; then BUILD_MODE=sudo-g5k
  elif sudo -n true 2>/dev/null; then BUILD_MODE=sudo
  elif grep -q "^$(id -un):" /etc/subuid 2>/dev/null; then BUILD_MODE=fakeroot
  fi
fi
info "modo de build de imagem: $BUILD_MODE"
[ "$BUILD_MODE" = none ] && info "  (sem privilegio para construir aqui; construa noutro no e copie o .sif)"

# --- machine-readable block --------------------------------------------------
echo "RUNTIME=$RUNTIME"
echo "RUNTIME_BIN=$RUNTIME_BIN"
echo "GPU_DEV=$GPU_DEV"
echo "GFX_ARCH=$GFX_ARCH"
echo "WAVE32_FLAG=$WAVE32_FLAG"
echo "NPROC=$(nproc)"
echo "BUILD_MODE=$BUILD_MODE"

[ "$RUNTIME" != none ] && [ "$GPU_DEV" = yes ]
