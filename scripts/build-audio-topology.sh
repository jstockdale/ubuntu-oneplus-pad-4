#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Build qcom/kaanapali/OnePlus-Pad4-tplg.bin (AudioReach topology, C4/A0).
#
# Recipe = the Fedora iceland port's: Linaro base + the Pad 4 overlay
# (vendored verbatim in configs/audio/topology/, upstream VOL_CTRL_MAX 8192),
# with the gain cap applied HERE at build time. docs/audio-plan.md §2.1/§4-A0.
#
# VOL_CTRL_MAX: 8192 = 0 dB = stock's stream ceiling (rung A7, 2026-11-02), shipped only
# because the PipeWire speaker-protection chain (device pkg 0.2.18+, swh-plugins) is the
# default sink — that chain IS the amp protection. 2056 (-12 dB) was the bring-up cap the
# ladder was flown on; rebuild it with: VOL_CTRL_MAX=2056 $0
set -euo pipefail

BASE_REPO=https://github.com/linux-msm/audioreach-topology
BASE_PIN=993a17dcb672357998a463a73f120064d6c74f4f   # BSD-3-Clause, Linaro
VOL_CTRL_MAX="${VOL_CTRL_MAX:-8192}"

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$PROJ/configs/audio/topology"               # mzakamin-hub/iceland-mainline @ a7aab9f, audio/topology/
OUT="${OUT:-/srv/ubuntu-iceland/out/rootfs-overlay/lib/firmware/qcom/kaanapali}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q "$BASE_REPO" "$WORK/audioreach-topology"
git -C "$WORK/audioreach-topology" checkout -q "$BASE_PIN"
cp -a "$OVERLAY/." "$WORK/audioreach-topology/"
rm -f "$WORK/audioreach-topology/LICENSE.audioreach-topology"

cd "$WORK/audioreach-topology"
sed -i "s/define(\`VOL_CTRL_MAX', \`8192')dnl/define(\`VOL_CTRL_MAX', \`$VOL_CTRL_MAX')dnl/" OnePlus-Pad4.m4
m4 -I . OnePlus-Pad4.m4 > OnePlus-Pad4.conf
# Gate G-A0 part 1: the cap really is in the compiled conf (3 capped subgraphs).
hits=$(grep -c "max \"$VOL_CTRL_MAX\"" OnePlus-Pad4.conf)
[ "$hits" -ge 1 ] || { echo "FAIL: VOL_CTRL_MAX $VOL_CTRL_MAX not in conf" >&2; exit 1; }
# alsatplg prints 'undefined sink widget' for BE streams the kernel defines
# at runtime from the DT — expected; only a non-zero exit is a failure.
alsatplg -c OnePlus-Pad4.conf -o OnePlus-Pad4-tplg.bin

mkdir -p "$OUT"
install -m0644 OnePlus-Pad4-tplg.bin "$OUT/OnePlus-Pad4-tplg.bin"
echo "built: $OUT/OnePlus-Pad4-tplg.bin (VOL_CTRL_MAX=$VOL_CTRL_MAX, cap hits=$hits)"
sha256sum "$OUT/OnePlus-Pad4-tplg.bin"
