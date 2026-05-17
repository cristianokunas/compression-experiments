#!/bin/bash
# Análise: % do código portado automaticamente vs intervenção manual.
#
# Compara três versões do mesmo arquivo:
#   1. CUDA original (nvcomp)
#   2. Saída do hipify-perl rodando sobre o nvcomp
#   3. Nosso port manual no arcto
# e reporta quantas linhas cada etapa modificou.
#
# Configure os três diretórios via env vars (ou edite os defaults abaixo):
#   NVCOMP_SRC    -- raiz do checkout do nvcomp (padrão: ./devel/nvcomp)
#   HIPIFY_OUT    -- saída do hipify_nvcomp.sh sobre o nvcomp acima
#                    (padrão: ./compression-experiments/hipify-output/nvcomp-hipified)
#   ARCTO_SRC     -- raiz do checkout do arcto (padrão: ./arcto)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPE_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_ROOT="$(dirname "$EXPE_ROOT")"
cd "$WORK_ROOT"

NV="${NVCOMP_SRC:-devel/nvcomp}"
HF="${HIPIFY_OUT:-compression-experiments/hipify-output/nvcomp-hipified}"
TK="${ARCTO_SRC:-arcto}"

# nvcomp_file : hipified_file : our_file
PAIRS=(
  "$NV/src/BitPackGPU.cu|$HF/src/BitPackGPU.hip|$TK/src/BitPackGPU.hip"
  "$NV/src/DeltaGPU.cu|$HF/src/DeltaGPU.hip|$TK/src/DeltaGPU.hip"
  "$NV/src/RunLengthEncodeGPU.cu|$HF/src/RunLengthEncodeGPU.hip|$TK/src/RunLengthEncodeGPU.hip"
  "$NV/src/CudaUtils.cu|$HF/src/CudaUtils.hip|$TK/src/HipUtils.hip"
  "$NV/src/Check.cpp|$HF/src/Check.cpp|$TK/src/Check.cpp"
  "$NV/src/nvcomp_api.cpp|$HF/src/nvcomp_api.cpp|$TK/src/arcto_api.cpp"
  "$NV/src/TempSpaceBroker.cpp|$HF/src/TempSpaceBroker.cpp|$TK/src/TempSpaceBroker.cpp"
  "$NV/src/LZ4Kernels.cuh|$HF/src/LZ4Kernels.hiph|$TK/src/LZ4Kernels.hiph"
  "$NV/src/CascadedKernels.cuh|$HF/src/CascadedKernels.hiph|$TK/src/CascadedKernels.hiph"
  "$NV/src/nvcomp_cub.cuh|$HF/src/nvcomp_cub.hiph|$TK/src/arcto_hipcub.hiph"
)

GT=0; GU=0; GH=0; GM=0

printf "%-28s %6s %6s %6s %6s  %s\n" "Arquivo" "Total" "NoChg" "Hipfy" "Manual" "Status"
printf "%-28s %6s %6s %6s %6s  %s\n" "---" "---" "---" "---" "---" "---"

for pair in "${PAIRS[@]}"; do
  IFS='|' read -r orig hipf final <<< "$pair"
  test -f "$orig" || continue
  test -f "$final" || continue

  total=$(wc -l < "$orig")
  GT=$((GT + total))

  if [ -f "$hipf" ]; then
    hc=$(diff "$orig" "$hipf" | grep -c '^[<>]')
    mc=$(diff "$hipf" "$final" | grep -c '^[<>]')
    # each diff line pair = 1 changed line, approximate unique
    hc=$((hc / 2))
    mc=$((mc / 2))
  else
    hc=0
    mc=$(diff "$orig" "$final" | grep -c '^[<>]')
    mc=$((mc / 2))
  fi

  uc=$((total - hc - mc))
  test $uc -lt 0 && uc=0

  GU=$((GU + uc)); GH=$((GH + hc)); GM=$((GM + mc))

  if [ $mc -eq 0 ] && [ $hc -eq 0 ]; then
    st="Sem mudanca"
  elif [ $mc -eq 0 ]; then
    st="hipify OK"
  elif [ $mc -le 3 ]; then
    st="Quase auto"
  else
    st="Manual"
  fi

  fname=$(basename "$orig")
  printf "%-28s %6d %6d %6d %6d  %s\n" "$fname" "$total" "$uc" "$hc" "$mc" "$st"
done

AUTO=$((GU + GH))
echo ""
echo "======================================================"
echo "TOTAL linhas originais (CUDA):  $GT"
echo ""
echo "  Sem mudanca (C++ puro):       $GU  ($(echo "scale=1; $GU*100/$GT" | bc)%)"
echo "  hipify-perl converte:         $GH  ($(echo "scale=1; $GH*100/$GT" | bc)%)"
echo "  Intervencao manual:           $GM  ($(echo "scale=1; $GM*100/$GT" | bc)%)"
echo ""
echo "  PORTADO AUTOMATICAMENTE:      $AUTO / $GT  ($(echo "scale=1; $AUTO*100/$GT" | bc)%)"
echo "  REQUER TRABALHO MANUAL:       $GM / $GT  ($(echo "scale=1; $GM*100/$GT" | bc)%)"
echo "======================================================"
