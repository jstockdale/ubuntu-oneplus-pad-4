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

# Recreate the worktree at the pinned commit and apply the RELEASE
# patches, exactly as build-mainline-kernel.sh does — the diag edits go
# on top, so the diag kernel always carries the release fixes too.
commit=$(git -C "$kernel_src" rev-parse HEAD)
if [ -d "$kernel_tree" ]; then
	git -C "$kernel_src" worktree remove --force "$kernel_tree" 2>/dev/null || \
		rm -rf -- "$kernel_tree"
fi
git -C "$kernel_src" worktree prune
git -C "$kernel_src" worktree add --detach "$kernel_tree" "$commit"
shopt -s nullglob
for patch in "$repo"/kernel/patches/*.patch; do
	echo "applying ${patch##*/}"
	git -C "$kernel_tree" apply --index "$patch" || {
		echo "${patch##*/} no longer applies" >&2
		exit 1
	}
done
shopt -u nullglob
revert_dts() { git -C "$kernel_tree" checkout -- "$dts" 2>/dev/null || true; }
trap revert_dts EXIT

python3 - "$kernel_tree/$dts" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()

old_args = ('bootargs = "rdinit=/rescue/mainline-init '
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
# console=tty0 FIRST: with the splash framebuffer node below and
# DRM_SIMPLEDRM, the kernel log is readable ON THE PANEL inside the
# 5-second death window; ttyGS0 stays last so the rescue shell lands on
# USB when the boot survives.
# The initcall_blacklist + fw_devlink=off set is the tb323fu port's
# SM8850 bring-up survival kit: genpd/regulator/interconnect sync_state
# and the clk sweep all power off "unclaimed" boot state, several of
# them whatever pd_ignore_unused says, and the live splash scanout (and
# whatever else ABL left running) dies with it.
new_args = old_args.replace(
    'loglevel=7', 'console=tty0 console=ttyGS0 initcall_debug '
    'clk_ignore_unused pd_ignore_unused '
    'initcall_blacklist=clk_disable_unused,genpd_power_off_unused,'
    'regulator_init_complete,of_platform_sync_state_init fw_devlink=off '
    'arm-smmu.disable_bypass=0 modprobe.blacklist=fastrpc,hci_uart,i2c_qcom_cci,ipa,leds_qcom_flash,leds_qcom_lpg,nt36536_ts,pci_pwrctrl_pwrseq,phy_qcom_mipi_csi2,pinctrl_sm8650_lpass_lpi,pwrseq_qcom_wcn,q6apm_dai,q6apm_lpass_dais,q6prm,q6prm_clocks,qcom_camss,qcom_q6v5_pas,qcom_rng,snd_q6apm,snd_soc_lpass_rx_macro,snd_soc_lpass_tx_macro,snd_soc_lpass_va_macro,snd_soc_lpass_wsa_macro,snd_soc_sc8280xp,snd_soc_tfa9865,snd_soc_wcd939x,soundwire_qcom,spi_geni_qcom,ath12k,btqca loglevel=7')

# ABL's live splash as a framebuffer console (the Fedora port's measured
# recipe: MDP at 650 MHz needs MMCX TURBO, dispcc is fed by MX/MXC, and
# dispcc's sync_state drops the INT2 GDSC whatever pd_ignore_unused says;
# DSI byte/pixel clocks deliberately omitted — their parents are PHY PLLs
# unknown until the PHYs probe).
# dtc demands properties before subnodes: the cell/ranges properties go
# right after "chosen {", and the framebuffer subnode is inserted just
# ahead of the fdt-handoff subnode (anchored on its comment line).
props = ('\tchosen {\n\t\t#address-cells = <2>;\n'
         '\t\t#size-cells = <2>;\n\t\tranges;\n')
assert '\tchosen {\n' in text, 'chosen block drifted'
text = text.replace('\tchosen {\n', props, 1)

anchor = ('\t\t/* The bootloader ramdisk carries the rescue and boot '
          'userspace. */\n')
assert anchor in text, 'fdt-handoff comment anchor drifted'
fb_node = '''
		framebuffer@fc800000 {
			compatible = "simple-framebuffer";
			reg = <0x0 0xfc800000 0x0 0x2b00000>;
			width = <3392>;
			height = <2400>;
			stride = <(3392 * 4)>;
			format = "a8r8g8b8";
			clocks = <&gcc GCC_DISP_HF_AXI_CLK>,
				 <&dispcc DISP_CC_MDSS_AHB_CLK>,
				 <&dispcc DISP_CC_MDSS_MDP_CLK>,
				 <&dispcc DISP_CC_MDSS_MDP_LUT_CLK>,
				 <&dispcc DISP_CC_MDSS_VSYNC_CLK>,
				 <&dispcc DISP_CC_MDSS_ESC0_CLK>,
				 <&dispcc DISP_CC_MDSS_ESC1_CLK>;
			power-domains = <&rpmhpd RPMHPD_MMCX>,
					<&rpmhpd RPMHPD_MX>,
					<&rpmhpd RPMHPD_MXC>,
					<&dispcc DISP_CC_MDSS_CORE_GDSC>,
					<&dispcc DISP_CC_MDSS_CORE_INT2_GDSC>;
			required-opps = <&rpmhpd_opp_turbo>,
					<&rpmhpd_opp_turbo>,
					<&rpmhpd_opp_turbo>;
			memory-region = <&cont_splash_mem>;
		};

'''
text = text.replace(anchor, fb_node + anchor, 1)

splash_mem = '''	reserved-memory {
		cont_splash_mem: splash-region@fc800000 {
			reg = <0x0 0xfc800000 0x0 0x2b00000>;
			no-map;
		};

'''
assert '\treserved-memory {\n' in text, 'reserved-memory block drifted'
text = text.replace('\treserved-memory {\n', splash_mem, 1)
print('DTS: splash framebuffer console node added')

# The apps SMMU's live display mappings are hypervisor-managed and
# invisible to the read-back ('reserved 0 boot mappings'), so any probe
# resets them out from under the scanning splash — and bypass does not
# help, because the mappings translate. The diag kernel leaves that SMMU
# alone entirely; consumers fall back to direct DMA.
text += '\n&apps_smmu {\n\tstatus = "disabled";\n};\n'
print('DTS: apps_smmu disabled for the diag')

# v17: the NT36536 TDDI touch driver probes against a panel that never
# comes (display driver off in the diag), retrying exactly where every
# post-boot death lands; disable it for the single-variable test.
text += '\n&spi19 {\n\tstatus = "disabled";\n};\n'
print('DTS: spi19/touch disabled for the diag')
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
# DRM_SIMPLEDRM drives the splash framebuffer node; DRM_MSM is DISABLED in
# the diag build so nothing resets ABL's live scanout (the Fedora port
# needed two driver patches to keep the splash through a dpu probe — the
# diagnostic sidesteps that entirely).
"$kernel_tree/scripts/config" --file "$build_dir/.config" \
	-e USB_G_SERIAL -e QCOM_WDT -e DRM_SIMPLEDRM -d DRM_MSM
make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" olddefconfig
for sym in CONFIG_USB_G_SERIAL=y CONFIG_QCOM_WDT=y CONFIG_DRM_SIMPLEDRM=y; do
	grep -q "^$sym\$" "$build_dir/.config" || {
		echo "$sym did not take; check its Kconfig dependencies" >&2
		exit 1
	}
done
if grep -q '^CONFIG_DRM_MSM=y' "$build_dir/.config"; then
	echo 'CONFIG_DRM_MSM is still enabled; the splash console would die' >&2
	exit 1
fi

make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" -j"$jobs" Image

diag_release=$(cat "$build_dir/include/config/kernel.release")
rm -rf -- "$diag_out"
mkdir -p "$diag_out"
install -m 0644 "$build_dir/arch/arm64/boot/Image" "$diag_out/Image"
install -m 0644 "$build_dir/.config" "$diag_out/kernel.config"
printf '%s\n' "$diag_release" > "$diag_out/kernel.release"

revert_dts
# After reverting the diag DTS edits the worktree holds exactly the
# applied release patches (staged); unstaged changes mean a bad revert.
[ -z "$(git -C "$kernel_tree" diff --name-only)" ] || {
	echo "worktree has unstaged changes after revert: $kernel_tree" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Diagnostic initramfs: single LZ4 frame + beacon overlay segment
# ---------------------------------------------------------------------------

# Repack via the shared helper: single LZ4-legacy frame AND the lib/
# directory fix (the vendor ramdisk owns a non-empty real lib/, so our
# usr-merge lib symlink silently loses and every dynamic exec dies with
# ENOENT on the loader — bisected to the vendor's lib/modules entry).
python3 -I "$repo/scripts/repack-initramfs.py" "$initramfs" "$base/out/initrd-diag.base"

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
