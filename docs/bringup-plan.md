# Bring-up plan: Phase C onward (from 2026-10-31; revised 2026-11-02)

Baseline, 2026-11-02 evening: the tablet boots Ubuntu standalone from
boot_b (kernel #39 = Perpetua 7c98a10e6bb7 + patches 0001–0028, bundle
a4060fbb; qbootctl.service re-marks slot B every boot); device package
ubuntu-iceland-device 0.2.21; zero blacklists, zero failed units. Cold boot
brings up panel + GPU (Adreno 840 / Mesa 26), 10-point touch, Wi-Fi (auto
join), Bluetooth controller, battery telemetry, both consoles (panel fbcon,
serial getty on the gadget), ssh over usb0 and over the air, speakers at
stock loudness behind the protection chain, microphones. C0–C4 are done.
Repository public at github.com/jstockdale/ubuntu-oneplus-pad-4.

Retired this revision: the "DSI PHY probe lottery". Journal census of the
last 20 boots (kernels #36–#39): 20/20 bring up fbcon at 1.9–2.0 s, msm
1.13.0, the GMU firmware and the touchscreen; the 8 "DSI PLL(0) lock
failed" lines and the one "phy driver is not ready" deferral appear on
every boot and are cosmetic. Also retired: the audio-stack boot race (3 of
41 boots with no sound card) — Ubuntu's userspace pd-mapper answering the
ADSP before the kernel's; masked since 0.2.20, 10/10 reboots clean.

Standing rails, unchanged: never set_active / vbmeta / dtbo / vendor_boot /
GPT edits / EDL. One variable per flight. Any kernel change flies as a RAM
boot before it is flashed; a rootfs-only change needs no flight. Restore:
boot_b ← factory/fcap/part-boot_b.img; init_boot_b ← bundle archive; both
sha-verified. Added 2026-11-02: never edit a script while it is running
(bash reads by byte offset); measure the live device tree before adopting a
sibling's SoC-dtsi fix (0029 was a no-op because the board file already
carried it).

## C0–C4 — done (10-31 … 11-02)

C0 infrastructure (NAT, apt, clock, hygiene) · C1 display + GPU firmware +
backlight · C2 touch (0007–0010, coldplug, 30-min soak) · C3 radios
(0003–0006, Wi-Fi auto-join, BT controller) · C4 audio ladder A0–A7
(0011–0028, topology built from Linaro sources, UCM2, PipeWire protection
chain, mics via 0028). Evidence per item in hardware-status.md and the
porting log. Carried opens from these phases: BT pairing + per-unit address,
wired headphones (UCM device + headset test), pen capabilities, stylus
props, the filed one-shots (T+60 USB bounce, early console loss, depmod
modules.builtin.modinfo).

## VP — Video decode/encode (iris VPU): one kernel flight, before/with C5

Verified 2026-11-02: the pinned tree has the full iris driver with the
VPU4x generation but no kaanapali compatible; the DT prerequisites (video
reserved memory, videocc with its five GDSCs, GCC AXI clocks, interconnect
and rpmhpd OPP labels, IRQ 174, SMMU SIDs 0x1940/0x1943/0x1944/0x1a20) are
all present and unused; kernel config already builds iris, V4L2 mem2mem,
videobuf2, MDT loader, PAS, UBWC as modules/built-in; vpu40_2v.mbn
(sha256 69d4e215…) is on the tablet, in the overlay and in the manifest;
Perpetua's head (b7d639cf, 100 commits past the pin) has no iris work, so
the series is carried locally. v4l-utils is installed; GStreamer is not.

- VP0 import — done 2026-11-02: 0029 platform data (Qualcomm via
  infiniti 0033), 0030 kaanapali.dtsi iris node (0035), 0031 our board
  enable (firmware-name vpu40_2v.mbn, status okay), 0032–0035 the
  VPU4x buffer-size fixes (0032/0034/0037/0038), 0036 bus_info prefix.
  Whole series apply-checked in order on a scratch worktree. Build gate:
  `modinfo qcom-iris.ko.zst` shows two qcom,kaanapali-iris aliases;
  `dtc -I dtb -O dts iceland.dtb | grep -A3 video-codec@2000000` shows
  status okay and the firmware-name.
