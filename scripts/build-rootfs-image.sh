#!/bin/bash
# Assemble the ext4 root filesystem image that the installer writes into the
# tablet's userdata partition.
#
# Derived from scripts/build-ufs-image.sh of the ubuntu-galaxy-tab-s9-ultra
# port, with the Samsung-specific pieces gone: no DTB lands in /boot (it is
# built into the kernel), and there is no microSD variant (this device has no
# slot).  The invariants are kept:
#
#   * a bare filesystem, not a disk: it goes into a partition that already
#     exists, so nothing on the device ever creates, moves, resizes or
#     deletes a partition and the GPT OnePlus shipped stays exactly as it is;
#   * it ships small and the first boot grows it to the whole partition;
#   * it writes only to a regular file under the build base — never a block
#     device, so it cannot overwrite the build host or the tablet.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
rootfs=${ROOTFS_DIR:-$base/rootfs}
overlay=${OVERLAY_OUT_DIR:-$base/out/rootfs-overlay}
out=${IMAGE_OUT:-$base/out/ubuntu-iceland-userdata.img}
kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
kernel_release=${KERNEL_RELEASE:-$(cat "$kernel_out/kernel.release" 2>/dev/null || true)}
slack_mb=${ROOT_SLACK_MB:-1152}
root_label=${ROOT_LABEL:-UBPAD4_ROOT}
# The whole image travels inside the release ZIP; small is what makes the
# download bearable, and first boot grows the filesystem anyway.
max_mb=${IMAGE_MAX_MB:-8192}

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
test -d "$overlay" || {
	echo "missing rootfs overlay: $overlay" >&2
	echo 'run scripts/build-rootfs-overlay.sh first' >&2
	exit 1
}

case "$out" in
	/dev/*) echo 'refusing to write to a block device' >&2; exit 1 ;;
esac
[ -b "$out" ] && { echo "refusing: $out is a block device" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Ubuntu initramfs — generated here so the image and the boot bundle can never
# carry two different ones.
# ---------------------------------------------------------------------------

initramfs=$(ROOTFS_DIR="$rootfs" KERNEL_OUT_DIR="$kernel_out" \
	KERNEL_RELEASE="$kernel_release" \
	bash "$repo/scripts/make-initramfs.sh")

# ---------------------------------------------------------------------------
# Filesystem geometry
# ---------------------------------------------------------------------------

content_mb=$(( $(du -sm --apparent-size "$rootfs" | cut -f1) \
	+ $(du -sm --apparent-size "$overlay" | cut -f1) ))
image_mb=$(( content_mb + slack_mb ))

echo "image: ${image_mb} MiB (content ${content_mb} MiB, slack ${slack_mb} MiB)"
if [ "$image_mb" -gt "$max_mb" ]; then
	echo "the image is larger than the ${max_mb} MiB budget" >&2
	echo 'raise IMAGE_MAX_MB deliberately, or take content out' >&2
	exit 1
fi

rm -f "$out"
truncate -s "${image_mb}M" "$out"

# The journal stays (unclean power-off without one accumulates damage), and
# errors=remount-ro makes corruption visible instead of compounding.
# -E resize=268435456 (1 TiB in 4 KiB blocks) reserves enough group
# descriptor blocks that first boot's online resize to any iceland userdata
# size (256 GB and 512 GB variants) is a few seconds, not an offline pass.
# -m 1: the percentage survives the resize, and 5% of a grown 200+ GiB
# filesystem is space the owner never gets back.
mkfs.ext4 -q -F -L "$root_label" -e remount-ro -m 1 \
	-E resize=268435456 "$out"

mnt=$base/mnt/userdata
mkdir -p "$mnt"
mount -o loop "$out" "$mnt"
release_mount() {
	sync
	umount "$mnt" 2>/dev/null || true
}
trap release_mount EXIT

echo 'copying the rootfs'
# --xattrs-include='*': GNU tar otherwise drops security.capability in
# silence, and the image ships a ping without cap_net_raw (the gts9u port
# shipped exactly that for months before noticing).
tar -C "$rootfs" --numeric-owner --acls \
	--xattrs --xattrs-include='*' -cf - . \
	| tar -C "$mnt" --numeric-owner --acls \
	--xattrs --xattrs-include='*' -xf -

echo 'merging the firmware overlay'
tar -C "$overlay" --numeric-owner --exclude=PROVENANCE.json -cf - . \
	| tar -C "$mnt" --numeric-owner -xf -
install -m 0644 "$overlay/PROVENANCE.json" "$mnt/usr/lib/iceland-firmware-provenance.json"

# Both tar streams end by applying "./"'s attributes to the extraction root:
# the image's / silently inherits the build tree's owner and mode, and systemd
# treats a non-root-owned / as an unsafe path transition (GNOME then dies on a
# console cursor).  Pin the root inode explicitly; never inherit it.
chown 0:0 "$mnt"
chmod 0755 "$mnt"

# The fstab was written for exactly this label by the rootfs build; verify
# rather than rewrite.
grep -q "LABEL=$root_label[[:space:]]\+/[[:space:]]" "$mnt/etc/fstab" || {
	echo "the rootfs fstab does not mount LABEL=$root_label as /" >&2
	cat "$mnt/etc/fstab" >&2
	exit 1
}

{
	printf 'kernel_release=%s\n' "$kernel_release"
	printf 'root_label=%s\n' "$root_label"
	printf 'install_target=%s\n' 'internal UFS, userdata'
	printf 'kernel_image_sha256=%s\n' \
		"$(sha256sum "$kernel_out/Image" | cut -d' ' -f1)"
	printf 'initramfs_sha256=%s\n' "$(sha256sum "$initramfs" | cut -d' ' -f1)"
	printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$mnt/boot/BUILD-METADATA.txt"

sync
release_mount
trap - EXIT

# A filesystem that is not clean here would be flashed dirty, and the first
# thing the tablet would do with it is fsck it in the dark.
e2fsck -fp "$out" || {
	rc=$?
	[ "$rc" -le 1 ] || { echo "e2fsck rejected the finished image ($rc)" >&2; exit 1; }
}

# Prove the root-inode fix on the finished image; debugfs reads it unmounted.
root_inode=$(debugfs -R 'stat <2>' "$out" 2>/dev/null)
printf '%s' "$root_inode" | grep -q 'User:     0   Group:     0' || {
	echo 'the image root directory is not owned by root:root' >&2
	printf '%s\n' "$root_inode" | head -4 >&2
	exit 1
}
printf '%s' "$root_inode" | grep -q 'Mode:  0755' || {
	echo 'the image root directory is not mode 0755' >&2
	exit 1
}
echo 'root inode: 0:0 mode 0755'

echo '=== image ==='
stat -c '%n %s bytes' "$out"
sha256sum "$out"
