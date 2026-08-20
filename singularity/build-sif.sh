#!/bin/bash
# build-sif.sh -- build the toolchain image from toolchain.def.
#
# Uses check-node.sh to pick the runtime and the privilege mode. Refuses to
# overwrite an existing image unless --force is given, because campaigns pin
# their provenance to the image they ran in.
#
# Usage:
#   ./build-sif.sh [-o OUTPUT.sif] [-d DEF] [--mode root|sudo-g5k|sudo|fakeroot] [--force]
#
# Defaults: OUTPUT = ../images/arcto_toolchain_rocm701.sif, DEF = ./toolchain.def
set -u
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../images/arcto_toolchain_rocm701.sif"
DEF="$HERE/toolchain.def"
MODE=""
FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    -d) DEF="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    -f|--force) FORCE=true; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

[ -f "$DEF" ] || { echo "def nao encontrado: $DEF" >&2; exit 1; }

if [ -f "$OUT" ] && [ "$FORCE" != true ]; then
  echo "imagem ja existe: $OUT" >&2
  echo "use --force para substituir (campanhas antigas apontam a provenance para ela)" >&2
  exit 1
fi

# node probe: runtime + privilege mode
eval "$("$HERE/check-node.sh" 2>/dev/null | grep -E '^(RUNTIME|RUNTIME_BIN|BUILD_MODE)=')"
[ "${RUNTIME:-none}" != none ] || { echo "sem singularity/apptainer neste no" >&2; exit 1; }
[ -n "$MODE" ] && BUILD_MODE=$MODE
[ "${BUILD_MODE:-none}" != none ] || {
  echo "sem privilegio para construir aqui (root/sudo-g5k/sudo/fakeroot)." >&2
  echo "construa num no com privilegio e copie o .sif; ele cruza sitios em segundos." >&2
  exit 1
}

mkdir -p "$(dirname "$OUT")"
echo "[build-sif] runtime=$RUNTIME modo=$BUILD_MODE def=$DEF" >&2
echo "[build-sif] saida=$OUT" >&2

case "$BUILD_MODE" in
  root)     "$RUNTIME_BIN" build ${FORCE:+--force} "$OUT" "$DEF" ;;
  sudo-g5k) sudo-g5k "$RUNTIME_BIN" build ${FORCE:+--force} "$OUT" "$DEF" ;;
  sudo)     sudo "$RUNTIME_BIN" build ${FORCE:+--force} "$OUT" "$DEF" ;;
  fakeroot) "$RUNTIME_BIN" build --fakeroot ${FORCE:+--force} "$OUT" "$DEF" ;;
  *) echo "modo invalido: $BUILD_MODE" >&2; exit 2 ;;
esac

echo "[build-sif] pronto: $OUT" >&2
"$RUNTIME_BIN" exec "$OUT" bash -c 'echo "[build-sif] ROCm na imagem: $(cat /opt/rocm/.info/version)"' >&2
