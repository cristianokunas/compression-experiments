#!/bin/bash
# =============================================================================
# Paper2 baseline + pinned sweep wrapper.
#
# Runs the existing run_benchmarks_auto.sh TWICE in sequence inside a single
# Singularity image:
#   1. baseline  (no flags)            -- reproduces the ICCSA26 columns
#   2. pinned    (-P --skip-testdata)  -- coalesce+pin H2D (paper2 optimization)
#
# Both passes share the same SIF and the same testdata, so the only variable
# is the new -P/--pinned-input flag. The combined output lands under one
# timestamped MI<arch>_PAPER2_FULL_<TS>/ directory with separate baseline/
# and pinned/ subtrees -- the runner appends _PINNED to the EnvLabel column
# on the second pass so a downstream concat is unambiguous.
#
# Used to produce paper/ARCTO-optim/results/MI300X_PAPER2_FULL_20260518_030032/
# (committed in compression-experiments@c0198b6).
#
# Required environment / defaults:
#   SIF      path to ARCTO singularity image (default: arcto_gfx942.sif in cwd)
#   TD       host testdata directory bind-mounted to /home/ckunas/testdata
#            inside the container (must already contain ICCSA26 dataset
#            -- generate_testdata.sh fills synth files, TTI must be present)
#   OUT_ROOT base output directory (default: $HOME/results)
#
# Usage:
#   ./scripts/run_paper2_baseline_pinned.sh
#   SIF=/path/to/arcto_gfx942.sif TD=/path/to/testdata \
#       ./scripts/run_paper2_baseline_pinned.sh
# =============================================================================

set -e

SIF="${SIF:-./arcto_gfx942.sif}"
TD="${TD:-$HOME/testdata}"
OUT_ROOT="${OUT_ROOT:-$HOME/results}"
TS=$(date +%Y%m%d_%H%M%S)
BASE="$OUT_ROOT/MI_PAPER2_FULL_${TS}"
mkdir -p "$BASE/baseline" "$BASE/pinned"

[ -f "$SIF" ] || { echo "missing SIF $SIF"; exit 1; }
[ -d "$TD" ]  || { echo "missing testdata dir $TD"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=========================================================="
echo "[1/2] BASELINE sweep (no -P)  --> $BASE/baseline"
echo "=========================================================="
singularity exec --rocm -B "$TD:$TD" -B "$HOME:$HOME" "$SIF" \
    ./scripts/run_benchmarks_auto.sh \
        -d "$TD" \
        -o "$BASE/baseline" \
        --skip-testdata

echo
echo "=========================================================="
echo "[2/2] PINNED sweep (-P --skip-testdata) --> $BASE/pinned"
echo "=========================================================="
singularity exec --rocm -B "$TD:$TD" -B "$HOME:$HOME" "$SIF" \
    ./scripts/run_benchmarks_auto.sh \
        -d "$TD" \
        -o "$BASE/pinned" \
        --skip-testdata \
        -P

echo
echo "=========================================================="
echo "DONE -- combined results under: $BASE"
ls "$BASE/baseline/" | head -3
echo "  ..."
ls "$BASE/pinned/"   | head -3
