#!/bin/bash
# Build the RAM-boot test image: one from-scratch Android v4 boot image
# carrying BOTH the Perpetua kernel and the Ubuntu initramfs, for
# `fastboot boot` only.
#
# Why a separate image: in the flash layout the ramdisk lives in init_boot,
# but `fastboot boot` downloads a single boot image and does not read the
# flashed init_boot — a RAM boot of our real boot.img would come up with
# Android's generic ramdisk.  A RAM boot also needs no stock template and no
# AVB footer: the bootloader boots the downloaded image directly, which is
# exactly what makes this the zero-write smoke test.
#
# What stays the same as a real boot: the stock vendor_boot still supplies
# the cmdline and prepends its vendor ramdisk, so this test exercises the
# same concatenation and the same no-root= discovery path as a flashed
# install (boot-strategy.md assumptions 1 and 3; a successful run also
# answers them).
#
# This script only writes a file and prints the command; running fastboot is
# the owner's move, deliberately.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
kernel_release=${KERNEL_RELEASE:-$(cat "$kernel_out/kernel.release" 2>/dev/null || true)}
rootfs=${ROOTFS_DIR:-$base/rootfs}
initramfs=${INITRAMFS:-$rootfs/boot/initrd.img-$kernel_release}
stock=${STOCK_DIR:-$base/stock/current}
out=${TEST_BOOT_OUT:-$base/out/test-boot.img}

image=$kernel_out/Image
test -f "$image" || {
	echo "missing kernel: $image" >&2
	echo 'run scripts/build-mainline-kernel.sh first' >&2
	exit 1
}
test -f "$initramfs" || {
	echo "missing initramfs: $initramfs" >&2
	echo 'build the rootfs (which generates it), or point INITRAMFS at one' >&2
	exit 1
}
command -v mkbootimg >/dev/null || {
	echo 'mkbootimg is missing; see scripts/check-build-deps.sh' >&2
	exit 1
}

# The vendor ramdisk ahead of ours is LZ4 legacy; mixed compression across
# ABL's concatenation is the one physically observed way to lose the initrd,
# RAM boot included.
magic=$(head -c4 "$initramfs" | od -An -tx1 | tr -d ' \n')
[ "$magic" = 02214c18 ] || {
	echo "initramfs is not LZ4 legacy (magic $magic); see make-initramfs.sh" >&2
	exit 1
}

# Mirror the stock boot image's OS version and patch level when a stock
# staging exists: some bootloaders compare them against anti-rollback state
# even for a downloaded image, and matching stock can never be the wrong
# answer.  Without a staging the fields stay unset, which unlocked
# bootloaders accept.
version_args=()
if [ -f "$stock/boot.img" ] && command -v unpack_bootimg >/dev/null; then
	header=$(unpack_bootimg --boot_img "$stock/boot.img" --format=info 2>/dev/null || true)
	os_version=$(printf '%s\n' "$header" | sed -n 's/^os version: //p' | head -1)
	os_patch=$(printf '%s\n' "$header" | sed -n 's/^os patch level: //p' | head -1)
	[ -n "$os_version" ] && version_args+=(--os_version "$os_version")
	[ -n "$os_patch" ] && version_args+=(--os_patch_level "$os_patch")
	echo "mirroring stock header: os version '${os_version:-}' patch level '${os_patch:-}'"
else
	echo 'no stock staging; building with unset OS version fields'
fi

mkdir -p "${out%/*}"
rm -f "$out"
mkbootimg \
	--header_version 4 \
	--kernel "$image" \
	--ramdisk "$initramfs" \
	--cmdline '' \
	"${version_args[@]}" \
	-o "$out"

{
	printf 'purpose=RAM boot only; never flash this image\n'
	printf 'kernel_release=%s\n' "${kernel_release:-unknown}"
	printf 'kernel_sha256=%s\n' "$(sha256sum "$image" | cut -d' ' -f1)"
	printf 'initramfs_sha256=%s\n' "$(sha256sum "$initramfs" | cut -d' ' -f1)"
	printf 'image_sha256=%s\n' "$(sha256sum "$out" | cut -d' ' -f1)"
	printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$out.metadata.txt"

stat -c '%n %s bytes' "$out"
cat <<EOF

RAM-boot it (writes nothing; a power cycle fully undoes it):

    adb reboot bootloader        # or Power+VolDown from off
    fastboot boot $out

What to expect on boot #1, in order of ambition:
  1. the panel lights up with a framebuffer console or GDM — jackpot;
  2. no display, but the host sees a new USB device / RNDIS interface —
     the kernel is up, debug over SSH once userdata is flashed;
  3. nothing visible, device falls back to the bootloader after ~10 s —
     the kernel did not start or the handoff refused; recheck the Perpetua
     pin and the fdt-handoff stock-model match for your regional variant;
  4. the device reboots on its own — a panic; if a later boot works,
     /sys/fs/pstore holds the last console.

Never 'fastboot flash' this image: it carries a ramdisk in boot, which is
not the flash layout.  The flashable pair comes from build-boot-bundle.sh.
EOF
