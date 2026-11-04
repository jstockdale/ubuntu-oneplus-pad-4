# Bring-up plan: Phase C onward (from 2026-10-31; revised 2026-11-04)

Baseline, 2026-11-02 evening: the tablet boots Ubuntu standalone from
boot_b (kernel #39 = Perpetua 7c98a10e6bb7 + patches 0001–0028, bundle
a4060fbb; qbootctl.service re-marks slot B every boot); device package
ubuntu-iceland-device 0.2.21; zero blacklists, zero failed units. Cold boot
brings up panel + GPU (Adreno 840 / Mesa 26), 10-point touch, Wi-Fi (auto
join), Bluetooth controller, battery telemetry, both consoles (panel fbcon,
serial getty on the gadget), ssh over usb0 and over the air, speakers at
stock loudness behind the protection chain, microphones. C0–C4 are done.
Repository public at github.com/jstockdale/ubuntu-oneplus-pad-4.

Status 2026-11-03: boot_b now carries kernel #45 (Perpetua perpetua/v7.3 @ b7d639cfb282 + patches 0001–0062 less the retired 0020, bundle boot-45-3cfb46cf; 0063 compiled into its touch module by hand; boot-44-f97398b2 is the fallback image) and the device package is 0.2.30; VP, the C5 flight and the pen suite (A.3, A.3b, A.3c) are done, rung P is in progress, and the readiness board below is the current state.

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
carried it). Added 2026-11-02 (#42 gate): every bundle gets a versioned copy
(out/bundles/boot-NN-<sha8>.img) before the next build, because the build
script rewrites out/bundle and out/kernel-iceland; bundle assembly is a
separate step from the kernel build (build-boot-bundle.sh with
INITRAMFS=…). Added 2026-11-03: CONFIG_MODVERSIONS is off, so module trees
are never mixed across pins — the rootfs module tree is replaced wholesale
at a pin bump, with a backup tar on the host; and after a series replay at
a pin bump, grep every carried match table against the board file's
compatibles at the new pin (0058 matched a renamed string on #45 and the
pen charger silently lost its hBoost).

## C0–C4 — done (10-31 … 11-02)

C0 infrastructure (NAT, apt, clock, hygiene) · C1 display + GPU firmware +
backlight · C2 touch (0007–0010, coldplug, 30-min soak) · C3 radios
(0003–0006, Wi-Fi auto-join, BT controller) · C4 audio ladder A0–A7
(0011–0028, topology built from Linaro sources, UCM2, PipeWire protection
chain, mics via 0028). Evidence per item in hardware-status.md and the
porting log. Carried opens from these phases: BT pairing + per-unit address,
wired headphones (UCM device + headset test), pen capabilities, stylus
props, the filed one-shots (T+60 USB bounce, early console loss, depmod
modules.builtin.modinfo). Status 2026-11-03: the per-unit address shipped in 0.2.25, pen capabilities and stylus props closed with #43 and the pen suite (A.3c), and BLE bonding is proven with the pen; classic BT pairing, wired headphones and the one-shots remain.

## VP — Video decode/encode (iris VPU): one kernel flight, before/with C5

Verified 2026-11-02: the pinned tree has the full iris driver with the
VPU4x generation but no kaanapali compatible; the DT prerequisites (video
reserved memory, videocc with its five GDSCs, GCC AXI clocks, interconnect
and rpmhpd OPP labels, IRQ 174, SMMU SIDs 0x1940/0x1943/0x1944/0x1a20) are
all present and unused; kernel config already builds iris, V4L2 mem2mem,
videobuf2, MDT loader, PAS, UBWC as modules/built-in; vpu40_2v.mbn
(sha256 69d4e215…) is on the tablet, in the overlay and in the manifest;
Perpetua's head (b7d639cf, 100 commits past the pin of the time; our pin since #45) has no iris work, so
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

Status 2026-11-03: VP0–VP4 done — VP1 first light and VP2 decode passed on #41 (2026-11-02); the 13-patch fix set VP4 had deferred (iceland 0157–0160, 0246–0250, 0292; infiniti 0069–0071) went in as 0043–0055 when the first VP9 session faulted the firmware; VP2/VP3 passed on #42 and #42 was flashed the same day (boot_b 82219574). Still owed: the VP4 robustness retest (a nonsensical level or an unsupported VP9 profile must be rejected, not crash the firmware) and the firmware-manifest VPU row with the sha (the manifest only names vpu40_2v.mbn in prose). VP5 stays deferred.

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
   Status 2026-11-03: PASS on 2026-11-02 — greeter on glass at 3392×2400, Wayland session on seat0, touch login with the on-screen keyboard, integer 2× scale, fwupd absent, corner taps under the finger, the short power press shows GNOME's dialog, idle gate closed (no suspend attempt on #41/#42); the desktop has been in daily use since, on #45 from 2026-11-03.
4. Fold the guards into build-ubuntu-rootfs.sh's desktop profile and
   build one clean image (installer writes userdata only; boot_b
   untouched); plymouth and gnome-remote-desktop come with the metapackage
   and are untested on this boot path.
5. Soak a day tethered; watch /sys/class/thermal under stress-ng +
   glmark2. No thermal policy daemon exists yet; Perpetua 8bd03159587a
   (kaanapali CPU passive cooling) is in the pin since #45 (2026-11-03; it only relocates iceland's existing 90 °C trips into a shared include, which is why 0031 was re-diffed).

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
- Owner's decision 2026-11-04: the full sensor path (S1–S7 + H1) is committed,
  and the SpeakerBoost engine (section SB) builds on it — S2/S3 prove the
  FastRPC daemon and the non-secure node that SB reuses, so S comes right
  after the charging sprint and SB right after S. S1 is host-only and runs in
  the charging flights' dead time (drains, soaks) whenever no kernel is
  building.

## SB — SpeakerBoost DSP engine (after the charging sprint and S2/S3; before C6)

Owner's decision 2026-11-04 ("a full implementation … the full sensor and
SpeakerBoost path … after our charging sprint"): stock's speaker-protection
engine runs on our ADSP with its own calibration, as docs/audio-plan.md §7
(rungs SB0–SB7, rail A7). Research 2026-11-04 (one agent, no fan-out; report
under /srv/ubuntu-iceland/build/audio-work/, never committed). The facts that
fix the slot: the engine is two Goodix modules the DSP loads *dynamically*
through the audio PD's FastRPC file server — the same hexagonrpcd the sensors
ladder builds (S1), attaches (S2) and opens the non-secure node for (S3) — so
SB2 cannot fly before S3; its DT remote heap rides as the one variable right
after S3; the host-only rungs interleave with the charging flights' drains and
the S1 host day. Order of record: P → CHECKPOINT → Q → S → SB → C6 → D.

- SB0/SB1 host (no tablet): acdb-tool (ours, BSD-3-Clause; AMDB manifest,
  subgraph walk, per-(subgraph, iid, CKV) calibration blobs; E1 settled on
  the host); four kernel patches K1–K4 (private data for any module, AMDB
  registration from q6apm, control-link topology tokens, a bytes kcontrol
  for module set/get param); hexagonrpcd `-S audiopd` static-PD mode (GPL-3,
  the sensors daemon package); the FastRPC remote-heap DT patch; the
  "speakerboost" topology flavour built on-device (rx + tx modules, the
  control link, a MultiMedia7 sense capture FE on PRIMARY_TDM_TX_0, cap
  2056); the device package's extraction step (the two .so, the ACDB, the
  persist cal → device-local, sha256 manifest, never shipped), the WirePlumber
  rule that holds the sense FE open while the speaker sink is active, the
  Re25 helper.