- VP1 RAM-boot first light (one variable: iris support on the otherwise
  identical #39 bundle). PASS: qcom-iris probes, dmesg shows vpu40_2v.mbn
  loaded with no PAS/firmware error, no arm-smmu context fault with
  cbfrsynra 0x1940/0x1943/0x1944/0x1a20 (0x800 at 0.25 s is baseline),
  /dev/video0 and /dev/video1 exist, `v4l2-ctl -d /dev/video0
  --list-formats-out` lists H264/HEVC/VP9/AV1. FAIL = any PAS error, a
  0x19xx/0x1a20 fault or a defer loop: stop, capture dmesg, power-cycle
  back to flashed #39, do not iterate blind.
- VP2 decode proof (rootfs-only): apt install gstreamer1.0-tools
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad; test clips (1080p
  H.264 + VP9, generated on the host); `gst-launch-1.0 filesrc ! qtdemux
  ! h264parse ! v4l2h264dec ! filesink`, checksum identical twice, then
  on-screen under Weston with low CPU. Then flash the VP bundle.
- VP3 encode proof: v4l2h264enc; GNOME screen recording once C5 is up.
- VP4 hardening, next bundle: iceland 0157–0160, 0246–0250, 0292 and
  infiniti 0069–0071 (all in /srv/ubuntu-iceland/ref/iceland-linux);
  firmware-manifest.md gets a VPU row with the sha.
- VP5 VA-API (iris-vaapi) deferred to the desktop phase.

## C5 — Desktop: GNOME on Wayland (rootfs-only; no flight)

Prerequisites verified 2026-11-02: panel reliable (20/20), touch classified
for libinput (ID_INPUT_TOUCHSCREEN, INPUT_PROP_DIRECT, pen as
ID_INPUT_TABLET), GLES via freedreno proven (Vulkan/turnip has no a840 —
not needed by mutter), chassis "tablet" in the DT, PipeWire complete.
No panel orientation transform is needed (no DT rotation, landscape-native
3392×2400, touch already swapped/inverted in the DT); what remains is the
visual tap-to-pixel check and integer scaling (the tb323fu port saw mutter
pick 2.2857× with fractional scaling and then refuse display changes; the
274×193 mm panel at ~315 DPI should land at 2×).

1. Gate 0 — guards, shipped in 0.2.21 (done 2026-11-02): fwupd and
   fwupd-signed pinned to -1 (its scsi plugin can write UFS firmware and
   this tablet has no recovery loader; ubuntu-desktop-minimal pulls both
   through Recommends), fwupd units and the sleep/suspend/hibernate/
   hybrid-sleep targets masked, logind HandlePowerKey=ignore +
   HandlePowerKeyLongPress=poweroff, dconf system db and GDM greeter
   drop-in with no idle suspend, power-button-action interactive, mutter
   experimental-features empty. PASS (measured): `apt-get -s install
   ubuntu-desktop-minimal` lists 844 packages and 0 fwupd;
   suspend.target masked; logind shows the two keys.
2. Gate 1 — touch-plan T2, panel blank/unblank ×3 on kernel #39 (done
   2026-11-02): backlight followed the panel each cycle, no kernel
   messages, both touch devices still registered. Tap confirmation after
   the cycles owed from the owner (IRQ 254 msmgpio counter must advance).
3. Flight — `sudo apt install ubuntu-desktop-minimal` in tmux over usb0
   (844 packages, ~531 MB, 1.8 GB); GDM starts on install. PASS: greeter
   on glass at 3392×2400, `loginctl` session Type=wayland, `journalctl -b
   -u gdm3` clean, touch login as ubuntu with the on-screen keyboard,
   gnome-shell is DRM master, taps land under the finger at four corners,
   Settings shows 2× (integer) scale, `pgrep fwupd` empty, no "Suspending"
   in the journal after 25 min idle, a short power press shows GNOME's
   dialog and does not power off. Any failure stays recoverable over
   usb0/serial: `systemctl disable gdm3` or `apt purge gdm3 gnome-shell`.
   Note: the dev rootfs gives a password login for ubuntu, not the
   first-boot wizard (that path is the clean-image build only).
