#!/bin/bash
# =============================================================
# hipify_nvcomp.sh - Converte nvcomp CUDA→HIP via hipify-perl
# e gera relatórios de comparação com o port manual
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPE_DIR="$(dirname "$SCRIPT_DIR")"

# --- Caminhos ------------------------------------------------
NVCOMP_SRC="${NVCOMP_SRC:-/ssd/cakunas/devel/nvcomp/src}"
TOOLKIT_SRC="${TOOLKIT_SRC:-/ssd/cakunas/hip-compression-toolkit/src}"

HIPIFY_OUT="$EXPE_DIR/hipify-output/nvcomp-hipified/src"
REPORT_DIR="$EXPE_DIR/hipify-output/reports"

# --- Verifica dependências -----------------------------------
if ! command -v hipify-perl &>/dev/null; then
  echo "ERRO: hipify-perl não encontrado. Instale ROCm ou use o container." >&2
  exit 1
fi

if [ ! -d "$NVCOMP_SRC" ]; then
  echo "ERRO: nvcomp source não encontrado em $NVCOMP_SRC" >&2
  echo "  Clone com: git clone --branch branch-2.2 https://github.com/NVIDIA/nvcomp.git /ssd/cakunas/devel/nvcomp" >&2
  exit 1
fi

# --- Cria diretórios -----------------------------------------
mkdir -p "$HIPIFY_OUT" "$REPORT_DIR"

# --- Mapeamento nvcomp → toolkit (nomes renomeados) ----------
declare -A FILE_MAP=(
  ["BitPackGPU.cu"]="BitPackGPU.hip"
  ["DeltaGPU.cu"]="DeltaGPU.hip"
  ["RunLengthEncodeGPU.cu"]="RunLengthEncodeGPU.hip"
  ["CudaUtils.cu"]="HipUtils.hip"
  ["Check.cpp"]="Check.cpp"
  ["nvcomp_api.cpp"]="hipcomp_api.cpp"
  ["TempSpaceBroker.cpp"]="TempSpaceBroker.cpp"
  ["LZ4Kernels.cuh"]="LZ4Kernels.hiph"
  ["CascadedKernels.cuh"]="CascadedKernels.hiph"
  ["nvcomp_cub.cuh"]="hipcomp_hipcub.hiph"
)

echo "=== Etapa 1: Convertendo nvcomp CUDA → HIP via hipify-perl ==="
for cuda_file in "${!FILE_MAP[@]}"; do
  src="$NVCOMP_SRC/$cuda_file"
  if [ ! -f "$src" ]; then
    echo "  SKIP: $cuda_file (não encontrado)"
    continue
  fi

  # Determina extensão do output
  case "$cuda_file" in
    *.cu)  ext="hip" ;;
    *.cuh) ext="hiph" ;;
    *)     ext="${cuda_file##*.}" ;;
  esac
  base="${cuda_file%.*}"
  out="$HIPIFY_OUT/${base}.${ext}"

  echo "  hipify-perl $cuda_file → $(basename "$out")"
  hipify-perl "$src" > "$out" 2>/dev/null
done

echo ""
echo "=== Etapa 2: Gerando relatórios de comparação ==="

SUMMARY="$REPORT_DIR/comparison_summary.md"
cat > "$SUMMARY" << 'HEADER'
# Comparação: hipify-perl vs Port Manual

Comparação entre a conversão automática (hipify-perl) do nvcomp 2.2
e o port manual no hip-compression-toolkit.

## Resumo por arquivo

| Arquivo Original | hipify→nosso (diff lines) | hipify→AMD (diff lines) | Status |
|---|---|---|---|
HEADER

for cuda_file in "${!FILE_MAP[@]}"; do
  our_file="${FILE_MAP[$cuda_file]}"

  case "$cuda_file" in
    *.cu)  hipified="$HIPIFY_OUT/${cuda_file%.*}.hip" ;;
    *.cuh) hipified="$HIPIFY_OUT/${cuda_file%.*}.hiph" ;;
    *)     hipified="$HIPIFY_OUT/$cuda_file" ;;
  esac

  our_path="$TOOLKIT_SRC/$our_file"

  [ -f "$hipified" ] || continue
  [ -f "$our_path" ] || continue

  our_diff=$(diff "$hipified" "$our_path" | grep -c '^[<>]' || true)

  # AMD hipCOMP-core comparison (optional)
  amd_path="/ssd/cakunas/devel/hipCOMP-core/src/$our_file"
  if [ -f "$amd_path" ]; then
    amd_diff=$(diff "$hipified" "$amd_path" | grep -c '^[<>]' || true)
  else
    amd_diff="N/A"
  fi

  if [ "$our_diff" -eq 0 ]; then
    status="hipify perfeito"
  elif [ "$our_diff" -le 10 ]; then
    status="quase auto"
  else
    status="manual"
  fi

  echo "| $cuda_file | $our_diff | $amd_diff | $status |" >> "$SUMMARY"

  # Gera diff detalhado por arquivo
  diff_file="$REPORT_DIR/diff_${cuda_file%.*}.txt"
  diff -u "$hipified" "$our_path" > "$diff_file" 2>/dev/null || true
done

echo "" >> "$SUMMARY"
echo "Gerado em: $(date -Iseconds)" >> "$SUMMARY"

echo "  Relatório salvo em: $SUMMARY"
echo ""

# --- Etapa 3: Análise quantitativa --------------------------
echo "=== Etapa 3: Análise quantitativa (% portado automaticamente) ==="
bash "$SCRIPT_DIR/hipify_pct.sh"

echo ""
echo "Concluído. Resultados em: $EXPE_DIR/hipify-output/"
