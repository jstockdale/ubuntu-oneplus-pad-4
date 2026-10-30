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

base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
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

# Repack as a single LZ4-legacy frame.  Ubuntu 26.04's initramfs-tools emits
# a SEGMENTED archive: plain cpio segment(s) first, then the compressed main
# body.  On its own the kernel unpacks that fine — but ABL prepends the stock
# vendor_boot ramdisk, which is LZ4-legacy, and the kernel's LZ4-legacy
# decoder has no end-of-stream marker: after the vendor frame it reads the
# next four bytes as a chunk size.  Another LZ4 frame's magic is the one
# value it takes as "a new frame follows"; a plain cpio segment decodes as an
# absurd chunk length and fails the WHOLE unpack before PID 1
# (lib/decompress_unlz4.c, init/initramfs.c) — observed as a dark panel with
# dead USB on RAM-boot attempts 1-3.  So: concatenate every segment's raw
# cpio bytes, decompressing the main body, and compress the whole as one
# LZ4-legacy frame.  Entry bytes are preserved exactly, and the kernel parses
# the decoded stream as successive cpio archives — the same way it parses
# stock Android's vendor+generic ramdisk pair.
python3 - "$initramfs" <<'PYEOF' | lz4 -l -12 > "$initramfs.single"
import subprocess, sys
data = open(sys.argv[1], 'rb').read()
out = sys.stdout.buffer
i = 0
while i < len(data):
    magic4 = data[i:i+4]
    if magic4 == b'\x02\x21\x4c\x18':
        p = subprocess.run(['lz4', '-dc'], input=data[i:], capture_output=True)
        if not p.stdout:
            sys.exit('the LZ4 main body failed to decompress')
        out.write(p.stdout)
        break
    if data[i:i+6] in (b'070701', b'070702'):
        j = i
        while j < len(data):
            hdr = data[j:j+110]
            if hdr[:6] not in (b'070701', b'070702'):
                break
            namesize = int(hdr[94:102], 16)
            filesize = int(hdr[54:62], 16)
            name = data[j+110:j+110+namesize-1].decode(errors='replace')
            j = (j + 110 + namesize + 3) // 4 * 4
            j = (j + filesize + 3) // 4 * 4
            if name == 'TRAILER!!!':
                break
        while j < len(data) and data[j:j+1] == b'\x00':
            j += 1
        out.write(data[i:j])
        i = j
        continue
    sys.exit(f'segment at offset {i} is neither plain cpio nor LZ4 legacy '
             f'(magic {magic4.hex()}): check COMPRESS=lz4 in '
             '/etc/initramfs-tools/initramfs.conf')
PYEOF
mv -- "$initramfs.single" "$initramfs"

# Verify the invariant the boot chain actually needs: LZ4 legacy from byte 0
# (nothing but LZ4 may follow the vendor frame), decodable, with
# rescue/mainline-init — the name the kernel's built-in bootargs exec —
# present in the decoded stream.
verify=$(python3 - "$initramfs" <<'PYEOF'
import subprocess, sys
data = open(sys.argv[1], 'rb').read()
if data[:4] != b'\x02\x21\x4c\x18':
    sys.exit(f'not a single LZ4-legacy frame (magic {data[:4].hex()}); '
             'the repack failed')
p = subprocess.run(['lz4', '-dc'], input=data, capture_output=True)
raw = p.stdout
if not raw:
    sys.exit('the repacked initramfs failed to decompress')
i, names = 0, set()
while i < len(raw):
    hdr = raw[i:i+110]
    if hdr[:6] not in (b'070701', b'070702'):
        if raw[i:].strip(b'\x00'):
            sys.exit(f'junk at decoded offset {i}: not cpio')
        break
    namesize = int(hdr[94:102], 16)
    filesize = int(hdr[54:62], 16)
    name = raw[i+110:i+110+namesize-1].decode(errors='replace')
    i = (i + 110 + namesize + 3) // 4 * 4
    i = (i + filesize + 3) // 4 * 4
    if name != 'TRAILER!!!':
        names.add(name)
    while i < len(raw) and raw[i:i+1] == b'\x00':
        i += 1
print(f'single LZ4-legacy frame, {len(names)} entries decoded')
if 'rescue/mainline-init' not in names:
    sys.exit('the initramfs lacks rescue/mainline-init; the '
             'iceland-rescue-init hook from ubuntu-iceland-device did not '
             'run — is the package installed and the hook executable?')
print('rescue/mainline-init: present')
PYEOF
) || { printf '%s\n' "$verify" >&2; exit 1; }
printf '%s\n' "$verify" >&2

size=$(stat -c %s "$initramfs")
echo "initramfs: $size bytes of a $init_boot_budget byte init_boot budget" >&2
if [ "$size" -ge "$init_boot_budget" ]; then
	echo 'the initramfs does not fit init_boot; prune modules (the device' >&2
	echo "package's initramfs hook) or raise INIT_BOOT_BUDGET only if the" >&2
	echo 'real stock partition is actually larger' >&2
	exit 1
fi

printf '%s\n' "$initramfs"
