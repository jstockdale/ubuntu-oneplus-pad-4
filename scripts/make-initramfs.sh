#!/bin/bash
# Generate the Ubuntu initramfs inside the built rootfs and check that it is
# the stream the GKI boot chain accepts and that it fits init_boot.
#
# One copy, used by every image builder, exactly as on the gts9u port: an
# initramfs that differed between builds would be the kind of divergence that
# only shows up as a black panel.
#
# It writes only inside the rootfs directory and prints the resulting path on
# stdout.  Nothing is flashed.
set -euo pipefail

base=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
rootfs=${ROOTFS_DIR:-$base/rootfs}
kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
kernel_release=${KERNEL_RELEASE:-$(cat "$kernel_out/kernel.release" 2>/dev/null || true)}
# The budget is the stock init_boot partition size; android-gki enforces the
# hard limit against the real template, this is the early, legible warning.
# 8 MiB is the conventional GKI init_boot size; stage-stock-images.sh's dump
# shows the real one.
init_boot_budget=${INIT_BOOT_BUDGET:-8388608}

test -n "$kernel_release" || {
	echo 'no kernel release; run scripts/build-mainline-kernel.sh first' >&2
	exit 1
}
test -d "$rootfs/etc" || { echo "missing rootfs: $rootfs" >&2; exit 1; }
test -d "$rootfs/usr/lib/modules/$kernel_release" || \
	test -d "$rootfs/lib/modules/$kernel_release" || {
	echo "rootfs has no modules for $kernel_release" >&2
	exit 1
}

# The root-discovery conf.d must be in place before generating: the stock
# cmdline carries no root=, so an initramfs without it boots to a shell.
test -f "$rootfs/etc/initramfs-tools/conf.d/iceland-root" || {
	echo 'missing /etc/initramfs-tools/conf.d/iceland-root in the rootfs;' >&2
	echo 'the ubuntu-iceland-device package was not installed' >&2
	exit 1
}

echo "generating the initramfs for $kernel_release" >&2
mount --bind /dev "$rootfs/dev"
mount -t proc proc "$rootfs/proc"
mount -t sysfs sys "$rootfs/sys"
unmount_pseudo() {
	umount -l "$rootfs/sys" 2>/dev/null || true
	umount -l "$rootfs/proc" 2>/dev/null || true
	umount -l "$rootfs/dev" 2>/dev/null || true
}
trap unmount_pseudo EXIT

chroot "$rootfs" update-initramfs -c -k "$kernel_release" >&2

initramfs=$rootfs/boot/initrd.img-$kernel_release
test -f "$initramfs" || { echo 'update-initramfs produced nothing' >&2; exit 1; }

# LZ4 legacy (magic 02 21 4c 18): ABL concatenates the stock vendor_boot
# fragments (LZ4) with this archive, and mixed compression across the
# concatenation is the one physically observed way to lose the initrd.
magic=$(head -c4 "$initramfs" | od -An -tx1 | tr -d ' \n')
if [ "$magic" != 02214c18 ]; then
	echo "initramfs is not LZ4 legacy (magic $magic); check" >&2
	echo '/etc/initramfs-tools/initramfs.conf COMPRESS=lz4' >&2
	exit 1
fi

size=$(stat -c %s "$initramfs")
echo "initramfs: $size bytes of a $init_boot_budget byte init_boot budget" >&2
if [ "$size" -ge "$init_boot_budget" ]; then
	echo 'the initramfs does not fit init_boot; prune modules (the device' >&2
	echo "package's initramfs hook) or raise INIT_BOOT_BUDGET only if the" >&2
	echo 'real stock partition is actually larger' >&2
	exit 1
fi

printf '%s\n' "$initramfs"
