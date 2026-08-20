#!/bin/bash
# commit-sweep.sh -- run the optimization-loop measurement over a list of
# commits, everything inside the toolchain image.
#
# This is the executable form of OPTIMIZATION-LOOP.md sections 6 and 7: each
# listed commit is checked out exactly, built inside the pinned-ROCm image,
# gated on the compressibility ladder in exact bytes, then measured with
# per-repetition output. Feeding it the kept commits in merge order produces
# the progression ladder; feeding it one attempt commit replays that attempt
# on this architecture.
#
# Usage:
#   ./commit-sweep.sh --sif IMG --source BUNDLE_OR_REPO --commits FILE [options]
#
#   --sif IMG          toolchain image (ROCm, hipcc, cmake inside)
#   --source PATH      git bundle or repository to clone the code from
#   --commits FILE     one commit per line: "<ref> [extra cmake -D flags...]"
#                      lines starting with # are ignored; the SAME ref may
#                      appear on several lines with different flags (variants)
#   --out DIR          results root (default: ./sweep_<host>_<timestamp>)
#   --reps N           timed repetitions per commit (default 30)
#   --chunk BYTES      chunk size (default 65536)
#   --input REL        throughput input, path relative to the repo
#                      (default tests/data/tti_rsf_64x64x64_t050.bin)
#   --dup N            -x duplication for the throughput input (default 512)
#   --clean-builds     remove each build dir after its runs (default: keep,
#                      so any commit can be re-run without rebuilding)
#
# Results layout under --out:
#   provenance.txt              session-level provenance
#   perrep.csv                  per-repetition rows, Tag = <shortsha>[_vN]
#   ratio_<tag>_<file>.csv      exact-bytes gate runs, full ladder per commit
#   summary.txt                 medians + the exact-bytes matrix across commits
#   work/arcto                  the clone (build_* dirs inside unless cleaned)
set -u
set -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF="" SRC="" COMMITS="" OUTDIR="" REPS=30 CHUNK=65536 DUP=512
INPUT_REL="tests/data/tti_rsf_64x64x64_t050.bin"
CLEAN_BUILDS=false

while [ $# -gt 0 ]; do
  case "$1" in
    --sif) SIF="$2"; shift 2 ;;
    --source) SRC="$2"; shift 2 ;;
    --commits) COMMITS="$2"; shift 2 ;;
    --out) OUTDIR="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    --chunk) CHUNK="$2"; shift 2 ;;
    --input) INPUT_REL="$2"; shift 2 ;;
    --dup) DUP="$2"; shift 2 ;;
    --clean-builds) CLEAN_BUILDS=true; shift ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SIF" ] && [ -n "$SRC" ] && [ -n "$COMMITS" ] || { echo "obrigatorios: --sif --source --commits (veja --help)" >&2; exit 2; }
[ -f "$SIF" ] || { echo "imagem nao encontrada: $SIF" >&2; exit 1; }
[ -f "$COMMITS" ] || { echo "lista de commits nao encontrada: $COMMITS" >&2; exit 1; }
# o laco muda de diretorio: caminhos viram absolutos aqui, ou param de resolver
SIF=$(readlink -f "$SIF"); COMMITS=$(readlink -f "$COMMITS")
[ -e "$SRC" ] && SRC=$(readlink -f "$SRC")

# --- node probe --------------------------------------------------------------
eval "$("$HERE/check-node.sh" --sif "$SIF" 2>/dev/null | grep -E '^(RUNTIME|RUNTIME_BIN|GPU_DEV|GFX_ARCH|WAVE32_FLAG|NPROC)=')" || true
[ "${RUNTIME:-none}" != none ] || { echo "sem runtime de container" >&2; exit 1; }
[ "${GPU_DEV:-no}" = yes ]     || { echo "sem /dev/kfd (driver amdgpu)" >&2; exit 1; }
[ -n "${GFX_ARCH:-}" ]         || { echo "gfx nao detectado" >&2; exit 1; }
export HIP_VISIBLE_DEVICES=${HIP_VISIBLE_DEVICES:-0}

OUTDIR=${OUTDIR:-"$PWD/sweep_$(hostname -s)_$(date +%Y%m%d_%H%M%S)"}
WORK="$OUTDIR/work"
mkdir -p "$OUTDIR" "$WORK"
inSIF() { "$RUNTIME_BIN" exec --rocm -B "$HOME" -B "$OUTDIR" "$SIF" bash -c "$1"; }

