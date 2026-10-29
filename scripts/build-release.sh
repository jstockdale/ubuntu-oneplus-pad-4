#!/bin/bash
# Produce a complete, installable release: kernel, rootfs, overlay, userdata
# image, boot bundle, the fastboot installer and a SHA-256 manifest, in one
# ZIP.
#
# Every stage is a separate script that can be run on its own; this only fixes
# the order and the data flow between them.  Nothing is flashed here: the
# owner runs install.sh from the ZIP.
#
# Prerequisites that are deliberately NOT automated here, because they involve
# the owner's proprietary package: scripts/stage-stock-images.sh (once per
# firmware version) and a recorded configs/firmware/iceland.toml.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
version=${RELEASE_VERSION:-$(tr -d '[:space:]' < "$repo/VERSION")}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	echo "invalid release version: $version" >&2
	exit 2
}
profile=${ICELAND_PROFILE:-desktop}
stock=${STOCK_DIR:-$base/stock/current}
artifacts=${ARTIFACTS_DIR:-$repo/artifacts}

test -d "$stock" || {
	echo "no stock staging at $stock; run scripts/stage-stock-images.sh first" >&2
	exit 1
}

# The stock provenance names the firmware this release was built against; the
# identity is stamped into the ZIP name and the manifest so a fleet with mixed
# firmware revisions can tell builds apart, and the installer can refuse a
# mismatch.
post_build=$(python3 -c \
	'import json,sys;print(json.load(open(sys.argv[1]))["post_build"])' \
	"$stock/PROVENANCE.json")
product=$(python3 -c \
	'import json,sys;print(json.load(open(sys.argv[1]))["product"])' \
	"$stock/PROVENANCE.json")

echo "=== release v$version ($profile) against $post_build ==="

bash "$repo/scripts/build-mainline-kernel.sh"
ICELAND_PROFILE=$profile bash "$repo/scripts/build-ubuntu-rootfs.sh"
bash "$repo/scripts/build-rootfs-overlay.sh"
bash "$repo/scripts/build-rootfs-image.sh"

kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
kernel_release=$(cat "$kernel_out/kernel.release")
initramfs=${ROOTFS_DIR:-$base/rootfs}/boot/initrd.img-$kernel_release
INITRAMFS=$initramfs bash "$repo/scripts/build-boot-bundle.sh"

# ---------------------------------------------------------------------------
# Assemble the ZIP
# ---------------------------------------------------------------------------

bundle=$base/out/bundle
image=$base/out/ubuntu-iceland-userdata.img
stagezip=$base/out/release-v$version
rm -rf -- "$stagezip"
mkdir -p "$stagezip"

install -m 0644 "$bundle/boot.img" "$stagezip/"
install -m 0644 "$bundle/init_boot.img" "$stagezip/"
install -m 0644 "$image" "$stagezip/ubuntu-iceland-userdata.img"
install -m 0755 "$repo/configs/install/install.sh" "$stagezip/"
# The fastboot product string ("canoe") is a repo constant, deliberately NOT
# the OTA metadata's product (OPD2514): ABL reports the platform name.
# Confirmed against the iceland-mainline project's install guide; verify on
# first device contact with `fastboot getvar product`.
install -m 0644 "$repo/configs/install/expected-fastboot-product" \
	"$stagezip/EXPECTED-PRODUCT"
install -m 0644 "$bundle/BUILD-METADATA.txt" "$stagezip/"
cp -a "$bundle/evidence" "$stagezip/evidence"

{
	printf 'release=%s\n' "$version"
	printf 'profile=%s\n' "$profile"
	printf 'stock_post_build=%s\n' "$post_build"
	printf 'kernel_release=%s\n' "$kernel_release"
	printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$stagezip/RELEASE.txt"

(cd "$stagezip" && find . -type f ! -name SHA256SUMS -print0 \
	| LC_ALL=C sort -z | xargs -0 sha256sum > SHA256SUMS)

zip_name=ubuntu-26.04-opd2514-v$version.zip
rm -f "$base/out/$zip_name"
(cd "$stagezip" && zip -q -r -X "$base/out/$zip_name" .)

# Released checksums are committed; the blobs themselves never are.
mkdir -p "$artifacts"
sha256sum "$base/out/$zip_name" | sed "s|$base/out/||" \
	> "$artifacts/$zip_name.sha256"
install -m 0644 "$stagezip/RELEASE.txt" "$artifacts/RELEASE-v$version.txt"

echo '=== release ==='
stat -c '%n %s bytes' "$base/out/$zip_name"
cat "$artifacts/$zip_name.sha256"
