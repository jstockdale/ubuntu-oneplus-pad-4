#!/bin/bash
# Assemble the overlay that the image build merges over the rootfs: the
# verified proprietary firmware staging, and nothing else yet.
#
# Scope note, same discipline as the gts9u port at this stage: this covers
# what the kernel needs to reach userspace with graphics, Wi-Fi and audio DSP
# firmware available.  UCM profiles, udev rules and recovery services arrive
# later, one at a time, each only once the matching regression has been
# observed under Ubuntu on this device.
#
# No proprietary blob is ever copied into this repository, and nothing is
# flashed here.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
overlay=${OVERLAY_OUT_DIR:-$base/out/rootfs-overlay}
stock=${STOCK_DIR:-$base/stock/current}
manifest=${FIRMWARE_MANIFEST:-$repo/configs/firmware/iceland.toml}

test -d "$stock" || {
	echo "missing stock staging: $stock" >&2
	echo 'run scripts/stage-stock-images.sh <full OTA zip> first' >&2
	exit 1
}

# stage-firmware.py fails fast and completely: a hash mismatch or a missing
# blob refuses the whole overlay, so an image can never silently ship without,
# say, Wi-Fi firmware.
python3 "$repo/scripts/stage-firmware.py" stage \
	--manifest "$manifest" \
	--stock "$stock" \
	--out "$overlay"

echo '=== overlay ==='
find "$overlay" -type f | sed "s|^$overlay/||" | sort
