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
the series is carried locally. v4l-utils, gstreamer1.0-tools/-base/-good/
-bad and three 1080p test clips (~/clips: H.264, HEVC, VP9) are on the
tablet since 2026-11-02.

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
  back to flashed #39, do not iterate blind. Module staging rule: the
  build's `rm -rf out/kernel-iceland` discards the host copy of #39's
  modules, so back up the tablet's /lib/modules/7.3.0+ first (done
  2026-11-02, backups/tablet-modules-7.3.0+-kernel39-*.tar.gz), then push
  only the modules whose hash differs (expected: qcom-iris only) and
  depmod; no reboot or RAM boot while dpkg is configuring.
- VP2 decode proof (rootfs-only; tools and clips already staged):
  `gst-launch-1.0 filesrc ! qtdemux ! h264parse ! v4l2h264dec ! filesink`,
  checksum identical twice, then on-screen under the compositor with low
  CPU. Then flash the VP bundle.
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
3. Flight — `apt install ubuntu-desktop-minimal` as a transient systemd
   unit (`systemd-run --unit=iceland-desktop-install …`; tmux is not on
   the dev rootfs, and a unit survives an ssh or usb0 drop) — started
   2026-11-02 evening, 844 packages. After dpkg is idle: `dpkg --audit`
   clean, `dconf update` (the minimal rootfs had no dconf binary, so the
   0.2.21 system db compiles only now) and `ls /etc/dconf/db/local`.
   PASS: greeter
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
predates the needed fixes. The owner's auto-rotation report (2026-11-02,
evening) is this gap and nothing else: GNOME's orientation lock is off,
there are 0 IIO devices, the iio-sensor-proxy 3.8-1 the desktop task
pulled in exports nothing (no SensorProxy on the system bus — it exits
when it finds no sensor), hexagonrpcd is absent, and the hub is alive
(SSC on QRTR). Rotation follows S5/S6, with the mount matrix checked on
glass in all four orientations.

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
00:03:7f:12:34:56 (both replaced since — A.1). Mic noise floor at parity (−61.4/−60.7 dBFS median vs
−64); 0059 is complete (ADPT_CTRL written). Thermal: kernel CPU/GPU loops
exist (90 °C passive, step_wise); no NTC/skin zones in our DT, so the
decoded shell model cannot run yet.

1. BT/WLAN identity — mechanism shipped as 0.2.24 (2026-11-02), values
   device-local: /etc/iceland/wlan-mac holds the Wi-Fi MAC from the
   DEVICE LABEL (the owner has it) and /etc/iceland/bdaddr the stock
   Bluetooth address, which turned up on 2026-11-02 in the factory
   capture's log store (a modem NV read the stock OS logged; persist has
   no bluetooth dir, devinfo is empty and the NV stores are OPLUS
   "OEM~~OEM" blobs, so it was a log line, not a provisioning file; it
   sits next to the Wi-Fi MAC as Qualcomm units are provisioned). When a
   file is absent it is generated once from /etc/machine-id (random per
   install) with the locally-administered bit — never from the SoC
   serial: a public recipe over an 8-hex-digit serial would let anyone
   recover the serial from the MAC in 2^32 guesses. Applied by
   iceland-radio-ids.service (files + a systemd .link for ath12k_pci,
   before NetworkManager) and iceland-bdaddr.service (Fedora's proven
   power on → off → Set Public Address, retried; re-run by udev on hci0
   add). The addresses never enter the repo or the logs. PASS: both
   addresses survive a reboot and a controller power cycle;
   /var/lib/bluetooth gains one dir for the real address; the router sees
   the label MAC.
2. BT audio: apt install libspa-0.2-bluetooth; pair a keyboard or headset
   (none recorded as owned). PASS: pairing persists across a reboot; an
   A2DP sink appears in `wpctl status`.