# --- code --------------------------------------------------------------------
if [ ! -d "$WORK/arcto/.git" ]; then
  git clone -q "$SRC" "$WORK/arcto" || { echo "clone falhou de $SRC" >&2; exit 1; }
fi
cd "$WORK/arcto"
# Um clone de bundle pode vir sem HEAD (arvore vazia): o primeiro checkout
# por commit resolve isso, e o submodulo e inicializado preguicosamente logo
# depois, dentro do laco -- bundles nao carregam submodulos.

# --- stack guard (never measure on a wedged driver) --------------------------
inSIF 'cat > /tmp/hipmin.hip <<H
#include <hip/hip_runtime.h>
#include <cstdio>
__global__ void k(int* p){ p[threadIdx.x] = threadIdx.x * 2; }
int main(){ int n=64,*d=nullptr,h[64]={0};
  if(hipMalloc(&d,n*sizeof(int))!=hipSuccess){printf("hipMalloc FALHOU\n");return 1;}
  hipLaunchKernelGGL(k,dim3(1),dim3(n),0,0,d);
  if(hipDeviceSynchronize()!=hipSuccess){printf("sync FALHOU\n");return 1;}
  hipMemcpy(h,d,n*sizeof(int),hipMemcpyDeviceToHost);
  printf("HIP OK %d\n",h[10]); hipFree(d); return 0; }
H
hipcc --offload-arch='"$GFX_ARCH"' /tmp/hipmin.hip -o /tmp/hipmin 2>/dev/null && /tmp/hipmin' \
  || { echo "ABORT: stack HIP nao esta saudavel" >&2; exit 1; }

# print completo do no junto de cada campanha: a pergunta "isso foi a CPU?"
# chega meses depois, quando o no ja foi reimageado
"$HERE/snapshot-node.sh" --out "$OUTDIR/node-snapshot" --sif "$SIF" --results-dir "$OUTDIR" >&2 || true

{ echo "date=$(date -Is)"; echo "host=$(hostname)"; echo "gfx=$GFX_ARCH"
  echo "sif=$SIF"; echo "rocm=$(inSIF 'cat /opt/rocm/.info/version')"
  echo "source=$SRC"; echo "commits_file=$COMMITS"
  echo "reps=$REPS chunk=$CHUNK input=$INPUT_REL dup=$DUP"
  echo "HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES"; } > "$OUTDIR/provenance.txt"

