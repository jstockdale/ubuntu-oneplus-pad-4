#!/bin/bash
# Capture this unit's factory data — the partitions no OTA carries and no
# reflash can recreate — from the tablet over SSH, into the stock archive.
#
# Run it as THE FIRST ACT of the first booted Ubuntu (checkpoint 7, before
# anything else is touched): persist holds the per-unit sensor calibration
# and registry (the iceland-firmware project extracts its registry from
# exactly here), modemst1/2 and fsg hold Qualcomm NV/RF data, and
# oplusreserve* hold OnePlus per-unit blobs. None of these are ever written
# by this port — this backup is belt and braces for repair shops, future
# ports and mistakes we have not imagined yet.
#
# Usage: capture-device-data.sh <ssh-destination> [label]
#        e.g. capture-device-data.sh ubuntu@192.168.1.57 iceland-dev-1
# Reads from the tablet, writes only under the local stock archive.
set -euo pipefail

base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
dest=${1:?usage: capture-device-data.sh <ssh-destination> [label]}
label=${2:-iceland-$(date +%Y%m%d)}
out=$base/stock/device-capture/$label

# The candidate list; each is captured only if the tablet has it. The GPT
# inventory recorded below is the authority on what exists.
partitions='persist modemst1 modemst2 fsg fsc devinfo engineering_cdt
oplusreserve1 oplusreserve2 oplusreserve3 oplusreserve4 oplusreserve5'

mkdir -p "$out"
echo "capturing from $dest into $out"

# Inventory first: every by-name partition and the GPT, so the capture is
# interpretable years from now.
ssh "$dest" 'ls -l /dev/disk/by-partlabel/' > "$out/by-partlabel.txt"
ssh "$dest" 'cat /proc/partitions' > "$out/proc-partitions.txt"

captured=0
for p in $partitions; do
	if ! ssh "$dest" "test -e /dev/disk/by-partlabel/$p"; then
		echo "  $p: not present, skipped"
		continue
	fi
	# Suffixed A/B copies (persist usually is not slotted; these are).
	echo "  $p: capturing"
	ssh "$dest" "sudo dd if=/dev/disk/by-partlabel/$p bs=1M status=none | gzip -c" \
		> "$out/$p.img.gz"
	captured=$((captured + 1))
done
# Slotted variants, where present.
for p in modemst1_a modemst1_b modemst2_a modemst2_b fsg_a fsg_b; do
	if ssh "$dest" "test -e /dev/disk/by-partlabel/$p" 2>/dev/null; then
		echo "  $p: capturing"
		ssh "$dest" "sudo dd if=/dev/disk/by-partlabel/$p bs=1M status=none | gzip -c" \
			> "$out/$p.img.gz"
		captured=$((captured + 1))
	fi
done

(cd "$out" && sha256sum ./*.gz ./*.txt > SHA256SUMS)
{
	printf 'captured=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'source=%s\n' "$dest"
	printf 'label=%s\n' "$label"
	printf 'partitions=%s\n' "$captured"
} > "$out/CAPTURE-METADATA.txt"

echo "=== $captured partition(s) captured ==="
cat "$out/SHA256SUMS"
echo
echo 'Archive this directory with the stock OTA zip — same retention, same'
echo 'reason: it is the part of the tablet no download can ever replace.'
