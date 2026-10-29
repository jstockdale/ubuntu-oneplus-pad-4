#!/bin/bash
# Package the Perpetua kernel and the Ubuntu initramfs as the two Android GKI
# boot images this device flashes, using Perpetua's own tool.
#
# This replaces the gts9u port's build-android-v4-bundle.sh wholesale, and the
# difference is the whole point of the iceland boot strategy: Perpetua's
# devices/boot/android-gki rewrites the owner's STOCK boot.img / init_boot.img
# (keeping their v4 headers, partition sizes, AVB salts and properties), so no
# vendor_boot, dtbo or vbmeta image exists here at all.  The DTB is built into
# the kernel; the cmdline stays whatever stock vendor_boot says.
#
# Inputs: the stock templates from stage-stock-images.sh and the artifacts of
# build-mainline-kernel.sh / make-initramfs.sh.  This script never flashes
# anything.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
kernel_src=${KERNEL_SRC:-$base/linux-perpetua}
kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
stock=${STOCK_DIR:-$base/stock/current}
out_dir=${BUNDLE_OUT_DIR:-$base/out/bundle}
initramfs=${INITRAMFS:?set INITRAMFS to the Ubuntu initramfs to package}

android_gki=$kernel_src/devices/boot/android-gki
image=$kernel_out/Image

for file in "$android_gki" "$image" "$initramfs" \
	"$stock/boot.img" "$stock/init_boot.img" "$stock/PROVENANCE.json"; do
	test -f "$file" || { echo "missing input: $file" >&2; exit 1; }
done
for tool in avbtool unpack_bootimg; do
	command -v "$tool" >/dev/null || {
		echo "$tool is missing; see scripts/check-build-deps.sh" >&2
		exit 1
	}
done

rm -rf -- "$out_dir"
mkdir -p "$out_dir" "$out_dir/evidence"

# android-gki asserts the template invariants itself (v4 header, no boot
# signature, no foreign payload) and verifies the result with avbtool and
# unpack_bootimg; EVIDENCE keeps those proofs with the artifacts.
python3 "$android_gki" boot \
	"$stock/boot.img" "$image" \
	"$out_dir/boot.img" "$out_dir/evidence" \
	> "$out_dir/evidence/boot.json"
python3 "$android_gki" init_boot \
	"$stock/init_boot.img" "$initramfs" \
	"$out_dir/init_boot.img" "$out_dir/evidence" \
	> "$out_dir/evidence/init_boot.json"

( cd "$out_dir" && sha256sum ./*.img > SHA256SUMS )
{
	printf 'kernel_source=%s\n' "$(git -C "$kernel_src" rev-parse HEAD)"
	printf 'kernel_release=%s\n' "$(cat "$kernel_out/kernel.release")"
	printf 'kernel_payload_sha256=%s\n' "$(sha256sum "$image" | cut -d' ' -f1)"
	printf 'kernel_config_sha256=%s\n' \
		"$(sha256sum "$kernel_out/kernel.config" | cut -d' ' -f1)"
	printf 'initramfs_sha256=%s\n' "$(sha256sum "$initramfs" | cut -d' ' -f1)"
	printf 'stock_post_build=%s\n' \
		"$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["post_build"])' \
			"$stock/PROVENANCE.json")"
	printf 'stock_boot_sha256=%s\n' \
		"$(sha256sum "$stock/boot.img" | cut -d' ' -f1)"
	printf 'stock_init_boot_sha256=%s\n' \
		"$(sha256sum "$stock/init_boot.img" | cut -d' ' -f1)"
	printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$out_dir/BUILD-METADATA.txt"

cat "$out_dir/SHA256SUMS"