# --- the sweep ---------------------------------------------------------------
IDX=0
declare -A SEEN
grep -vE '^\s*(#|$)' "$COMMITS" | while read -r REF FLAGS; do
  IDX=$((IDX+1))
  git checkout -q "$REF" || { echo "[$IDX] checkout falhou: $REF" >&2; continue; }
  if [ ! -e third_party/zfp/CMakeLists.txt ]; then
    git submodule update --init third_party/zfp \
      || { echo "submodulo zfp indisponivel (sem rede?); copie de um checkout existente" >&2; exit 1; }
  fi
  SHORT=$(git rev-parse --short HEAD)
  TAG="$SHORT"
  # a mesma ref com flags diferentes vira variantes _v2, _v3...
  if [ -n "${SEEN[$SHORT]:-}" ]; then
    SEEN[$SHORT]=$(( ${SEEN[$SHORT]} + 1 )); TAG="${SHORT}_v${SEEN[$SHORT]}"
  else SEEN[$SHORT]=1; fi
  B="build_${TAG}"
  ALLFLAGS="$WAVE32_FLAG $FLAGS"

  echo "[$IDX] $TAG  ($(git log -1 --format=%s | cut -c1-60))  flags:$ALLFLAGS"
  if [ ! -x "$B/bin/benchmark_lz4_chunked" ]; then
    inSIF "cd $WORK/arcto && cmake -S . -B $B \
      -D CMAKE_PREFIX_PATH=/opt/rocm -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -D CMAKE_HIP_ARCHITECTURES=$GFX_ARCH -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_BENCHMARKS=ON -D BUILD_TESTS=OFF \
      -D CMAKE_HIP_FLAGS='$ALLFLAGS' -D CMAKE_CXX_FLAGS='$ALLFLAGS' \
      > $B.configure.log 2>&1 \
      && cmake --build $B -j $NPROC --target benchmark_lz4_chunked > $B.build.log 2>&1" \
      || { echo "[$IDX] BUILD FAIL $TAG"; tail -5 "$B.build.log" 2>/dev/null; continue; }
  fi
  { echo "commit=$(git rev-parse HEAD)"; echo "describe=$(git describe --tags --always 2>/dev/null)"
    echo "tag=$TAG"; echo "flags=$ALLFLAGS"; } > "$B/ATTEMPT"

  # gate primeiro: escada completa em bytes exatos
  for F in tests/data/*.bin; do
    FN=$(basename "$F" .bin)
    inSIF "cd $WORK/arcto && LD_LIBRARY_PATH=$B/lib:/opt/rocm/lib \
      $B/bin/benchmark_lz4_chunked -f $F -p $CHUNK -w 1 -i 2 -c true -g 0 -x 64" \
      > "$OUTDIR/ratio_${TAG}_${FN}.csv" 2>/dev/null
  done
  echo "[$IDX] gate $TAG registrado"

  # vazao por repeticao
  inSIF "cd $WORK/arcto && LD_LIBRARY_PATH=$B/lib:/opt/rocm/lib \
    ARCTO_PER_REP_CSV=$OUTDIR/perrep.csv ARCTO_PER_REP_TAG=$TAG \
    $B/bin/benchmark_lz4_chunked -f $INPUT_REL -p $CHUNK -x $DUP -w 3 -i $REPS -c true -g 0" \
    > "$OUTDIR/${TAG}_perf.csv" 2> "$OUTDIR/${TAG}_perf.err"
  echo "[$IDX] perf $TAG rc=$?"

  [ "$CLEAN_BUILDS" = true ] && rm -rf "$B"
done

# nunca declarar sucesso sem resultado: o smoke pegou exatamente isso
[ -s "$OUTDIR/perrep.csv" ] || { echo "ERRO: nenhum resultado produzido (veja o log acima)" >&2; exit 1; }

# --- summary -----------------------------------------------------------------
python3 - "$OUTDIR" > "$OUTDIR/summary.txt" <<'PY'
import csv, glob, os, sys, statistics as st, collections
out = sys.argv[1]
try:
    rows = list(csv.DictReader(open(os.path.join(out, "perrep.csv"))))
except FileNotFoundError:
    rows = []
g = collections.defaultdict(list)
for r in rows: g[r["Tag"]].append(float(r["CompThroughputGBs"]))
print("== vazao de compressao (mediana [Q1-Q3]) ==")
prev = None
for t in g:  # insertion order = sweep order
    v = sorted(g[t]); n = len(v)
    m = st.median(v)
    step = f"  {m/prev:5.3f}x vs anterior" if prev else ""
    print(f"  {t:20} {m:8.2f} GB/s  [{v[n//4]:.2f} - {v[3*n//4]:.2f}]  n={n}{step}")
    prev = m
tags = list(g)
if len(tags) > 1 and prev:
    first = st.median(sorted(g[tags[0]]))
    print(f"  ganho total {tags[-1]} / {tags[0]}: {prev/first:.2f}x")
print("\n== portao: bytes exatos por arquivo da escada ==")
# deriva os nomes de arquivo da escada a partir dos globs POR TAG, porque
# tags de variante contem '_' e um split posicional erraria o corte
files = set()
for t in tags:
    for f in glob.glob(os.path.join(out, f"ratio_{t}_*.csv")):
        files.add(os.path.basename(f)[len(f"ratio_{t}_"):-len(".csv")])
files = sorted(files)
def comp_bytes(path):
    r = list(csv.reader(open(path))); h = [c.strip() for c in r[0]]
    return int(r[1][h.index("Compressed size in bytes")])
for fn in files:
    vals = {}
    for t in tags:
        p = os.path.join(out, f"ratio_{t}_{fn}.csv")
        if os.path.exists(p):
            try: vals[t] = comp_bytes(p)
            except Exception: vals[t] = None
    uniq = {v for v in vals.values() if v is not None}
    mark = "  " if len(uniq) <= 1 else "!!"
    print(f"  {mark} {fn:28} " + " ".join(f"{t}={v}" for t, v in vals.items()))
print("\n('!!' = bytes mudaram entre commits: compare com a linha de base da")
print(" tentativa antes de aceitar; mudanca de razao e o sinal de falha silenciosa)")
PY
echo "===== SWEEP DONE ====="
echo "resultados: $OUTDIR (summary.txt)"