4. Fold the guards into build-ubuntu-rootfs.sh's desktop profile and
   build one clean image (installer writes userdata only; boot_b
   untouched); plymouth and gnome-remote-desktop come with the metapackage
   and are untested on this boot path.
5. Soak a day tethered; watch /sys/class/thermal under stress-ng +
   glmark2. No thermal policy daemon exists yet; Perpetua 8bd03159587a
   (kaanapali CPU passive cooling) is a next-pin-bump candidate.

Gate: daily-drivable desktop, no tether.

## S — Sensors / IMU (host work first; S6 needs C5)

Route A (sensors-plan.md): the ADSP sensor hub over FastRPC + QRTR,
hexagonrpcd serving the per-unit DSP tree, libssc, iio-sensor-proxy 3.9
with SSC support, GNOME auto-rotation. Verified 2026-11-02: kernel side is
already complete on #39 (fastrpc, qrtr, qcom_pd_mapper loaded; the
kernel mapper advertises msm/adsp/sensor_pd; the SSC QMI service 400 is
already on QRTR); the only kernel gap is the non-secure fastrpc node
(Fedora 0061), and all DSP-tree inputs exist on the host (factory persist
registry, 352 entries; stock dsp/adsp libs; ODM and vendor sensor
configs). Nothing of the userspace stack exists in Ubuntu 26.04: libssc is
absent, iio-sensor-proxy 3.8 lacks the SSC backend, hexagonrpcd 0.4.0
predates the needed fixes.