- SB2–SB7 flights (RAM boots, one variable, audio at 2056, the PipeWire chain
  the default throughout): SB2 audio-PD attach → SB3 AMDB registration → SB4
  the TX graph alone (sense capture = E4) → SB5 the RX graph with the engine
  and the link (first-sound rules) → SB6 Re25 injection, R0/F0 readback,
  protection evidence (enable 1 vs 0 on the V/I capture) → SB7 A/B against the
  PipeWire chain, the 8192 raise as the last change, 24 h soak, ship as the
  default.
- Rails: A1–A6 verbatim plus A7 (the engine is never instantiated without its
  calibration, enable, Re25 and a started, verified IV path); cap 2056 until
  SB7; nothing above −20 dBFS or longer than 10 s before SB6; one ADSP restart
  ends a flight; never above the A7-measured stock loudness; no Goodix or OPLUS
  byte in the repo or a published overlay.

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
   Status 2026-11-03: BLE bonding is proven — the Stylo Pro is bonded with LE Secure Connections (A.3c N4) and served by HOGP/uhid, and the bond persists across reboots; classic pairing and A2DP remain untested and libspa-0.2-bluetooth is still to be installed.
3. Stylus (OnePlus Stylo Pro) — input; flown as #43 on 2026-11-02 (evdev gate PASS: BTN_STYLUS/BTN_STYLUS2 in the KEY bits, 124 units/mm on every axis, libinput lists a 274×194 mm tablet, zero "missing tablet capabilities"), flashed with #45 on 2026-11-03:
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
   Superseded 2026-11-02/03: on this unit the pen stayed silent through the touch IC alone — the controller's pen scanning is off until 0x7F/0x10 (0040), and even with scanning on and every host-side ack accepted (N2 on #44) the Stylo Pro writes only after the Bluetooth-brokered OPP handshake (A.3c; H2 refuted), so the Bluetooth leg is required, not polish.
