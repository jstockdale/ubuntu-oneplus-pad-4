#!/bin/bash
# Build the DIAGNOSTIC RAM-boot image for iceland: one `fastboot boot` that
# answers as much as possible while writing nothing to the device.
#
# What it changes against the release artifacts, and why:
#
#   kernel     The release configuration with two deliberate edits in the
#              built-in DTS, reverted from the worktree after the build:
#                - the fdt-handoff match is loosened to compatible-only,
#                  one of "qcom,canoe" / "qcom,canoep".  A bootloader that
#                  skips the dtbo overlay on RAM boots, or patches the model
#                  or bootargs at runtime, fails the strict match silently —
#                  the kernel then boots the Android tree, binds nothing,
#                  and shows exactly a dark panel with dead USB.
#                - panic=0 becomes panic=10, so a post-handoff panic turns
#                  into a visible reboot instead of an indistinguishable
#                  dark hang.
#
#   initramfs  The release archive repacked as a single LZ4-legacy frame.
#              ABL prepends the stock vendor ramdisk, which is LZ4-legacy,
#              and the kernel's LZ4-legacy decoder knows no end-of-stream:
#              after the vendor frame it reads the next four bytes as a
#              chunk size.  Another LZ4 frame's magic is the one value it
#              treats as "a new frame follows" — a plain cpio segment, like
#              the one Ubuntu's initramfs-tools puts first, decodes as a
#              ~0.8 GB chunk and fails the whole unpack before PID 1
#              (lib/decompress_unlz4.c, init/initramfs.c).  On top of the
#              repack, a trailing LZ4 cpio segment overlays the
#              reboot-beacon variant of the usb debug script
#              (scripts/diag/iceland-usb-debug-beacon), so "reached the
#              initramfs but no USB" becomes a visible reboot too.
#
# Outputs, all under $UBUNTU_WORKDIR/out and separate from the release
# artifacts: kernel-iceland-diag/, initrd-diag.img, test-boot-diag.img.
# The rootfs is not touched and needs no root.  RAM boot only — never flash
# any of this.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
kernel_src=${KERNEL_SRC:-$base/linux-perpetua}
kernel_tree=${KERNEL_WORKTREE:-$base/build/linux-src-iceland}
build_dir=${KERNEL_BUILD_DIR:-$base/build/linux-iceland}
rootfs=${ROOTFS_DIR:-$base/rootfs}
release_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
diag_out=$base/out/kernel-iceland-diag
jobs=${KERNEL_JOBS:-$(nproc)}
dts=arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts
beacon=$repo/scripts/diag/iceland-usb-debug-beacon

kernel_release=$(cat "$release_out/kernel.release" 2>/dev/null || true)
initramfs=$rootfs/boot/initrd.img-$kernel_release

