#!/bin/bash
# Modified post_install.sh: configures the Grid'5000 node AND kicks off
# the canonical synthetic-dataset generation in the background as ckunas,
# so the datasets are ready (or close to it) by the time the user logs in.
#
# The TTI dataset suite is NOT generated here because it depends on
# TTI.rsf@ being already present in ~/testdata/source/, which is the
# subject of an external rsync transfer. The user generates TTI at the
# start of the session once the rsync completes.
#
# Drop-in replacement for the original post_install.sh.
set -e

NODE="vianden-1"

echo "[*] Connecting to $NODE as root to provision..."

ssh -o StrictHostKeyChecking=no root@"$NODE" bash << 'ENDSSH'
set -e

echo "[1/5] Installing base packages..."
apt update
apt install -y sudo git nano software-properties-common rsync

echo "[2/5] Configuring ckunas with passwordless sudo..."
/sbin/adduser ckunas sudo 2>/dev/null || true
echo "%sudo   ALL=(ALL:ALL) NOPASSWD: ALL" | tee -a /etc/sudoers

echo "[3/5] Installing Apptainer..."
add-apt-repository -y ppa:apptainer/ppa
apt update
apt install -y apptainer
apptainer --version

echo "[4/5] Preparing canonical-dataset scratch directory..."
# /tmp on Grid'5000 vianden is typically backed by local SSD/HDD with
# tens of GB free; choose a host-local persistent path so that the
# 125 GB synthetic suite does not hit tmpfs / ramdisk. If /tmp is
# small, /local is often the convention.
for candidate in /tmp /local /scratch; do
  if [ -d "$candidate" ]; then
    free_gb=$(df -BG --output=avail "$candidate" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -n "$free_gb" ] && [ "$free_gb" -ge 150 ]; then
      SCRATCH="$candidate/arcto_canonical"
      break
    fi
  fi
done
SCRATCH="${SCRATCH:-/tmp/arcto_canonical}"
mkdir -p "$SCRATCH"
chown -R ckunas:ckunas "$SCRATCH"
echo "scratch dir : $SCRATCH (free: ${free_gb:-unknown} GB)"
echo "$SCRATCH" > /home/ckunas/.arcto_scratch_dir
chown ckunas:ckunas /home/ckunas/.arcto_scratch_dir

echo "[5/5] Kicking off synthetic dataset generation in the background (as ckunas)..."
# The regen_synthetic_canonical.sh script does not need the SIF nor
# the GPU, only Python3 (already on the system). It generates 18 files
# (zeros/random/binary x 6 sizes) of ~117 GB total. Runs in ~5-15
# minutes on local SSD.
#
# Logged to /home/ckunas/.arcto_dataset_gen.log so the user can check
# status on first login.
GEN_SCRIPT=/home/ckunas/compression-experiments/paper/ARCTO-optim/draft/regen_synthetic_canonical.sh
if [ -x "$GEN_SCRIPT" ]; then
  su - ckunas -c "nohup $GEN_SCRIPT $SCRATCH > /home/ckunas/.arcto_dataset_gen.log 2>&1 &" \
    && echo "  background generation launched as ckunas"
  echo "  status check after login:  tail -f ~/.arcto_dataset_gen.log"
  echo "  scratch dir saved in:      ~/.arcto_scratch_dir"
else
  echo "  WARNING: $GEN_SCRIPT missing or not executable"
  echo "  user will need to run it manually after login."
fi

echo "[OK] post-install done."
ENDSSH

echo "[*] node $NODE provisioned successfully."
echo ""
echo "On first login as ckunas, expect:"
echo "  ~/.arcto_dataset_gen.log    - synthetic dataset generation progress"
echo "  ~/.arcto_scratch_dir        - path of the canonical scratch dir"
echo ""
echo "For the TTI suite (depends on rsync of TTI.rsf@), run after the rsync completes:"
echo "  SRC=~/testdata/source/TTI.rsf@ \\"
echo "    OUT_DIR=\$(cat ~/.arcto_scratch_dir) \\"
echo "    ~/compression-experiments/paper/ARCTO-optim/draft/regen_tti_canonical.sh"
echo ""
echo "Then the full sweep:"
echo "  DATA_DIR=\$(cat ~/.arcto_scratch_dir) \\"
echo "    ~/compression-experiments/paper/ARCTO-optim/draft/sweep_canonical.sh"