3b. Pen charging — staged 2026-11-02 as 0056–0062, promoted into the series (kernel/patches/0056–0062) for build #44; flown on #44 2026-11-03, PASS; flashed with #45
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
   CONFIG_CHARGER_MT5806_PEN=m (kernel/config/config-pen-charger.fragment, promoted from staged/ with the patches). RAM-boot gate, in
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
   fw_version);    a power_supply for the pen battery is a later polish.
   Status 2026-11-03 (#44 RAM boot, boot-44-f97398b2; = N3 of the ladder): gate PASS in the planned order — vreg_ls3b/ls4b present and enabled with no RPMh complaint (the abort criterion); pmic_glink and the RPMh regulator driver are built in, so only mt5806_pen_charger.ko needed staging; driver bound at 0-002b, firmware 0x20022, 7000 mV acknowledged; the pen docked → "pen attached" within a second, state charging at 7.96 V × 0.11 A, the pen's address delivered (root-only, never recorded); tablet telemetry unchanged, no battmgr errors. Watch items: pen_soc stays −1 and no 10 V step was logged (charging proceeds at ≈ 8 V). The series rides in #45 (flashed); the pen battery into UPower is still owed.
3c. Pen protocol (OPP) ladder — flown on the #44 RAM boot 2026-11-03 (#44 was never flashed; #45 carries 0040–0042 and, by hand in its touch module, 0063); N0–N6 all reached, polish owed (see N6). Verified 2026-11-02
   (research run, report in /srv/ubuntu-iceland/build/pen-protocol-work,
   its notes hold stock log extracts with addresses and never enter the
   repo): the Stylo Pro is an "OPP" pen. Stock enables scanning with the
   same `0x7F 0x10 0x01` we send (0040), then the controller emits a
   20-byte uplink-timing frame (input id 30, page 6, 107–161 ms after the
   enable), the stock daemon writes it to the pen over a bonded BLE link
   (GATT handle 0x0067, write-with-response), and the pen's replies
   (connection state, pen info type 2, pressure) are written back into
   the controller as `0x7F 0x40 <opcode>` commands, refused until a fresh
   uplink frame. We do the enable only: our parser skips the uplink frame
   as an out-of-range slot, sends no 0x7F 0x40, has no bridge, and nothing
   is bonded. Firmware (fw_ver 0x15, byte-identical) and DT pen
   configuration are at parity; the FAE-firmware theory was refuted by the
   verifiers. Leading hypothesis H1: the pen transmits only after the
   BLE-delivered timing table; H2 (the controller's decoder opens on the
   host-side acks alone, no radio needed) is the cheapest decisive test;
   also H3 pen asleep/bond-bound, H4 charger-mode 0x53 never sent, H6 our
   adapter carries the stock BT address without the pen's bond key.
   Outcome 2026-11-03: H2 refuted on #44 (every downlink command accepted, no pen packets), so H1 stands — the pen transmits only after the BLE-delivered timing block; H6 did not arise (the pen bonded to our adapter on the stock address at the first attempt); H3 is real in a narrower form — the pen sleeps on the charger and when idle and applies the timing only after "sleep exit", which is why the daemon replays the handshake on that console event.
   - N0 owner's hand, nothing written: evtest on event4 with USB and the
     charger unplugged while writing (H4); the interrupt-reaction probe
     (pen tip on the glass, buttons pressed, no finger, against a 60 s
     idle baseline of NVT-ts-spi in /proc/interrupts); a phone BLE scan
     with the tip pressed (presence and name only).
   - N1 frame logger (module swap, logging only): log every frame with
     point_data[1]>>3 == 30, any 0xF0 pen-ID packet and bytes 109..111.
     PASS: a page-6 frame with [3]=0, [4]=20 within 200 ms of the 0x10 ack
     — the controller waits for the handshake exactly as on stock. PASS 2026-11-03 (#44, module swap of 0041): the frame came within a second of the enable, type 0, 20 bytes, the same pattern the stock log shows.
   - N2 downlink probe (module swap, a debugfs pen_cmd node): after the
     ack and the N1 frame write TIMING_CFG_ACK 0x02, CON_STA 0x20, CFG_ID
     0x01, PEN_INFO 0x48, then SIZE_INFO, owner writing throughout. PASS:
     point_data[66] leaves 0xFF / BTN_TOOL_PEN events → H2 proven, the
     BLE leg becomes polish (pressure source, battery, double-click).
     FAIL: H1 confirmed as necessary. Keep the stock gate semantics
     (downlink only after a fresh uplink) in the driver either way. Outcome 2026-11-03: FAIL — every downlink command was accepted (status byte 0x00; the controller re-emitted its frame after the first ack) yet no pen packets; H2 refuted, H1 confirmed as necessary.
   - N3 = the 3b MT5806 flight: proof of life (present, pen_soc) and the
     pen's address (root-only, read, never recorded) for N4.
   - N4 BlueZ bond (owner's go-ahead for radio actions): btmon passive
     capture while the pen wakes, scan or direct connect, pair, trust.
     PASS: bonded, uhid "OnePlus Stylo Pro" devices, the vendor
     characteristics (0x003d/0x0045/0x0048/0x004b, Battery 0x0021) and
     the 0x0067 characteristic enumerated; persists across a reboot. FAIL:
     H6 — retry with the adapter on its generated address, then the stock
     one; if both refuse, the pen's old bond must be cleared (procedure
     unknown; owner question: does the pen have a reset gesture?). PASS 2026-11-03: the pen advertises while docked (ADV_IND every 16 s, Flags 0x04 only — no LE-discoverable bit, so plain discovery never creates a device object and Ubuntu's bluetoothd does not export the experimental ConnectDevice); a discovery filter with the pen's address as `pattern` makes BlueZ report it, and pair/trust/connect bonded it with LE Secure Connections on the first attempt — uhid "OnePlus Stylo Pro Mouse"/"Keyboard", Battery 100 %, barrel haptics live. BlueZ names characteristics by declaration handle, one below the stock log's value handles: stock 0x0067 = char0066 (0783b03e-8535-b5a0-7140-a304d2495cbb, write+notify), 0x003d = char003c (status), 0x0048 = char0047 (180938ac, barrel 02 press / 03 release), Battery 0x0021 = char0020; 6e400003 is the pen's text console. H6 did not arise; the bond persists across reboots (#45).
   - N5 bridge: one kernel rung exposing each uplink block (sysfs + uevent
     or a misc device) and accepting the downlink opcodes through the N2
     node; a BSD-3-Clause daemon on the rootfs that, over BlueZ D-Bus,
     enables notifications on 0x003d, sends the status request, writes
     the block to 0x0067 and maps the pen's notifications to
     CON_STA/CFG_ID/PEN_INFO/TIMING_CFG_ACK/PRESS. PASS: BTN_TOOL_PEN,
     position and non-zero pressure within 2 s of the pen touching the
     glass after a resume; survives 10 blank/unblank cycles. Done 2026-11-03: the kernel side is 0041 (sysfs pen_uplink + uevent, pen_downlink with stock's gate, pen_debug) and 0042 (pen_input — contact is the controller's call, magnitude the pen's); the daemon is iceland-pen (python3, BlueZ D-Bus, pyudev; BSD-3-Clause; device package 0.2.28 with /etc/iceland/pen.conf as a conffile) — it writes the 20-byte block to char0066, sends the five acknowledgements with stock's values (cfg_id 1, pen_info 2, con_sta 1, timing_ack 1, hopfrq_ack 1), mirrors the ~140 Hz pressure stream, maps the barrel button to BTN_STYLUS, and replays the handshake on every uplink frame, at start-up and on the console's "sleep exit"; since 0.2.29 it waits for ServicesResolved. The owner writes with pressure (14 taps → 14 tip-downs, up to 15507 of 16384, nothing while hovering); the 10-cycle blank/unblank soak of this gate is not recorded.
   - N6 polish: pressure source, battery level, double-click, the A.3
     four-corner gate, libinput tablet mode and a drawing app; 30-min soak. Status 2026-11-03: pressure source and the barrel button (right click while hovering) done; GNOME's Graphics Tablets panel lists "OnePlus Pad 4" since 0.2.29 (0063 ids, 74-iceland-pen.rules presenting the SPI devices as I2C because libwacom accepts only bus 0/3/5/0x18, /etc/libwacom/oneplus-pad4.tablet). Owed: the barrel's double/long-press codes, middle-click mapping, pen battery into UPower, the libinput "pressure offset greater than 50%" notice (noise when a tap begins without a hover frame), the four-corner gate, the 30-min soak, and a proposal to libwacom to accept the SPI bus.
   - Fidelity patch (not carried — 0041 took the handshake only; still owed, best with rung W's driver patch since today's blank leaves the IC awake): write the 0x11 deep-sleep
     in nvt_ts_suspend; pen command conditional on the REK wait and also
     from Boot_Update_Firmware; IRQ trigger from the DT flags once the
     pin bias is reconciled; charger 0x53/0x51 from a power-supply
     notifier. Licensing: driver work GPL-2.0-only (constants and
     behaviour taken from the GPL-2.0 vendor tree as interface facts,
     never code), the daemon BSD-3-Clause; offer the driver ABI to
     Perpetua only once N5 passes — N5 passed 2026-11-03: the pen series 0037, 0039–0042, 0063 (+ 0038 DT) is now a Perpetua candidate (docs/upstreaming.md); nothing has been filed anywhere yet (the maintainer's GitHub account is needed; `gh` is not on the build host).
4. Thermal baseline during the C5 soak (tb323fu's thermal-stress pattern:
   600 s all-core + glmark2; CPU zones held under 95 °C, no critical
   trip). The ADC/NTC zones (Perpetua cf2156997bf7, 573a270f7b90 +
   CONFIG_QCOM_SPMI_ADC5_GEN3; Fedora 0056/0190 skin/XO/USB-C) come with
   the pin bump — status 2026-11-03: the bump (#45) brought the PMK8850 Gen4 ADC with six charger thermistors as labelled IIO channels (batt_con_therm, usb_con_therm, usb_temp_l, svooc_mos_therm, subboard_therm, usb_temp_r) but no thermal zones for them, so the shell model still waits on the zones and the C5-soak thermal census is still owed; only then the userspace model (iceland-thermal,
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

## W — Touch-to-wake (one driver rung after #45, flashed 2026-11-03; W3 after C6)

Verified 2026-11-02 (owner's question): with the screen blanked (GNOME
idle-delay 300 s, DPMS off, nothing suspended) only the power key wakes
the tablet, by design of 0008: panel_disabling → nvt_ts_suspend → host
command 0x11 (deep sleep), IRQ disabled, contacts released — corrected the same day by the #43 side finding: nvt_ts_suspend builds the 0x11 command but never writes it (no CTP_SPI_WRITE), so on blank the IC is left awake with its IRQ disabled and contacts released; the IC's blank-time draw is already being paid, W1's "send no 0x11" is today's behaviour and its one variable is leaving the IRQ armed, and the stock driver also carries a PENDETECT wake gesture. nt36xxx.c
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
  double tap wakes, 10/10; pm_wakeup_irq (CONFIG_PM_DEBUG did not come with P — no fragment sets it; add it on the C6 F2 RAM boot)
  names GPIO 158.
- Patches: one driver patch (GPL-2.0-only) and one board DT patch
  (BSD-3-Clause); offered to Perpetua together with 0037/0039 (same file,
  so it follows them in the series).

## P — Kernel pin bump (charging: PD 9 V and SuperVOOC; suspend; thermal ADC)

Measured 2026-11-02 on a PD 3.0 charger (the owner's SuperVOOC-capable
adapter): contract held at 5 V (voltage_max 5 V), input limit 2 A →
4.90 V × 1.99 A = 9.75 W in, 6.9 W into the battery; the driver logs
"unknown message 0x1000a" (the firmware's input events). Cause: our pin at the time,
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
PMK8850 Gen4 ADC with the charger thermistors (four named in the commit, six on #45 — usb_temp_l and usb_temp_r as well: battery connector, USB
connector, SVOOC MOSFETs, subboard) — devices/iceland/charging.md:
51–55 W from the 80 W adapter (model 0x4B), battery 11.2 A, connector
48 °C / MOSFETs 44 °C; an earlier run tripped the firmware's own
"Overheat" at 54 W with pumps at 59 °C; design target "about 55 W with
70 °C hardware limits". The battmgr commits do not apply on our pin on
their own (they sit on five earlier battmgr changes) and the SuperVOOC
set is ~25 commits across power/supply, iio/adc, typec mux and DT: the
vehicle is a pin bump, not cherry-picks.

- P0 host — done 2026-11-02/03: pin = perpetua/v7.3 head b7d639cfb282 (fetch-perpetua.sh default); the series replayed with `git am -3`, the four re-diffs in place (0028 WRITE_DONE hunk only; 0031 just the &iris block; 0058 keeps Xiaomi's pmic-glink match data next to ours; 0061 keeps the head's SuperVOOC nodes next to the pen charger's), 0020 retired (AK1: the head's TFA9865 driver already puts the middle amplifiers in stock's playing state, 5f:00e0 / 76:d700 read back on #45), the interim p-pinbump/ copies removed on 2026-11-03 (notes in kernel/patches/README), config fragments re-merged (ADC5 Gen3/Gen4, SC8547, SC8547_SVOOC, oplus_svooc, the NMI/soft lockup detectors with hung_task 120 s). Dry run
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
- P1 — done 2026-11-03 (#45 RAM boot; four fastboot attempts for the bootloader's USB re-enumeration churn, nothing on storage touched): census PASS (card, codec macros, soundwire, touch and pen, iris, lockup detectors on; AK1 regmaps at stock); PD_PPS 8.94 V, voltage_max 9 V, ICL 1.5 A, current_max 5 A at 99 % — the 9 V contract, no "unknown message"; the rate at a lower charge is still owed (expect ≈ 12–13 W). Two boot races surfaced and were fixed in 0.2.29 (WirePlumber's UCM profile never attaching, the pen daemon resolving GATT before ServicesResolved). As planned: RAM boot on the 5 V-only charger first (the PD adapter): the whole
  system census (display, touch, audio, Wi-Fi, BT, GDM, iris, stylus) +
  PD: expect 9 V × ~1.4 A ≈ 12–13.5 W, battmgr no "unknown message".
- P2 SuperVOOC on the owner's adapter, tethered to the serial/usb0
  witness: sc8547 pumps bound, sc8547-svooc MAINS supply present, debugfs
  status; watch the six thermistors (IIO channels, no thermal zones yet — the session script reads the channels) and battery current; PASS = Denial's
  envelope (≈50–55 W, pumps < 60 °C, no firmware overheat trip) and a
  clean fallback to PD when the session is refused. Safety: the
  firmware's 500 mA fallback after a failed session needs a replug; never
  run the first session unattended; the thermistor zones must exist
  before the session is enabled (their absence is the abort criterion).
  Superseded 2026-11-03: the owner's adapter (Anker) is a PD PPS source to this firmware — 0 VOOC frames at any charge — so the stages need the OnePlus 80 W SuperVOOC brick; the usb0 witness cannot exist with the brick in the only port, so the witness is ssh over Wi-Fi, the persistent journal (33 boots kept) with the NMI/soft lockup detectors (hung_task 120 s), and the host-side svooc-session.sh log (not in the repo). The driver has no current knob — svooc_entry_ua() takes 2 A above 85 %, 3 A from 56 to 85 %, 6.2 A at ≤ 55 %, then the minimum with the thermal derate, the 4.46 V taper and the 55 W budget; admissible only with health Good, capacity < 90 %, cell 15–44 °C, every thermistor under its soft limit; a session ends at 90 %; the charger gate is usb_type DCP or Apple-brick at VBUS 4.5–5.5 V two seconds after the plug — so the stages are selected by charge level: stage 1 brick in at 86–89 % (2 A, self-ending at 90 %), stage 2 at 60–84 % (3 A, single pump), stage 3 at ≤ 55 % (up to 6.2 A, Denial's 50–55 W), each attended, discharge-to-half.sh (device-local /tmp; backlight at maximum plus a small CPU load under a cell-temperature thermostat) for the set-up. Until the stages pass, 75-iceland-charging.rules (0.2.30) writes Standard on every boot — in Standard the driver never starts a session and PD is unaffected; after a PASS the rule is dropped so Fast (the driver's default) ships, the owner's decision of 2026-11-03. The thermistor zones do not exist; the six IIO channels do, and their presence is the abort criterion now.
- P3 flash — done 2026-11-03 (boot-45-3cfb46cf to boot_b, lock-in PASS, boot_a 1f11e2c6 untouched, slot _b bootable + successful; boot-44-f97398b2 is the fallback image; the 24 h soak runs since). Still owed in P: the 9 V rate at a lower charge, the standard-charging regression (SDP/DCP/PD, OTG, connected boot, 500 mA fallback), the three SuperVOOC stages, the soak, then the formal checkpoint (this pass is the interim documentation checkpoint of 2026-11-03). Then the suspend rungs of C6 (ebe4aed7e940 GDSC retention
  comes with the bump) and the thermal zones for the shell model.

## Q — PD PPS through the charge pumps (after P's VOOC stages and the checkpoint; before C6)

Research run of 2026-11-03 (six readers, synthesis, three adversarial
reviews, revision 2): report and notes under
/srv/ubuntu-iceland/build/pps-work/ (research material, never committed).
Stock charges this unit from any PPS adapter through the same two SC8547D
pumps at up to 55 W (its arbitration table: VOOC 80 / PPS 55 / PD 13 /
QC 13); the firmware owns only the PD contract and the buck. Perpetua at the
pin holds a fixed 9 V contract through the buck (13.1 W measured) and runs
the pumps only over VOOC. Design (one driver, two adapter back-ends):

- A-series, `qcom_battmgr` (variant-scoped, inert unless written, module
  swaps): A0 the firmware's charger log as the witness (0069/0070, done
  2026-11-03); A1 name the PD notifications (0x56/0x7f/0x91); A2 read the
  source capabilities (opcode 0x10004, from the charging work) and decode
  the APDO; A3 the tcpm-shaped programmable supply on qcom-battmgr-usb —
  ONLINE 2 with the host's input vote, VOLTAGE_MIN, one 29/30 pair per
  request, **a 10.0 V rejection on every write path**, the −1 exit refused
  after a failed 5 V exit.
- Flights F1–F4 (pumps untouched, Anker, hand writes ≤ 9.0 V): F1 the
  APDO list (FAIL ends the rung for this source: it needs min ≤ 5.5 V,
  max ≥ 9.2 V, ≥ 1.5 A); F2 the vote-gated request from the 9 V contract
  (which write triggers the PD Request; 0x56; UPower with online = 2);
  F3 120 s keep-alive; F4 the verified 5 V exit and the −1 recovery
  (hard precondition of any switching).
- B-series, `sc8547_svooc`: B1 the policy arithmetic into a KUnit-pinned
  library (gauge-referenced window kept); B2 the adapter seam; B3 refuse
  system suspend during a session (owed before C6's F1). The SuperVOOC
  PASS that drops the Standard policy is taken on the module that ships.
- C-series: C1 the PPS back-end lifting VBUS with the pumps off (IDLE APDO
  gate, debugfs `protocols` mask default vooc, slow worker for every
  firmware round trip, 9.5 V cap, exit with its failure branch, attempt
  counter) → F5a lift, F5b 60 s hold at 9.5 V, F5c cable pull; C2 first
  switching at 1 A with the RDO as the hold current and the ≤ 5 s
  re-request → F6 three runs (normal, cable pull, deliberate 5 s watchdog
  trip) after the S0 hard-reset drill; C3 regulation → F7a 30 min at 3 A
  plus a reboot during a session; C4 the dual-pump join → F7b to
  min(APDO, 5 A, 55 W); C5 docs; C6 default on, one flashed bundle; C7 the
  two USB-connector thermistors into the envelope (a flagged DT change).

Rails added by the review: no request above 10.0 V by any path; the input
vote released only with both pumps verified off and a fixed contract back;
no PPS-capable module on the tablet before the 0.2.33 boot-time Standard
is verified on a connected boot; flight modules loaded from /run, never the
first session unattended; the device-local bench script with a dead-man
timer (Wi-Fi only mirrors). Denial's design review of the plan is the first
item on the critical path for upstreaming (needs the maintainer's GitHub
account). Effort about three weeks interleaved; nothing blocks on the
OnePlus brick.

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
stays stuck off and the phone resets" — must precede any flashed suspend; in the pin since #45 (rung P, 2026-11-03), so F1 on #45 no longer expects the GDSC reset.
The serial console is the USB gadget, which dwc3 device-mode suspend
disconnects, so the witnesses are the panel, the host's USB log and the
post-hoc suspend_stats/journal. No MCQ on our UFS DT (single reg, no
msi-parent), so the "MCQ suspend fix" does not apply. CONFIG_PM_DEBUG is
unset (no pm_wakeup_irq); Perpetua added it for aston on 2026-11-03.

- S0 once, before any flight: drill and record the hard-reset gesture on
  the idle, synced tablet (runbook says power+vol-up; the media plan says
  power ≥10 s; only Vol-Down+Power ~15 s → fastboot is verified).
  **Done 2026-11-03, PASS**: the power key held on the idle tablet (Anker
  out) — logind logged "Power key pressed long." and took no action, the
  PMIC's long-press reset did the rest; the tablet was back on Wi-Fi 76 s
  later from the same slot (boot_b, #46) with the previous boot's journal
  intact to its last line, the charging policy at 2.8 s, the pen charging,
  audio up; the flight module in /run was gone, as the swap vehicle
  intends (porting log, "S0 hard-reset drill").
- F1 baseline on flashed #45 (written for #39), nothing built: battery ≥40 %, tethered,
  host `journalctl -k -f`; on the tablet `nmcli radio wifi off`, `echo
  disabled > /sys/bus/pci/devices/0000:00:00.0/power/wakeup`, snapshot
  wakeup_sources + /proc/interrupts + suspend_stats, then `systemd-run
  --unit=s2idle-f1 rtcwake -m freeze -s 30` (freeze = s2idle, bypasses
  the deep default; the unit survives the gadget drop). Do not press the
  power key during the window. PASS: suspend_stats success 0→1, fail 0;
  "PM: suspend entry (s2idle)"/"suspend exit" ≥25 s apart; panel, gadget
  and ssh back within 60 s. FAIL (a) wakes in <5 s → diff wakeup_sources
  → disable that source → F1b; (b) sleeps then resets → GDSC hazard
  confirmed → F2 = RAM boot with CONFIG_PM_DEBUG=y (ebe4aed7e940 is in the pin since #45, so a reset now points elsewhere); (c)
  never wakes → power press, else the drilled reset → fastboot → boot_b.
- Then the DT pair (drop wake-gpios; USB wakeup-source) as our own
  patches, CONFIG_HOTPLUG_PCI_PCIE=y (Perpetua's route for the root port
  to reach D3, 78b1d23d88bc) and the Wi-Fi-up rung; flash after the
  RAM-boot gate. Policy last, rootfs-only: tmpfiles mem_sleep=s2idle,
  sleep.conf.d MemorySleepMode=s2idle, logind HandlePowerKey=suspend,
  unmask the sleep targets, GNOME timers back on.
- Drain (S3) was unreachable on the old pin 7c98a10e6bb7 (d68240c6e4bb and cf7e4df5e479 are in b7d639cfb282 since #45, untested here): the single-cluster CPU PM domain
  makes the firmware deny system power-down; d68240c6e4bb (two clusters
  + rpmh-stats node) is pin-bump material, with cf7e4df5e479 (UFS lane
  clocks → CXO shutdown).
- The filed one-shots: T+60 USB bounce, early console loss, battmgr uevent
  EAGAIN, depmod modules.builtin.modinfo, on-device update-initramfs
  writing an unused /boot initrd.
- Kernel pin bump — done as rung P on 2026-11-03 (#45 = b7d639cfb282, the 2026-11-02 head, which holds everything listed here that predates it; 0028 kept only its WRITE_DONE hunk; ADC5 Gen3/Gen4 merged; CONFIG_PM_DEBUG not yet; the suspend commits untested): past 9ba37ef1db70 (drop
  0028's READ_DONE hunk); suspend block ebe4aed7e940, d68240c6e4bb,
  78b1d23d88bc, cf7e4df5e479, 8b2990f9ae9f; thermal/ADC cf2156997bf7,
  573a270f7b90, b4ab5eb72d15 (+CONFIG_QCOM_SPMI_ADC5_GEN3=m) — note
  8bd03159587a only relocates iceland's existing 90 °C trips; battmgr
  006b67a31bae (9 V PD); ath12k 476ac2f9e476 (inert without
  qcom,drv-supported); the dpu/dp DisplayPort fixes; re-diff 0011–0024 and
  0029–0036 if they move.
- Upstreaming: docs/upstreaming.md (WRITE_DONE consistency patch, our
  0002/0004–0007/0010/0031, the license request to the Fedora port; since 2026-11-03 also the pen series 0037, 0039–0042, 0063 (+ 0038 DT) for Perpetua, PipeWire's compress-node card object, WirePlumber's first-pass UCM attach, and libwacom's SPI bus — nothing filed anywhere yet).

## Phase D — Waydroid (after C5 stable)

Binder/ashmem config audit in the Perpetua tree, Waydroid image,
shared-kernel Android apps. Scoped when C5 lands.

## Readiness board (revised 2026-11-03)

| Step | State | What it still needs |
|---|---|---|
| #42 video fix set | **flashed** (boot_b 82219574) | — |
| #43 stylus input (0037–0039) | **RAM-booted and gated** 2026-11-02 21:14 (boot-43-e9368756): capabilities, udev and libinput all PASS; the pen itself silent — pen scanning in the controller is off until the stock 0x7F/0x10 command, now patch 0040 (flown live as a module swap, acknowledged), still no pen packets on any of the six pen-protocol values | research done (report in /srv/ubuntu-iceland/build/pen-protocol-work); patch 0041 (handshake plumbing: uplink export, downlink node, stock gate) written and compile-checked, flies as a module swap on #44: the Stylo Pro is an OPP pen — stock brokers a 20-byte timing block from the controller to the pen over BLE and the pen's replies back as 0x7F 0x40 commands; ladder A.3c (N0–N6) written; the cheapest decisive test is N2 (host-side acks, no radio), after the #44 flash; #43+0040 are flashed with #44. Status 2026-11-03: superseded — 0041 flew on the #44 RAM boot (N1 PASS, N2 refuted H2), N4/N5 bonded the pen and made it write, 0042 and 0063 followed; #44 was never flashed; 0037–0042 are in #45, flashed 2026-11-03 (0063 by hand in its touch module) |
| Audio hardening + processed mic (0.2.26) + clock domains (0.2.27) | **installed and measured** 2026-11-02: audio-check "present"; both inputs listed, "voice processing" the default (owner: much higher level); the crackle that came with it traced to the two DSP-timed PCMs sharing a clock domain, fixed by capture clock.name + sink priority.driver 3000 + min-quantum 2048: 0 resyncs / 0 xruns in a 60 s soak with both sources open during playback (51 per 3 min before); owner: "rock solid" | owed: the numeric speech-level gate (≈ −40 dBFS processed vs ≈ −54 raw, needs the owner's voice for 12 s) and a call-style echo test |
| Wi-Fi idle drops (0.2.27) + slow joins / regulatory timeout (2026-11-03) | power save: our drop-in outranked by Ubuntu's default file, moved to /etc zz- name (0.2.27). Slow joins: the firmware 11d scan after every radio start swallowed the first 4-way handshake (7.2 s → WRONG_KEY → minutes of back-off), off since 0068 (first handshake 8 s after reload); the 3 s regulatory timeout after each association fixed by Qualcomm's ath-next series 0064–0067; both flown live on #45; confirmed on the #46 boots: no "Failed to set the requested Country", no regulatory timeout, joins in 11–27 s when the first association is to the 5240 or 2462 MHz radio | watch, sharpened 2026-11-03: every drop since the fix was on the mesh's 5680 MHz radio (channel 136, DFS) — the firmware declares beacon loss 6.6 s after associating there (once it took the first handshake with it, once "Connection to AP lost" 12 s after CONNECTED) while joins to the other two radios are clean; a probe (profile pinned to that radio for one re-activation, ath12k debug 0x312) is written, on hold after the 15:40 reset |
| #44 pen charger (0056–0062) + stylus 0037–0040 | **RAM-booted and gated** 2026-11-03 (boot-44-f97398b2): level shifters, hBoost, pen attached and charging, address delivered, telemetry unchanged — PASS; on the same boot the pen ladder reached N5: the Stylo Pro writes with pressure (0041/0042 + iceland-pen) | flash decision 2026-11-03: #45 (rung P) builds on top of #44's content, so the #44 flash is skipped in favour of flashing #45 after its gate — done, #45 flashed 2026-11-03; boot-44-f97398b2 is the fallback image; original gate text for the record: PMH0101 regulators (no cmd-db debugfs on this kernel, so the RPMh resources LS3B/LS4B can only be proven by the boot — abort criterion) → driver bound, fw 0x20022, hBoost 7000 mV acked → pen on the magnet edge → battmgr telemetry unchanged; then ONE flash for #43+#44 |
| Checkpoint (owner's standing order, 2026-11-02) | **after the charging fixes (rung P) land**: the next full checkpoint | README, hardware-status, plan, patch provenance, upstreaming ledger, firmware manifest, the status page artifact, memory; commit and push to GitHub. Interim pushes continue after every verified step (#44 was never flashed; the #45 flash got this interim documentation checkpoint, ordered by the owner on 2026-11-03), but the formal "we are here" checkpoint waits for the 9 V rate at a lower charge, the standard-charging regression, the three SuperVOOC stages and the 24 h soak |
| P pin bump (charging 9 V / SuperVOOC, GDSC, thermistors) | **#45 flashed to boot_b 2026-11-03** (boot-45-3cfb46cf, lock-in PASS); RAM-boot census the same day PASS — 9 V PD contract on the Anker (PD_PPS, 8.94 V, voltage_max 9 V), both pumps bound, svooc supply + debugfs, six ADC thermistors live, AK1 regmaps at stock, lockup detectors on; two boot races found and fixed in 0.2.29 (WirePlumber HiFi attach, pen daemon GATT discovery), the WirePlumber one repeats on every boot of this pin and the guard nets it; 0.2.30 holds the svooc driver in Standard across boots (it re-probes to Fast) and scopes the guard to the owner's session; fastboot needed four attempts (bootloader USB churn) | owed: (a) done 2026-11-03 — 13.1 W at 84 % (8.80 V × 1.49 A, ICL 1.5 A, the firmware's PD cap); (b) the standard-charging regression — PD and connected boot PASS 2026-11-03; SDP at the #46 RAM boot (PC cable); DCP with the brick PASS 2026-11-03 (the firmware types it BrickID, 4.96 V × 2.99 A = 14.8 W, no session in Standard); OTG and the 500 mA fallback still owed; (c) the SuperVOOC staged validation with the OnePlus 80 W brick (a PD source never speaks VOOC: the Anker is PD PPS to this firmware, 0 frames at any charge). The driver has no current knob — svooc_entry_ua() picks the session current by charge level: 2 A above 85 %, 3 A from 56 %, 6.2 A at ≤ 55 %, minimum with the thermal derate, the voltage taper and the 55 W budget; a session ends at 90 % — so stage 1 (2 A, self-terminating) = brick in at 86–89 %, stage 2 (3 A; both pumps, the second joins above 1.4 A) at 60–84 %, stage 3 (up to 6.2 A, Denial's 50–55 W) at ≤ 55 % with a cool cell; each attended, svooc-session.sh logging the IIO thermistors, the persistent journal as the freeze witness (no usb0 with the brick in the only port). **Stage 1 PASS 2026-11-03 16:14–16:24**: adapter model 0x24, 87 → 90 % in 548 s at 2 A adapter current (about 1 A into each of the two pumps at the 9 V bus, ≈ 2.4 A into the cell; VBUS 8.9–9.0 V, buck idle), taper to 1.5 A at 4.44 V, the driver's own end at 90 %, 0 frame errors, every thermistor cooler at the end than at the start (≤ 34.2 °C), the policy unit left the opted-in session alone three times. **Stage 2 PASS 2026-11-03 17:27–17:46**: 84 → 90 % in 1109 s at 3 A adapter current (1.54 + 1.51 A into the two pumps at 9.05 V, 27.6 W, ≈ 4.3 A into the cell at the start), the taper stepping 3.0 → 2.0 → 1.5 A, the driver's own end, 0 frame errors, hottest point the battery connector at 38.8 °C (soft limit 60), the policy unit quiet four times. **Stage 3 FAIL-by-reset 2026-11-03 20:25–20:30**: the 6.2 A entry at 54 % ran 5 min at 46 W (2.6 A per pump, +10 A into the cell, dies 42 °C, battery connector 43 °C, nothing near a limit) and the tablet reset silently — the day's second unexplained reset (no kernel line, no watchdog bite, no reason witness); the layered safety held (pump watchdog, boot-time Standard). Owner's decision 20:48: the production level stays 6.2 A, the reset is root-caused (battery undamaged: health Good, capacity 13 789 mAh unchanged, pumps Good, firmware clean). A second 6.2 A run with host-side witnesses reset the same way at +4:45 with every quantity steady to the last second. Established: not the APSS watchdog (not armed on our boots; stopped during both runs), not the PMIC watchdog (disabled), not a kernel panic (panic=0 hangs), not a PMIC die alarm — the reset comes from below the kernel; Denial's commits f4a65f20c7ab/c617cde5d95a describe the same cascade (pump I2C timeouts → SOCCP charger firmware → RPMh → CPUs) as freezes on their unit. Stock's host disables the charger (CHG_EN 0) and forces the OVP setting (132) for a VOOC session and pins CPU frequencies; our driver votes ICL 0 only. **Root-caused 2026-11-04 (runs A and A2 of the ladder, porting log)**: the brick is a 55 W-class adapter (stock's adapter table, model 0x24); asked 6.2 A it sits at its 5.1 A ceiling and steps its output down at +5:00 and +16:00 on its own clock (an I2C-level trace of every frame shows nothing preceding the step); both fatal runs died at that step, while two runs with every cpuidle state above WFI disabled crossed it at 46 W and lived; stock's AP VOOC PHY holds cpu_latency_qos 0 for the whole session, ours held nothing. Patch 0077 (the QoS hold, mirroring stock): **flight D1 PASS 2026-11-04 10:13** — cpuidle back to the governor, the same 46 W session from 54 %, the brick's +300 s step crossed with the deep-idle usage sum flat for the whole session; 0077 in the series. The conformance review (build/pps-work/proto-review/conformance-ledger.md: 16 differences that matter, 60 equivalences) is implemented as 0078–0084 (adapter-class cap, hysteresis, stray frames, the change path, the second pump, register fidelity; KUnit 23/23, W=1 and checkpatch clean, the 82-patch series applies), staged under build/pps-work/d-series for flights D2 (0078: does the step disappear at 5.0 A), D3 (0079–0082 + 0084) and D4 (0083 with the pump driver reloaded), each entering the series after its flight. **Flight D2 2026-11-04 11:38–12:20 (0077 + 0078 as a module swap)**: the brick identified as model 0x24 → class 55 W → 5.0 A asked; it still stepped 5.2 → 4.1 A at exactly +5:00 and → 3.05 A at +16:00 with the request held at 5.0 A and nothing but GET_VBAT on the wire — the step is the brick's own clock, 0078 is conformance (it enters the series), 0077 is the cure (deep-idle sum flat, both steps crossed, no reset); no GET_CURRENT after the grant at a cool cell. From +30:28 the gauge-referenced VBUS window tripped four times on ~300 mV, ~100 ms sags of the brick's output at a 4.3–4.4 V cell (each followed by a clean 3 A restart) — 0084's two-reading window passes all four moments by 100–200 mV, so D3 carries it. Ended by the session script at 12:20:32 ("finished"); ten seconds later the tablet reset silently with the brick still in (see C6). Fast does not ship as the default until the 6.2 A stage completes on the patched driver; (d) a 24 h soak on #45 (running since the flash); (e) build #46 (0058 matching the renamed board compatible): RAM-booted and FLASHED 2026-11-03 (boot-46-23711786, lock-in PASS) — hBoost device present, MT5806 firmware 0x20022, docked pen charging; SDP typed with ICL 500 mA on the PC cable; policy Standard at 2.8 s on a connected boot with the Anker (the PPS plan's precondition); Wi-Fi joined in 27 s with the 0064–0068 module; then CHECKPOINT |
| Q PD PPS through the pumps | research done 2026-11-03 (plan revision 2 under build/pps-work); A0 (firmware charger log, 0069/0070) built and loaded on #46; A1–A3 written and self-reviewed (the review agents ran out of credits); **F1–F4 PASS 2026-11-03**: the firmware answers the read-buffer opcode, the Anker offers PPS 5–11 V at 5 A (55 W reachable), no Oplus SVID; the vote-gated entry, a 6.0 V request, a 120 s hold kept by the firmware, the 5 V exit and the 9 V ramp back all as specified (the voltage write triggers the PD Request; PPS_Status empty; UPower fine with online 2); 0071–0073 in the series | B1–B3 written 2026-11-03 by the implementation workflow as 0074–0076 under build/pps-work/b-series (policy library sc8547_direct_policy + KUnit, the adapter seam struct svooc_adapter_ops with seven operations, the suspend refusal closed against the driver's own worker); its three reviewers' objections taken in revision 2 (an unlocked state write, the suspend/worker race, the gate move); a second five-reviewer pass with adversarial verification confirmed only minors and nits (named hard-stop constants, boundary pins for 60 W and the over-power step, the PPS numbers of the test moved into the library, two message corrections, the PM callbacks renamed) — revision 3 applies them; evidence at revision 2: arm64 modules W=1 clean, kernel-doc silent, checkpatch 0/2/1 + 0/0/0 + 0/0/0, KUnit 19/19 on the host under UML (the port's first KUnit use), the 75-patch series applies in order on the pin. Rule 3 decision: the brick stages stay on the shipped #46 module so Fast can ship on #46; the refactored two-module pair re-flies a 3 A session as the B-gate before any bundle carries it. 0074–0076 entered the series 2026-11-03 17:40. **C1 written the same evening** (one patch, 0077, under build/pps-work/c-series: the PD PPS back-end with the pumps off — Kconfig bool default n, the IDLE APDO gate, the protocols mask default vooc, the slow worker, the lift to 2·VBAT + 150 mV capped at min(APDO, 9.5 V), a bounded hold with the F5b sweep, the verified exit with its failure branch, the attempt counter; 25 KUnit cases; both Kconfig builds W=1 clean; the 76-patch series applies on the pin); its own four reviewers found one blocker (a clamp whose low bound could exceed the cap) and three majors, all taken in revision 2; the independent five-reviewer pass runs on a frozen copy before it enters the series; then F5a/F5b/F5c on the Anker as a three-module swap (A-series battmgr + the C1 pair) | A1–A3 as module swaps → F1 (the Anker's APDO list decides) → F2–F4 pumps untouched → B → C with flights F5–F7b; predecessors: #46 flash + the 0.2.33 connected-boot check (done), the formal checkpoint, S0 before F6 (done 2026-11-03) |
| S sensors | kernel side complete; nothing of the userspace exists (the owner's auto-rotation report is this gap); **the full path S1–S7 + H1 committed by the owner 2026-11-04**, first after the charging sprint (SB builds on S2/S3) | S1 host day (arm64 mmdebstrap chroot; make-dsp-tree.sh from the factory persist registry; hexagonrpc 0.5.0-1 → 598b591 + Fedora 0001/0002 + the `-S audiopd` mode for SB; libssc 0.4.4-2; iio-sensor-proxy 3.9-1 with ssc) — start when the host is not building kernels (qemu-user builds crawl under a kernel build) |
| SB SpeakerBoost DSP engine | research done 2026-11-04 (one agent; report under build/audio-work, never committed): stock's protection is two Goodix modules loaded dynamically into the ADSP audio PD, AMDB-registered from the OPLUS ACDB, 74-parameter calibration per CKV variant, per-unit Re25/F0 in persist; mainline gaps named (private data, AMDB register, control-link tokens, bytes control, DT heap, daemon static-PD mode); **committed by the owner 2026-11-04 as a full implementation** (audio-plan.md §7, rail A7) | SB0/SB1 host work (acdb-tool, K1–K4, hexagonrpcd -S audiopd, DT heap patch, the speakerboost topology flavour, the extraction step) in the charging flights' dead time; flights SB2–SB7 after S3, one variable each, cap 2056 until SB7 |
| C6 suspend | hazards mapped; F1 procedure written; **S0 hard-reset drill PASS 2026-11-03** (power key held; slot, rootfs and journal intact; unattended boot to the desktop in 76 s) | next: F1 on the flashed kernel with Wi-Fi off and WAKE# disarmed; the GDSC retention fix (ebe4aed7e940) is in the pin since #45, so F1 runs on flashed #45 and a reset now would not be the GDSC hazard; CONFIG_PM_DEBUG still to be added on the F2 RAM boot. Open since 2026-11-03: **two unexplained silent resets on #46** (the SuperVOOC ones — 20:30 and a second at 21:31 — root-caused 2026-11-04, see P; the 15:40 one stays open, and repeated 2026-11-04 10:36:20: no charger, 72 s after the discharge load started, same silent signature; a userspace `/dev/cpu_dma_latency` 0 hold is being tried across the next drain as the cheapest discriminator; **a third on 2026-11-04 at 12:20:42**, ten seconds after flight D2's session ended cleanly, at or within seconds of the unplug (the owner recalls the reboot after the cable came out; the host record puts the death before the unplug call was sent and the firmware's last flush still showed the cable present with the buck re-enabling at 5 V, ICL 2000 → 2500 — the two events were seconds apart either way), policy Standard, pumps idle, the four host witnesses costing ≈ 700 forks/s with two clusters at 3.6 GHz; the 30 min drain before it under the hold, with the stress load paused and the backlight at max, had no reset. Common to all three: a heavy, bursty CPU load around a power-path transition (load start, input removal, buck re-enable); two of three on battery, this one on the brick. Working hypothesis: a rail collapse below the kernel under load. Discriminators before D3: a backlight-only drain, the session-end transition with the witnesses stopped first, a cpufreq ceiling under a stress load on battery) — 15:40 (the desktop under the discharge load, no charger) and 20:30 (five minutes into the 46 W SuperVOOC stage 3) — both with no kernel line before, no shutdown, no panic text, the APSS watchdog reporting no bite, and no reset-reason witness on this device (no ramoops survives, PON GEN3 has no reason registers, the bootloader log is unreadable); kernel.panic=0 means a panic hangs rather than reboots, so the signature points at the power path or the firmware side; shared factors: #46 (the first build with the pen charger's hBoost alive — #45 ran 24 h clean), long uptime under load, high battery current in either direction. Next: separate the variables (a 3 A session long run; the discharge load alone; the pen undocked), the boot census reads the watchdog status each time; the stress helper and the active Wi-Fi probe stay off; decide kernel.panic (0 = hang for inspection vs 10 = unattended reboot) |
| A polish | identity done (0.2.25: label MAC on Wi-Fi; the stock BT address since its recovery from the capture); mic stage in 0.2.26 | classic BT pairing + libspa-0.2-bluetooth (BLE bonding is proven — the pen is bonded with LE Secure Connections since 2026-11-03, served by HOGP/uhid); pen polish — barrel double/long-press codes, middle click, battery into UPower, the libwacom SPI-bus proposal; a USB-C analog headset for the headphone rung; loudness comparison vs stock; Chrome/Widevine playback test |
| W touch-to-wake | facts mapped (section W): deep sleep on blank, no gesture code, GPIO 158 is PDC-wakeable | after #45 (flashed 2026-11-03): W1 keep-awake RAM boot → W2 double-tap gesture (KEY_WAKEUP) → flash with the next bundle; W3 (s2idle) after C6 F1 |
| C5 leftovers | desktop in daily use, on #45 since 2026-11-03; power press → GNOME's dialog and four-corner taps confirmed by the owner 2026-11-02 | the 24 h soak (running on #45 since the flash, counted under P); then fold the guards into the desktop rootfs profile and build one clean image |

Idle gate: no suspend attempt in ~2 h of the #41 session nor on #42 so far
(journal: 0 "Suspending", suspend_stats 0/0, sleep.target masked) — closed.

## Master test order (one line each)

C0: NAT → apt → clock → hygiene.                        [done 10-31]
C1: display census (20/20) → weston → GPU fw → backlight. [done 10-31]
C2: touch modprobe-with-panel → soak → coldplug → unblacklist. [done 11-01]
C3: pwrseq → ath12k → BT (BLE bonding proven with the pen 11-03; classic pairing still owed).           [done 11-01]
C4: audio PD → topology/UCM → amps → mics → chain → stock ceiling → race. [done 11-02]
VP: import → build gate → RAM-boot first light → decode → flash → encode → hardening (fix set 0043–0055 in #42). [done 11-02; VP4 robustness retest and the manifest VPU row owed]
C5: guards (done) → T2 (done) → apt desktop (done) → GDM on glass (done 11-02) → taps/scale/power key (done 11-02) → soak (running on #45) → clean image.
S:  host debs + DSP tree → secure-node attach → (DT flight) → ssccli → iio-sensor-proxy → GNOME rotate → ship.  [full path committed 11-04; first after the charging sprint; SB needs S2/S3]
SB: acdb-tool + K1–K4 + hexagonrpcd -S audiopd + DT heap + speakerboost topology flavour (host, in the drains) → audio-PD attach → AMDB register → TX graph (sense capture) → RX graph (first sound) → Re25 + R0/F0 + protection evidence → A/B vs the PipeWire chain → 8192 → 24 h soak → ship.  [committed 11-04; after S, before C6]
A:  BT/WLAN identity (0.2.25; stock BT address since) → pen (#43–#45 + A.3c N0–N6, done 11-03; polish owed) → BT audio + classic pairing (BLE bonding proven) → thermal census → headphones (needs a USB-C headset).
W:  W1 keep-awake RAM boot → W2 double-tap gesture (KEY_WAKEUP) → flash → W3 s2idle wake source after C6.
P:  re-diff → config re-merge → RAM-boot census (9 V contract) → flash #45 [done 11-03] → SuperVOOC staged by charge level with the brick (2 A at 86–89 % → 3 A at 60–84 % → 6.2 A at ≤ 55 % [reset ×2 11-03; root-caused 11-04: the brick's +5:00 step × deep cpuidle; 0077 flight D1 next]) → 9 V rate + standard regression → 24 h soak → drop the Standard rule → CHECKPOINT: docs + push (owner's order).
Q:  A0 (done) → A1–A3 module swaps → F1 APDO list → F2–F4 (pumps off) [done 11-03] → B1–B3 (in progress) → C1 F5a/b/c → S0 [done 11-03] → C2 F6 ×3 → C3 F7a → C4 F7b → regression → bundle with the bool → C5/C6.
C6: S0 reset drill [done 11-03] → F1 s2idle baseline on #45 (GDSC retention in the pin since P) → PM_DEBUG RAM boot → DT pair + pciehp → Wi-Fi-up → policy → one-shots → upstreaming (pin bump done as P, 11-03).
D:  Waydroid.