3. Stylus (OnePlus Stylo Pro) — input, next kernel bundle after VP:
   today the NT36536 driver already reports the pen's position, pressure,
   tilt and hover (ABS_PRESSURE/TILT_X/TILT_Y/DISTANCE, BTN_TOOL_PEN) and
   the firmware decodes the two barrel buttons and a battery byte that the
   driver parses and drops; libinput ignores the device ("missing tablet
   capabilities: btn-stylus resolution", seen in the first GNOME session
   on 2026-11-02). Patches: 0037 = adapted Fedora 0036 (declare and report
   BTN_STYLUS/BTN_STYLUS2, axis resolution from touchscreen-x-mm/y-mm via
   the controller's abs_x_max/abs_y_max; its hunk 5 rewritten for our
   touchscreen_parse_properties-based probe), 0038 = the DT mm properties
   in OUR controller frame (touchscreen-size-x 24000 / size-y 33920 with
   inverted-x + swapped-x-y, so the mm values pair with the controller
   axes, not Fedora's hardcoded landscape frame), 0039 = our fix routing
   the pen through touchscreen_report_pos like touch (its coordinates are
   raw today). RAM boot; evdev gate: BTN_STYLUS in KEY bits, resolution in
   absinfo, pen and finger agree at four corners; then libinput/GNOME
   (hover cursor, pressure in a drawing app). No Bluetooth involved: the
   Fedora port reports "the pen works" through the touch IC alone.
3b. Pen charging — staged 2026-11-02 as kernel/patches/staged/0056–0062
   (own flight after 3): the Fedora port's Maxic MT5806 wireless
   transmitter driver (hBoost converter voltage asked from the charger
   firmware over PMIC GLINK, owner 32785 / opcode 0x10007, 7 V idle →
   10 V with a pen; 5 s attach window; 120-min cap; error power cycling),
   its binding and the board node (I2C hub bus 1 at 0x2b, IRQ gpio169,
   four PMIH0108 control lines, five pinctrl states), plus the three
   prerequisites the dependency audit found missing here: PMH0101 level
   shifters ls3/ls4 as RPMh XOB regulators (0056/0057 — they gate the hub
   bus) and a pmic_glink hboost auxiliary client keyed to our board
   compatible (0058); 0062 = Fedora's later fix so the first s2idle after
   load is not aborted by the IC's post-start IRQ. Config
   CONFIG_CHARGER_MT5806_PEN=m (kernel/config/staged). RAM-boot gate, in
   this order: (1) regulators — dmesg has no "could not find RPMh address
   for resource LS3B_E0/LS4B_E0" and /sys/class/regulator still lists
   every vreg_l*b plus vreg_ls3b/ls4b (a missing resource would fail the
   whole PMH0101 probe = display rails: that is the abort criterion);
   (2) /sys/bus/i2c/drivers/mt5806-pen-charger/<bus>-002b bound, dmesg
   "MT5806 firmware 0x20022, supply 7000 mV, transmitter looking for a
   pen"; debugfs mt5806-pen-charger/<dev>/status shows boost acked_mv
   7000 (the firmware confirmed the request); (3) pen on the magnet edge:
   "pen attached", present=1, state → charging, tx_voltage_mv ≈ 10000,
   uevent PEN_PRESENT=1; off: present=0, idle; (4) tablet telemetry
   unchanged (battmgr capacity/current/status still updating, charging
   with the cable in while a pen charges, no new battmgr errors). Risks:
   first AP-side use of the charger firmware's owner 32785 here; a
   permanent small drain from the 7 V idle request (stock behaviour);
   wakeup-source on the IRQ. The driver registers no power_supply — its
   attributes live on the I2C device (state, present, pen_soc, rx_soc,
   tx_voltage_mv, tx_current_ma, inhibit, scan_fast, chip_id,
   fw_version); a power_supply for the pen battery is a later polish.
4. Thermal baseline during the C5 soak (tb323fu's thermal-stress pattern:
   600 s all-core + glmark2; CPU zones held under 95 °C, no critical
   trip). The ADC/NTC zones (Perpetua cf2156997bf7, 573a270f7b90 +
   CONFIG_QCOM_SPMI_ADC5_GEN3; Fedora 0056/0190 skin/XO/USB-C) come with
   the pin bump; only then the userspace model (iceland-thermal,
   GPL-2.0-or-later, with its decoded-model provenance question).
5. Audio watch items (2026-11-02): (a) loudness — owner is not sure the
   chain reaches full volume; measure the chain vs the raw sink vs stock
   at the next audio pass (the chain is tuned never louder than stock;
   GNOME's slider caps at 100 % unless over-amplification is on);
   (b) RESOLVED 2026-11-02: the mid-session loss of the HiFi profile was
   WirePlumber creating a second card object from the compress node
   (comprC0) and losing the device reservation to it; 0.2.23 disables that
   object (52-iceland-compress.conf); (c) policy
   question for the owner: unattended-upgrades is enabled on the dev
   rootfs (it upgraded ffmpeg/imagemagick libraries tonight) — fine for
   a desktop, but on a bring-up device it moves the baseline under
   flights; the device package could disable APT::Periodic.
6. Headphones once a USB-C analog headset exists: first gate is
   SW_HEADPHONE_INSERT=1 and an MBHC plug line on insertion; then a
   Headphones UCM device from the wcd939x sequences alsa-ucm-conf already
   ships; if detection never fires, obtain Fedora's q90w2 headset fixes.

## W — Touch-to-wake (one driver rung after #44; W3 after C6)

Verified 2026-11-02 (owner's question): with the screen blanked (GNOME
idle-delay 300 s, DPMS off, nothing suspended) only the power key wakes
the tablet, by design of 0008: panel_disabling → nvt_ts_suspend → host
command 0x11 (deep sleep), IRQ disabled, contacts released. nt36xxx.c
has no gesture code (no WAKEUP_GESTURE, KEY_WAKEUP or enable_irq_wake),
the touch node has no wakeup-source, wakeup_sources lists the PMIC power
key only, and the Fedora queue carries nothing (their wake list: power
key, alarm, cover, keyboard, charger). In our favour: the touch IRQ is
GPIO 158, which is in the kaanapali PDC wake map (pinctrl-kaanapali.c),
so an s2idle wake needs no pinctrl work; the touch node declares no
supplies and the driver makes no regulator calls (its rails are not the
panel's vddio/avdd/avee that the panel driver drops at unprepare — W1
confirms the IC answers through a blank); nvt_ts_resume re-downloads the
firmware, which is also how Novatek's vendor driver leaves gesture mode.
The NT36xxx gesture mode is host command 0x13: the IC keeps a low-rate
scan and raises its IRQ on a recognised gesture (double tap, ID 15 in
Novatek's event map); OxygenOS offers double-tap-to-wake on this unit, so
the stock firmware blob carries the engine. Two behaviours, the owner's
choice: (a) any-touch wake — no deep sleep on blank, IRQ left armed,
every contact is an input event and mutter unblanks; most sensitive, a
few mW while blank, accidental wakes in a bag until H1 lid gating; (b)
double-tap wake (stock behaviour) — gesture mode, the driver decodes the
gesture and reports KEY_WAKEUP; lowest power, no single-touch wakes.
Recommended: (b), with (a) run first as W1 because it proves the whole
pipeline with one variable.

- W1 keep-awake flight (RAM boot, one driver variable): a board DT
  property (novatek,wake-on-touch) under which panel_disabling releases
  the contacts but sends no 0x11 and leaves the IRQ on, and panel_enabled
  skips the firmware re-download. PASS: blank at idle, one touch brings
  the screen back; evtest still reports after the blank; /proc/interrupts
  shows no storm on the touch line; battmgr current while blank recorded
  (the IC's cost). FAIL (IC dead after a blank) → its rail is panel-tied →
  W2 must keep that rail up, or wake stays s2idle-only.
- W2 gesture mode: 0x13 instead of 0x11, IRQ left enabled,
  nvt_ts_work_func reads the gesture byte while !bTouchIsAwake and reports
  KEY_WAKEUP press/release on the touch input device (EV_KEY capability
  added; udev then tags ID_INPUT_KEY and libinput forwards the key, which
  resets mutter's idle monitor — the gate checks `libinput debug-events`
  shows it); the resume path is unchanged. PASS: double tap wakes from
  blank in ≤1 s, 20/20; a single touch does not; 30-min blank soak with
  zero spurious wakes.
- W3 from s2idle, after C6 F1 passes: wakeup-source on the touch node,
  device_init_wakeup + enable_irq_wake in suspend. PASS: rtcwake freeze,
  double tap wakes, 10/10; pm_wakeup_irq (CONFIG_PM_DEBUG arrives with P)
  names GPIO 158.
- Patches: one driver patch (GPL-2.0-only) and one board DT patch
  (BSD-3-Clause); offered to Perpetua together with 0037/0039 (same file,
  so it follows them in the series).

## P — Kernel pin bump (charging: PD 9 V and SuperVOOC; suspend; thermal ADC)

Measured 2026-11-02 on a PD 3.0 charger (the owner's SuperVOOC-capable
adapter): contract held at 5 V (voltage_max 5 V), input limit 2 A →
4.90 V × 1.99 A = 9.75 W in, 6.9 W into the battery; the driver logs
"unknown message 0x1000a" (the firmware's input events). Cause: our pin
7c98a10e6bb7 (Oct 28) predates Denial's Oplus-Kaanapali charging work on
perpetua/v7.3 (Oct 31 – Nov 3): request matching and errno results,
charging enabled when the service comes up, host-set input limit, input
events reported, input limit by charger type with a ramp (wall chargers
to 3 A), battery status/power derivation, and "ask PD sources for 9 V"
(006b67a31bae: drop to 500 mA, request the fixed 9 V PDO, ramp to 1.5 A
= stock's 13.5 W; Denial measured 8.9 V × 1.39 A ≈ 12.4 W). Beyond PD,
SuperVOOC landed the same days: the Southchip SC8547D charge-pump driver
(both pumps, VOOC PHY over D+/D- through the WCD939x mux), the
oplus_svooc protocol library (KUnit-tested), sc8547_svooc session driver,
PMK8850 Gen4 ADC with the four thermistors (battery connector, USB
connector, SVOOC MOSFETs, subboard) — devices/iceland/charging.md:
51–55 W from the 80 W adapter (model 0x4B), battery 11.2 A, connector
48 °C / MOSFETs 44 °C; an earlier run tripped the firmware's own
"Overheat" at 54 W with pumps at 59 °C; design target "about 55 W with
70 °C hardware limits". The battmgr commits do not apply on our pin on
their own (they sit on five earlier battmgr changes) and the SuperVOOC
set is ~25 commits across power/supply, iio/adc, typec mux and DT: the
vehicle is a pin bump, not cherry-picks.

- P0 host: new pin = perpetua/v7.3 head (b7d639cfb282 or later). Dry run
  2026-11-02 on b7d639cfb282 (100 commits past the pin): 55 of our 59
  patch files apply unchanged; the four that conflict, each small:
  0028 (READ_DONE hunk merged upstream as 9ba37ef1db70 — keep only the
  WRITE_DONE hunk), 0031 (head appended nodes at the end of the board
  dts — re-diff the &iris append), 0058 (pmic_glink.c changed once by
  e02224f94012, and 5ff346c547a7 renames the board's pmic-glink
  compatible to oneplus,kaanapali-pmic-glink with the generic fallback —
  key the hBoost client on the new string), 0061 (the board dts gained
  the SuperVOOC charge pumps f87a3641ea94, the charger thermistors
  573a270f7b90 and the CPU cooling include 8bd03159587a — re-diff the
  charger node and pinctrl against the new neighbours). 0011–0027 and
  the iris set apply as-is. Config fragments re-merged with Perpetua's
  devices/iceland/kernel.config for the new drivers (ADC5 Gen3/Gen4,
  SC8547, SC8547_SVOOC, oplus_svooc). Build gate: modules diff census
  against the previous bundle, DTB diff reviewed node by node.
- P1 RAM boot on the 5 V-only charger first (the PD adapter): the whole
  system census (display, touch, audio, Wi-Fi, BT, GDM, iris, stylus) +
  PD: expect 9 V × ~1.4 A ≈ 12–13.5 W, battmgr no "unknown message".
- P2 SuperVOOC on the owner's adapter, tethered to the serial/usb0
  witness: sc8547 pumps bound, sc8547-svooc MAINS supply present, debugfs
  status; watch the four thermistors and battery current; PASS = Denial's
  envelope (≈50–55 W, pumps < 60 °C, no firmware overheat trip) and a
  clean fallback to PD when the session is refused. Safety: the
  firmware's 500 mA fallback after a failed session needs a replug; never
  run the first session unattended; the thermistor zones must exist
  before the session is enabled (their absence is the abort criterion).
- P3 flash; then the suspend rungs of C6 (ebe4aed7e940 GDSC retention
  comes with the bump) and the thermal zones for the shell model.

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

## Readiness board (2026-11-02, evening)

| Step | State | What it still needs |
|---|---|---|
| #42 video fix set | **flashed** (boot_b 82219574) | — |
| #43 stylus input (0037–0039) | **RAM-booted and gated** 2026-11-02 21:14 (boot-43-e9368756): capabilities, udev and libinput all PASS; the pen itself silent — pen scanning in the controller is off until the stock 0x7F/0x10 command, now patch 0040 (flown live as a module swap, acknowledged), still no pen packets on any of the six pen-protocol values | pen research run (pen-protocol-work/report.md) → decide the Bluetooth-side sync work; #43+0040 are flashed with #44 |
| Audio hardening + processed mic (0.2.26) + clock domains (0.2.27) | **installed and measured** 2026-11-02: audio-check "present"; both inputs listed, "voice processing" the default (owner: much higher level); the crackle that came with it traced to the two DSP-timed PCMs sharing a clock domain, fixed by capture clock.name + sink priority.driver 3000 + min-quantum 2048: 0 resyncs / 0 xruns in a 60 s soak with both sources open during playback (51 per 3 min before); owner: "rock solid" | owed: the numeric speech-level gate (≈ −40 dBFS processed vs ≈ −54 raw, needs the owner's voice for 12 s) and a call-style echo test |
| Wi-Fi idle drops (0.2.27) | root cause: station power save on, our powersave=2 drop-in outranked by Ubuntu's default file; moved to /etc zz- name | watch: no further unreachable-when-idle events; the DFS-roam "regulatory prevented using AP config" + ath12k "Timeout while waiting for regulatory update" lines → C6/P (ath12k fixes after the pin) |
| #44 pen charger (0056–0062) + stylus 0037–0040 | **building** since 2026-11-02 22:5x (60 patches, promoted; log out/build-44.log) | RAM boot; gate order: PMH0101 regulators (no cmd-db debugfs on this kernel, so the RPMh resources LS3B/LS4B can only be proven by the boot — abort criterion) → driver bound, fw 0x20022, hBoost 7000 mV acked → pen on the magnet edge → battmgr telemetry unchanged; then ONE flash for #43+#44 |
| Checkpoint (owner's standing order, 2026-11-02) | **after the charging fixes (rung P) land**: the next full checkpoint | README, hardware-status, plan, patch provenance, upstreaming ledger, firmware manifest, the status page artifact, memory; commit and push to GitHub. Interim pushes continue after every verified step (the #44 flash gets its own docs pass), but the formal "we are here" checkpoint waits for 9 V PD + SuperVOOC |
| P pin bump (charging 9 V / SuperVOOC, GDSC, thermistors) | **re-diff done and compile-checked** 2026-11-02 late (touched objects + the device tree build clean on the head; p-pinbump/README): the whole 60-patch series replayed with `git am -3` on b7d639cfb282 — 56 untouched, 0028/0031/0058/0061 resolved and parked in kernel/patches/p-pinbump/ (README there says what changed and why); the head's iceland config already enables SC8547/SVOOC/ADC5_GEN3 and the lockup detectors Denial added after two freezes during SuperVOOC; Denial's charging.md: PD 9 V ≈ 12.4 W via battmgr, SuperVOOC 51–55 W but sustained 55 W unproven (firmware Overheat at 59 °C pumps), default stays Standard and Fast is an explicit opt-in | a build day: re-diff 0028/0031/0058/0061, re-merge config with Perpetua's devices/iceland/kernel.config, full census RAM boot on the PD adapter (expect ≈13 W), SuperVOOC test tethered with the thermistor zones present, flash |
| S sensors | kernel side complete; nothing of the userspace exists (the owner's auto-rotation report is this gap) | S1 host day (arm64 mmdebstrap chroot; make-dsp-tree.sh from the factory persist registry; hexagonrpc 0.5.0-1 → 598b591 + Fedora 0001/0002; libssc 0.4.4-2; iio-sensor-proxy 3.9-1 with ssc) — start when the host is not building kernels (qemu-user builds crawl under a kernel build) |
| C6 suspend | hazards mapped; F1 procedure written | owner: one hard-reset drill (S0); then F1 on the flashed kernel with Wi-Fi off and WAKE# disarmed; the GDSC retention fix arrives with P, so F1 may reset — that is the expected data point |
| A polish | identity done (0.2.25: label MAC on Wi-Fi; the stock BT address since its recovery from the capture); mic stage in 0.2.26 | BT pairing + libspa-0.2-bluetooth (also the pen's BLE side once the research says what it needs); a USB-C analog headset for the headphone rung; loudness comparison vs stock; Chrome/Widevine playback test |
| W touch-to-wake | facts mapped (section W): deep sleep on blank, no gesture code, GPIO 158 is PDC-wakeable | after #44: W1 keep-awake RAM boot → W2 double-tap gesture (KEY_WAKEUP) → flash with the next bundle; W3 (s2idle) after C6 F1 |
| C5 leftovers | desktop in daily use on #42 | owner: power-press shows GNOME's dialog; four-corner taps under the compositor; 24 h soak on the real charger; then fold the guards into the desktop rootfs profile and build one clean image |

Idle gate: no suspend attempt in ~2 h of the #41 session nor on #42 so far
(journal: 0 "Suspending", suspend_stats 0/0, sleep.target masked) — closed.

## Master test order (one line each)

C0: NAT → apt → clock → hygiene.                        [done 10-31]
C1: display census (20/20) → weston → GPU fw → backlight. [done 10-31]
C2: touch modprobe-with-panel → soak → coldplug → unblacklist. [done 11-01]
C3: pwrseq → ath12k → BT (pairing still owed).           [done 11-01]
C4: audio PD → topology/UCM → amps → mics → chain → stock ceiling → race. [done 11-02]
VP: import (done) → build gate → RAM-boot first light → decode → flash → encode → hardening.
C5: guards (done) → T2 (done) → apt desktop → GDM on glass → taps/scale/power key → soak → clean image.
S:  host debs + DSP tree → secure-node attach → (DT flight) → ssccli → iio-sensor-proxy → GNOME rotate → ship.
A:  BT/WLAN identity (0.2.25; stock BT address since) → BT audio + pairing → pen patches (next bundle) → thermal census → headphones (needs a USB-C headset).
W:  W1 keep-awake RAM boot → W2 double-tap gesture (KEY_WAKEUP) → flash → W3 s2idle wake source after C6.
P:  (next after #44) re-diff 0028/0031/0058/0061 → config re-merge → RAM-boot census on the PD adapter (9 V ≈ 13 W) → SuperVOOC tethered with the thermistor zones → flash → CHECKPOINT: docs + push (owner's order).
C6: S0 reset drill → F1 s2idle baseline on #39 → GDSC + PM_DEBUG RAM boot → DT pair + pciehp → Wi-Fi-up → policy → pin bump → one-shots → upstreaming.
D:  Waydroid.
