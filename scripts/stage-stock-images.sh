#!/bin/bash
# Stage the stock boot.img / init_boot.img templates and the firmware source
# images from the owner's OnePlus OTA package, and record their provenance.
#
# Role in the pipeline: Perpetua's android-gki tool rebuilds our boot images
# FROM the stock ones (keeping their v4 headers and AVB properties), so the
# stock OTA package for the firmware actually installed on the tablet is a
# build input, not just a backup.  This script is the one place that opens it.
#
# It also records the OTA's post-build fingerprint.  The release installer
# refuses to flash a device whose `fastboot getvar product` does not match the
# product recorded here, and refuses entirely while nothing is recorded —
# the gate fails closed.
#
# No proprietary byte enters the repository, and nothing is flashed.
#
# Usage: stage-stock-images.sh OTA.zip
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
ota=${1:?usage: stage-stock-images.sh OTA.zip}
stock_root=${STOCK_ROOT:-$base/stock}
# boot and init_boot are the repack templates.  vendor and odm feed
# stage-firmware.py.  vendor_boot and vbmeta are staged as evidence and for
# recovery, never for flashing by this port.
partitions=${STOCK_PARTITIONS:-boot,init_boot,vendor_boot,vbmeta,dtbo,vendor,odm,modem,bluetooth,dsp}

test -f "$ota" || { echo "no such OTA package: $ota" >&2; exit 1; }
command -v payload-dumper-go >/dev/null || {
	echo 'payload-dumper-go is missing; see scripts/check-build-deps.sh' >&2
	exit 1
}

# --- provenance from the OTA's own metadata ----------------------------------
# A/B OTA zips carry META-INF/com/android/metadata with lines like
#   post-build=OnePlus/<product>/<device>:16/.../...:user/release-keys
#   post-build-incremental=...
# That fingerprint names the exact firmware these templates belong to.
metadata=$(unzip -p "$ota" META-INF/com/android/metadata 2>/dev/null || true)
post_build=$(printf '%s\n' "$metadata" | sed -n 's/^post-build=//p' | head -1)
[ -n "$post_build" ] || {
	echo 'the OTA package has no post-build fingerprint in its metadata;' >&2
	echo 'is this a full OTA zip?  (incremental OTAs cannot be used here)' >&2
	exit 1
}
build_id=$(printf '%s' "$post_build" | tr '/:' '__')
product=$(printf '%s' "$post_build" | cut -d/ -f2)
device=$(printf '%s' "$post_build" | cut -d/ -f3 | cut -d: -f1)

out=$stock_root/$build_id
mkdir -p "$out"

# --- extract the partitions ---------------------------------------------------
# payload-dumper-go reads the payload from inside the OTA zip directly (the
# payload is stored uncompressed, so the zip is seekable); extracting a
# ~7 GiB payload.bin first doubles the disk cost for nothing — and on a
# tmpfs /tmp it simply does not fit.
echo "extracting partitions from ${ota##*/}"
payload-dumper-go -partitions "$partitions" -output "$out" "$ota" >/dev/null

for img in boot init_boot; do
	test -f "$out/$img.img" || {
		echo "the payload produced no $img.img; wrong package?" >&2
		exit 1
	}
done

# --- sanity: the templates must be what android-gki expects -------------------
# Header v4, magic ANDROID!.  Catch a wrong package now, not at bundle time.
for img in boot init_boot; do
	magic=$(head -c8 "$out/$img.img")
	[ "$magic" = 'ANDROID!' ] || {
		echo "$img.img does not look like an Android boot image" >&2
		exit 1
	}
done

# --- provenance ---------------------------------------------------------------
{
	printf '{\n'
	printf '  "tool": "stage-stock-images.sh/1",\n'
	printf '  "ota": "%s",\n' "${ota##*/}"
	printf '  "ota_sha256": "%s",\n' "$(sha256sum "$ota" | cut -d' ' -f1)"
	printf '  "post_build": "%s",\n' "$post_build"
	printf '  "product": "%s",\n' "$product"
	printf '  "device": "%s",\n' "$device"
	printf '  "staged": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf '  "images": {\n'
	first=1
	for img in "$out"/*.img; do
		[ "$first" = 1 ] || printf ',\n'
		first=0
		printf '    "%s": "%s"' "${img##*/}" \
			"$(sha256sum "$img" | cut -d' ' -f1)"
	done
	printf '\n  }\n}\n'
} > "$out/PROVENANCE.json"

# The newest staging is the default input for the rest of the pipeline.
ln -sfn "$out" "$stock_root/current"

echo '=== staged ==='
echo "post-build: $post_build"
echo "product:    $product   device: $device"
echo "stock dir:  $out (symlinked as $stock_root/current)"
ls -l "$out"