test -d "$kernel_tree/.git" -o -f "$kernel_tree/.git" || {
	echo "missing kernel worktree: $kernel_tree (run build-mainline-kernel.sh once)" >&2
	exit 1
}
test -f "$build_dir/.config" || {
	echo "missing configured build dir: $build_dir (run build-mainline-kernel.sh once)" >&2
	exit 1
}
test -f "$initramfs" || { echo "missing initramfs: $initramfs" >&2; exit 1; }
test -f "$beacon" || { echo "missing $beacon" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Diagnostic kernel: edit the worktree DTS, build incrementally, revert
# ---------------------------------------------------------------------------

[ -z "$(git -C "$kernel_tree" status --porcelain)" ] || {
	echo "kernel worktree is not pristine: $kernel_tree" >&2
	echo 'rerun scripts/build-mainline-kernel.sh to reset it' >&2
	exit 1
}
revert_dts() { git -C "$kernel_tree" checkout -- "$dts" 2>/dev/null || true; }
trap revert_dts EXIT

python3 - "$kernel_tree/$dts" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()

old_args = ('bootargs = "rdinit=/rescue/mainline-init panic=0 '
            'loglevel=7 log_buf_len=2M bootconfig";')
# panic=10: a post-handoff panic becomes a visible reboot.
# console=ttyGS0: the serial-gadget console (USB_G_SERIAL + the already-set
# U_SERIAL_CONSOLE) registers at USB probe time, no userspace needed, and
# printk replays its backlog to it — an early panic trace reaches the host
# if the panic falls after dwc3 comes up.
# initcall_debug: names the exact initcall that dies.
# clk_ignore_unused pd_ignore_unused: skip the late-init sweep that gates
# every unclaimed clock and power domain — on a new variant that list can
# include something the secure world or the memory path still needs, and
# the result is a hard reset on a constant ~5 s fuse with no panic path
# (the attempt 4-6 signature: gadget pulls up at T+1 s, dead by T+6 s).
new_args = old_args.replace(
    'panic=0', 'panic=10 console=ttyGS0 initcall_debug '
    'clk_ignore_unused pd_ignore_unused')
assert old_args in text, 'bootargs line drifted; refit the diagnostic edit'
text = text.replace(old_args, new_args)

old_match = ('\t\t\tstock-compatible = "qcom,canoe";\n'
             '\t\t\tstock-model = "Qualcomm Technologies, Inc. '
             'Canoe MTP,iceland-O IN";\n'
             '\t\t\tstock-bootargs = "oplusboot.prjname=25978";\n')
new_match = '\t\t\tstock-compatible = "qcom,canoe", "qcom,canoep";\n'
assert old_match in text, 'fdt-handoff node drifted; refit the diagnostic edit'
text = text.replace(old_match, new_match)

open(path, 'w').write(text)
print('DTS: panic=10, handoff match loosened to compatible-only')
PYEOF

# The legacy g_serial gadget auto-binds the first UDC at initcall time and,
# with U_SERIAL_CONSOLE=y (already set), carries the kernel console the DTS
# edit above points at ttyGS0.  The release build regenerates .config from
# scratch, so flipping it here cannot leak into release kernels.  The
# initramfs debug script tolerates the UDC being taken: its configfs bind
# fails quietly and its kmsg cat lands on the same ttyGS0.
# QCOM_WDT=y: ABL hands over with the APSS watchdog armed, Perpetua carries
# the driver =m, and this initramfs has no modules — unfed, the dog bites a
# few seconds in (the attempt-4/5 hard resets).  Built in, it probes at once
# and WATCHDOG_HANDLE_BOOT_ENABLED keeps it fed.  Also in the release
# fragment; set here too because this build reuses the existing .config.
"$kernel_tree/scripts/config" --file "$build_dir/.config" -e USB_G_SERIAL -e QCOM_WDT
make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" olddefconfig
for sym in CONFIG_USB_G_SERIAL=y CONFIG_QCOM_WDT=y; do
	grep -q "^$sym\$" "$build_dir/.config" || {
		echo "$sym did not take; check its Kconfig dependencies" >&2
		exit 1
	}
done

make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" -j"$jobs" Image

diag_release=$(cat "$build_dir/include/config/kernel.release")
rm -rf -- "$diag_out"
mkdir -p "$diag_out"
install -m 0644 "$build_dir/arch/arm64/boot/Image" "$diag_out/Image"
install -m 0644 "$build_dir/.config" "$diag_out/kernel.config"
printf '%s\n' "$diag_release" > "$diag_out/kernel.release"

revert_dts
[ -z "$(git -C "$kernel_tree" status --porcelain)" ] || {
	echo "worktree still dirty after revert: $kernel_tree" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Diagnostic initramfs: single LZ4 frame + beacon overlay segment
# ---------------------------------------------------------------------------

# Concatenate every segment's raw cpio bytes (decompressing the LZ4 main
# body), exactly preserving entries, then compress the whole as ONE
# LZ4-legacy frame.  Handles both the segmented layout and an already
# repacked single-frame one.
python3 - "$initramfs" <<'PYEOF' | lz4 -l -12 > "$base/out/initrd-diag.base" || exit 1
import subprocess, sys
data = open(sys.argv[1], 'rb').read()
out = sys.stdout.buffer
i = 0
while i < len(data):
    if data[i:i+4] == b'\x02\x21\x4c\x18':
        p = subprocess.run(['lz4', '-dc'], input=data[i:], capture_output=True)
        if p.returncode and not p.stdout:
            sys.exit('LZ4 segment failed to decompress')
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
    sys.exit(f'unknown segment magic at {i}: {data[i:i+4].hex()}')
PYEOF

overlay=$base/build/initrd-diag-overlay
rm -rf -- "$overlay"
mkdir -p "$overlay/scripts/init-top" "$overlay/rescue"
install -m 0755 "$beacon" "$overlay/scripts/init-top/iceland-usb-debug"
# Replaces the packaged rescue/mainline-init SYMLINK with the watchdog
# wrapper (the kernel's cpio unpack unlinks the old entry first).
install -m 0755 "$repo/scripts/diag/mainline-init-wrapper" \
	"$overlay/rescue/mainline-init"
(cd "$overlay" && printf '%s\n' scripts scripts/init-top \
	scripts/init-top/iceland-usb-debug rescue rescue/mainline-init | \
	cpio -o -H newc --owner=0:0 2>/dev/null) | lz4 -l > "$base/out/initrd-diag.overlay"

cat "$base/out/initrd-diag.base" "$base/out/initrd-diag.overlay" \
	> "$base/out/initrd-diag.img"
rm -f "$base/out/initrd-diag.base" "$base/out/initrd-diag.overlay"

# Verify: single chain of LZ4-legacy frames from byte 0, whose decoded
# stream still carries the rescue init and now carries the beacon.
magic=$(head -c4 "$base/out/initrd-diag.img" | od -An -tx1 | tr -d ' \n')
[ "$magic" = "02214c18" ] || {
	echo "diag initramfs does not start with LZ4 legacy (got $magic)" >&2
	exit 1
}
decoded=$(lz4 -dc < "$base/out/initrd-diag.img" 2>/dev/null | strings | \
	grep -c -e 'rescue/mainline-init' -e 'reboot beacon' || true)
[ "$decoded" -ge 2 ] || {
	echo 'diag initramfs decode check failed: rescue init or beacon missing' >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Image, via the same builder as the release smoke test
# ---------------------------------------------------------------------------

KERNEL_OUT_DIR=$diag_out INITRAMFS=$base/out/initrd-diag.img \
	TEST_BOOT_OUT=$base/out/test-boot-diag.img \
	bash "$repo/scripts/make-test-bootimg.sh"

cat <<'EOF'

Diagnostic flight: fastboot boot <out>/test-boot-diag.img, then watch the
clock and the tablet:

  ACM on the host (~5-40 s)   kernel + handoff + initramfs all fine;
                              read the kmsg stream for the panel story
  reboot at ~15-25 s          handoff succeeded, then the kernel panicked
                              (panic=10); unpack or early driver death
  reboot at ~35-50 s          userspace ran but no UDC in 30 s: USB/dwc3
                              never probed
  dark forever                handoff hard-error hang, or match still
                              failing and the Android tree boots nothing

RAM boot only.  Never flash the diagnostic kernel or image.
EOF