- S1 host (no tablet, ~1 day): arm64 mmdebstrap build chroot;
  scripts/make-dsp-tree.sh (registry 0600, never published; socinfo from
  Fedora's generic set — hw_platform=MTP, three values still to fetch);
  three debs: hexagonrpc from Debian experimental 0.5.0-1 moved to
  598b591 + Fedora patches 0001/0002, libssc 0.4.4-2 backport,
  iio-sensor-proxy 3.9-1 with ssc. Fedora's patch files are now local
  under /srv/ubuntu-iceland/ref/.
- S2 first attach, zero kernel change: fresh reboot, within 2 min run
  hexagonrpcd on /dev/fastrpc-adsp-secure; PASS = attach + a stream of hub
  file requests, ADSP stays up, battery telemetry alive, daemon still
  serving at 5 min. FAIL-A (ioctl rejected) → S3; FAIL-B (no requests) →
  retry with an earlier start, then record.
- S3 DT flight: qcom,non-secure-domain on the ADSP fastrpc node (RAM boot).
- S4 ssccli per sensor · S5 iio-sensor-proxy + udev rule with the mount
  matrix (verify against our panel orientation on glass) · S6 GNOME
  auto-rotation + 20-min soak · S7 ship · H1 hall/lid (Fedora 0030),
  independent.

## A — Audio, Bluetooth, pen, thermal polish (rootfs-first; one kernel rung)

Verified 2026-11-02 (remaining-audio reader): the wired-headphone "plays
four periods then EIO" is not a bug — with no jack detected the common
machine driver keeps the HPH DAPM endpoint off, the codec-DMA sink stops
consuming and aplay starves. The Pad 4 has no 3.5 mm jack: the path needs
a USB-C analog headset or adapter (MBHC + the WCD939x Type-C mux, both
bound and in the pin; Fedora 0186–0192 are already in Perpetua). Bluetooth
is up on BRAHMA 2.0.1 firmware but broadcasts the Perpetua board file's
placeholder address AD:5A:00:00:00:25 (as every Pad 4 on Perpetua does);
this unit's persist has no bluetooth directory, so Fedora's provisioning
sources do not exist here; the WLAN MAC is likewise the firmware default
00:03:7f:12:34:56. Mic noise floor at parity (−61.4/−60.7 dBFS median vs
−64); 0059 is complete (ADPT_CTRL written). Thermal: kernel CPU/GPU loops
exist (90 °C passive, step_wise); no NTC/skin zones in our DT, so the
decoded shell model cannot run yet.

1. BT/WLAN identity (rootfs-only, 0.2.22): /etc/iceland/bdaddr + an
   iceland-bdaddr.service (btmgmt power on → off → public-addr, retried,
   re-run by udev on hci0 add; Fedora's v3 ordering) and the same for the
   WLAN MAC. Owner decision: factory values (read from stock Android:
   persist.vendor.service.bdroid.bdaddr) or a stable per-unit derivation
   from /sys/devices/soc0/serial_number (phonewave's method) — derivation
   recommended unless the factory values are already known. PASS: the new
   address survives a reboot and a power cycle of the controller.
2. BT audio: apt install libspa-0.2-bluetooth; pair a keyboard or headset
   (none recorded as owned). PASS: pairing persists across a reboot; an
   A2DP sink appears in `wpctl status`.
3. Pen (next kernel bundle after VP): adapted Fedora 0036 (BTN_STYLUS/2,
   axis resolution from touchscreen-x-mm/y-mm; hunk 5 must be rewritten
   for our probe) + 0037 (mm values in the controller frame) + a one-hunk
   fix so the pen goes through touchscreen_report_pos like touch (its
   coordinates are raw today). Evdev gate first; libinput under C5.
4. Thermal baseline during the C5 soak (tb323fu's thermal-stress pattern:
   600 s all-core + glmark2; CPU zones held under 95 °C, no critical
   trip). The ADC/NTC zones (Perpetua cf2156997bf7, 573a270f7b90 +
   CONFIG_QCOM_SPMI_ADC5_GEN3; Fedora 0056/0190 skin/XO/USB-C) come with
   the pin bump; only then the userspace model (iceland-thermal,
   GPL-2.0-or-later, with its decoded-model provenance question).
5. Headphones once a USB-C analog headset exists: first gate is
   SW_HEADPHONE_INSERT=1 and an MBHC plug line on insertion; then a
   Headphones UCM device from the wcd939x sequences alsa-ucm-conf already
   ships; if detection never fires, obtain Fedora's q90w2 headset fixes.

## C6 — Hardening / dailyability (after C5)

Verified 2026-11-02 (suspend reader): the tablet has never suspended
(suspend_stats 0/0). /sys/power/mem_sleep is "s2idle [deep]" — a plain
`systemctl suspend` today would attempt PSCI deep, which this SoC does not
support (hence the masked sleep targets since 0.2.21). Two deterministic
hazards are in the live tree: (1) PCIe WAKE# is armed as a dedicated
level-high wake IRQ (IRQ 256, GPIO 104 pulled up) → instant wake, Fedora's
symptom; disarmable at runtime with `power/wakeup=disabled` on
0000:00:00.0, permanently by dropping wake-gpios as Fedora's final DT does;
(2) the pin lacks Perpetua ebe4aed7e940 (2026-10-29, one day after our
pin): PCIe/USB GDSCs PWRSTS_OFF_ON → RET_ON, "on resume gcc_pcie_0_gdsc
stays stuck off and the phone resets" — must precede any flashed suspend.
The serial console is the USB gadget, which dwc3 device-mode suspend
disconnects, so the witnesses are the panel, the host's USB log and the
post-hoc suspend_stats/journal. No MCQ on our UFS DT (single reg, no
msi-parent), so the "MCQ suspend fix" does not apply. CONFIG_PM_DEBUG is
unset (no pm_wakeup_irq); Perpetua added it for aston on 2026-11-03.

- S0 once, before any flight: drill and record the hard-reset gesture on
  the idle, synced tablet (runbook says power+vol-up; the media plan says
  power ≥10 s; only Vol-Down+Power ~15 s → fastboot is verified).
- F1 baseline on flashed #39, nothing built: battery ≥40 %, tethered,
  host `journalctl -k -f`; on the tablet `nmcli radio wifi off`, `echo
  disabled > /sys/bus/pci/devices/0000:00:00.0/power/wakeup`, snapshot
  wakeup_sources + /proc/interrupts + suspend_stats, then `systemd-run
  --unit=s2idle-f1 rtcwake -m freeze -s 30` (freeze = s2idle, bypasses
  the deep default; the unit survives the gadget drop). Do not press the
  power key during the window. PASS: suspend_stats success 0→1, fail 0;
  "PM: suspend entry (s2idle)"/"suspend exit" ≥25 s apart; panel, gadget
  and ssh back within 60 s. FAIL (a) wakes in <5 s → diff wakeup_sources
  → disable that source → F1b; (b) sleeps then resets → GDSC hazard
  confirmed → F2 = RAM boot with ebe4aed7e940 + CONFIG_PM_DEBUG=y; (c)
  never wakes → power press, else the drilled reset → fastboot → boot_b.
- Then the DT pair (drop wake-gpios; USB wakeup-source) as our own
  patches, CONFIG_HOTPLUG_PCI_PCIE=y (Perpetua's route for the root port
  to reach D3, 78b1d23d88bc) and the Wi-Fi-up rung; flash after the
  RAM-boot gate. Policy last, rootfs-only: tmpfiles mem_sleep=s2idle,
  sleep.conf.d MemorySleepMode=s2idle, logind HandlePowerKey=suspend,
  unmask the sleep targets, GNOME timers back on.
- Drain (S3) is unreachable on the pin: the single-cluster CPU PM domain
  makes the firmware deny system power-down; d68240c6e4bb (two clusters
  + rpmh-stats node) is pin-bump material, with cf7e4df5e479 (UFS lane
  clocks → CXO shutdown).
- The filed one-shots: T+60 USB bounce, early console loss, battmgr uevent
  EAGAIN, depmod modules.builtin.modinfo, on-device update-initramfs
  writing an unused /boot initrd.
- Kernel pin bump (one flight, after VP and C5): past 9ba37ef1db70 (drop
  0028's READ_DONE hunk); suspend block ebe4aed7e940, d68240c6e4bb,
  78b1d23d88bc, cf7e4df5e479, 8b2990f9ae9f; thermal/ADC cf2156997bf7,
  573a270f7b90, b4ab5eb72d15 (+CONFIG_QCOM_SPMI_ADC5_GEN3=m) — note
  8bd03159587a only relocates iceland's existing 90 °C trips; battmgr
  006b67a31bae (9 V PD); ath12k 476ac2f9e476 (inert without
  qcom,drv-supported); the dpu/dp DisplayPort fixes; re-diff 0011–0024 and
  0029–0036 if they move.
- Upstreaming: docs/upstreaming.md (WRITE_DONE consistency patch, our
  0002/0004–0007/0010/0031, the license request to the Fedora port).

## Phase D — Waydroid (after C5 stable)

Binder/ashmem config audit in the Perpetua tree, Waydroid image,
shared-kernel Android apps. Scoped when C5 lands.

## Master test order (one line each)

C0: NAT → apt → clock → hygiene.                        [done 10-31]
C1: display census (20/20) → weston → GPU fw → backlight. [done 10-31]
C2: touch modprobe-with-panel → soak → coldplug → unblacklist. [done 11-01]
C3: pwrseq → ath12k → BT (pairing still owed).           [done 11-01]
C4: audio PD → topology/UCM → amps → mics → chain → stock ceiling → race. [done 11-02]
VP: import (done) → build gate → RAM-boot first light → decode → flash → encode → hardening.
C5: guards (done) → T2 (done) → apt desktop → GDM on glass → taps/scale/power key → soak → clean image.
S:  host debs + DSP tree → secure-node attach → (DT flight) → ssccli → iio-sensor-proxy → GNOME rotate → ship.
A:  BT/WLAN identity (0.2.22) → BT audio + pairing → pen patches (next bundle) → thermal census → headphones (needs a USB-C headset).
C6: S0 reset drill → F1 s2idle baseline on #39 → GDSC + PM_DEBUG RAM boot → DT pair + pciehp → Wi-Fi-up → policy → pin bump → one-shots → upstreaming.
D:  Waydroid.
