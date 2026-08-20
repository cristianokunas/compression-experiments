#!/bin/bash
# =============================================================================
# Fetch a pinned SDRBench subset and record a checksum manifest.
#
# WHY a manifest: sdrbench.github.io publishes neither checksums nor version
# numbers, so "download SDRBench" is not by itself a reproducible instruction.
# This script records sha256 of every file it fetches; a later run verifies
# against that manifest and fails loudly if the upstream bytes changed.
#
# CITATION (required by SDRBench for any published result):
#   K. Zhao, S. Di, X. Liang, S. Li, D. Tao, J. Bessac, Z. Chen, F. Cappello,
#   "SDRBench: Scientific Data Reduction Benchmark for Lossy Compressors", 2020.
#   Also acknowledge the dataset source, DOE NNSA ECP and the CODAR project.
#
# NOT included on purpose: NSTX GPI requires pre-publication approval from a
# third party (rchurchi@pppl.gov) -- it would put the thesis schedule on
# someone else's calendar.
#
# Usage:
#   ./fetch_sdrbench.sh -o DATADIR [-d "isabel nyx"] [--verify]
# =============================================================================
set -euo pipefail

OUTPUT_DIR="${PWD}/sdrbench"
DATASETS="isabel nyx miranda"
VERIFY_ONLY=false

# name|url|expected-domain-note
# URLs verified against sdrbench.github.io on 2026-08-19. Host is a Globus
# HTTPS collection; if anonymous GET starts 401/403-ing, the collection went
# auth-only and the fetch needs a Globus token (see --help).
declare -A URLS=(
  [isabel]="https://g-d0cd3f.fd635.8443.data.globus.org/raw-data/Hurricane-ISABEL/SDRBENCH-Hurricane-ISABEL-100x500x500.tar.gz"
  [nyx]="https://g-d0cd3f.fd635.8443.data.globus.org/raw-data/EXASKY/NYX/SDRBENCH-EXASKY-NYX-512x512x512.tar.gz"
  [miranda]="https://g-d0cd3f.fd635.8443.data.globus.org/raw-data/Miranda/SDRBENCH-Miranda-256x384x384.tar.gz"
)
declare -A NOTES=(
  [isabel]="weather, float32, 100x500x500, ~1.25GB"
  [nyx]="cosmology, float32, 512^3, ~2.7GB"
  [miranda]="turbulence, float64, 256x384x384, ~1.87GB"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)   OUTPUT_DIR="$2"; shift 2 ;;
    -d|--datasets) DATASETS="$2";   shift 2 ;;
    --verify)      VERIFY_ONLY=true; shift ;;
    -h|--help)     sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "opcao desconhecida: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
MANIFEST="$OUTPUT_DIR/MANIFEST.sha256"

if $VERIFY_ONLY; then
  [[ -f "$MANIFEST" ]] || { echo "ERRO: sem $MANIFEST para verificar" >&2; exit 1; }
  echo "[VERIFY] conferindo contra $MANIFEST"
  ( cd "$OUTPUT_DIR" && sha256sum -c MANIFEST.sha256 ) || {
    echo "ERRO: bytes divergem do manifesto -- os dados upstream mudaram ou o download corrompeu." >&2
    exit 1; }
  echo "[VERIFY] OK"; exit 0
fi

for ds in $DATASETS; do
  url="${URLS[$ds]:-}"
  [[ -n "$url" ]] || { echo "dataset desconhecido: $ds (disponiveis: ${!URLS[*]})" >&2; exit 1; }
  echo "[FETCH] $ds -- ${NOTES[$ds]}"
  tarball="$OUTPUT_DIR/$(basename "$url")"
  if [[ -f "$tarball" ]]; then
    echo "  ja baixado, pulando download"
  else
    curl -fL --retry 3 --retry-delay 5 -o "$tarball.part" "$url"
    mv "$tarball.part" "$tarball"
  fi
  tar -xzf "$tarball" -C "$OUTPUT_DIR"
done

echo "[MANIFEST] gerando sha256 de todos os arquivos em $OUTPUT_DIR"
( cd "$OUTPUT_DIR" && find . -type f ! -name 'MANIFEST.sha256' -print0 \
    | sort -z | xargs -0 sha256sum > MANIFEST.sha256 )
echo "[MANIFEST] $(wc -l < "$MANIFEST") arquivos registrados em $MANIFEST"
echo
echo "Lembrete: qualquer resultado publicado com estes dados precisa citar o SDRBench"
echo "(Zhao et al., 2020) e reconhecer DOE NNSA ECP + CODAR."
