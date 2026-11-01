# Bring-up plan: Phase C onward (from 2026-10-31)

Baseline: tablet boots Ubuntu standalone from boot_b (slot-protected by
qbootctl.service), zero failed units; access = panel fbcon + serial
getty + ssh over fixed-MAC ECM (enx026963656c68 / 192.168.7.2);
charging verified ADSP-autonomous; factory restore kit on Drive
(serial 2fe096b5). Known opens carried in: DSI PHY probe lottery, GPU
firmware absent (gen80200_sqe.fw + zap), touch blacklisted (probe
resets panel IC), pwrseq_qcom_wcn blacklisted (probe resets SoC; XPU
suspicion), audio untested, suspend untested, T+60 USB bounce +
early-console-loss filed, fwupd UFS guard owed before desktop.

Standing rails, unchanged: never set_active / vbmeta / dtbo /
vendor_boot / GPT edits / EDL. One variable per flight. Any kernel
change flies as a RAM boot before it is flashed. Restore: boot_b ←
factory/fcap/part-boot_b.img; init_boot_b ← bundle archive; both
sha-verified. Short power-press = clean shutdown from any state.

## C0 — Infrastructure (no reboots, ~an hour)

1. Host NAT so the tablet reaches the internet over usb0:
   ip_forward=1 + masquerade out the wifi uplink; tablet gets
   Gateway=192.168.7.1 + DNS in 80-iceland-usb0.network (ship in
   0.2.14, hand-apply first). Test: ping 1.1.1.1, apt update.
2. apt baseline: update/upgrade, install weston kmscube mesa-utils
   evtest i2c-tools stress-ng. Test: versions print.
3. Clock: with internet, chrony steps to real time (journals gain true
   timestamps; the epoch-pin forensics workaround retires). Test:
   `date` correct after sync.
4. Host hygiene: verify ModemManager ignore rule applied (no AT junk
   at the login prompt on next boot); exactly one serial listener
   (lsof /dev/ttyACM0).
5. QoL: avahi hostname (ssh ubuntu@ubuntu-iceland.local), ssh key for
   root-less scripted runs.

Gate: tablet installs packages itself; clock true.

## C1 — Display made permanent (critical path, first pixels already
   proven)

1. Characterize the DSI PHY lottery: ten standalone reboots, record
   fb0 success per boot (journal now has real time); capture the
   failing signature (PLL lock loop vs phy defer).
2. Fix probe order (likely dsi_phy vs dpu deferral; candidate: probe
   reorder patch or fw_devlink tuning on release cmdline — RAM-boot
   the candidate kernel first). Gate: 5/5 boots with fb0.
3. Software compositor smoke test (no GPU needed): weston with pixman
   over ssh on KMS. Gate: weston desktop renders on glass.
4. GPU firmware: obtain stock ROM package for OPD2514 (GLO), unpack
   super → /vendor/firmware; harvest the Adreno SQE microcode the
   kernel requests as qcom/gen80200_sqe.fw plus the signed zap blob;
   install under /lib/firmware. RAM-boot test first. Gate: dmesg GPU
   revision line, /dev/dri/renderD128 present, kmscube accelerated.
   Note: GPU preemption stays off on the stock firmware pair (carried
   note from research).
5. Backlight control: ktz8869 sysfs brightness sweep. Gate: brightness
   follows writes.

## C2 — Input: touch (the gate between "demo" and "usable")

1. Study the NT36536 probe reset: it shares reset/power with the live
   panel; the Fedora iceland port carries a working driver/patch —
   port it (re-clone mzakamin's tree; our earlier review notes are in
   the porting log).
2. Test ladder, RAM boots: (a) fb0 up, manual `modprobe nt36536_ts`,
   panel must survive, evtest shows contacts; (b) 20-min soak with
   periodic touches; (c) unblacklist, coldplug boot, 3/3 reboots.
3. Only then remove nt36536_ts from the shipped blacklist (0.2.x).
Gate: reliable multitouch across reboots, panel never resets.

## C3 — Connectivity (parallel track once C0 done)

1. pwrseq_qcom_wcn XPU hunt, split-node diag flights:
   a. v23: pmu node minus the BT half (bt-enable-gpios + bt_default
      pinctrl) → modprobe pwrseq → survive/reset splits PMIC-GPIO vs
      TLMM path.
   b. v24: inverse split (minus WLAN half) confirms.
   c. Finer split inside the guilty half: pinctrl-0 state vs gpiod
      claim → names the exact pin/write.
   d. Fix in DT (reserve the protected pin / drop the redundant
      enable if firmware pre-drives it), unblacklist pwrseq.
2. WLAN: ath12k (PCIe path; bridge + pwrctrl already proven) +
   WCN786x firmware/board files from stock vendor or ath12k-firmware.
   Gate: scan, join AP, iperf sane, then UNTETHERED ssh over wifi
   (usb0 stays as fallback).
3. BT: hci_uart/btqca + ship the stock blob under the requested
   gngbtfw20.mbn name. Gate: scan; pair a BT keyboard (second input
   path, de-risks desktop debugging).

## C4 — Audio (after C1, parallel to C3; CAUTION: smart amps)

1. Verify audio PD up via pd-mapper/PDR (green on standalone boot).
2. LPASS topology + UCM2 profiles (sibling-port references; machine
   driver snd_soc_sc8280xp already binds). Gate: aplay -l lists card.
3. tfa9865 smart amps are damageable without speaker protection:
   first sound at minimal volume, short bursts, watch amp temp.
   Gate: clean low-volume playback; mics deferred to DSP-extras.

## C5 — Desktop: GNOME on Wayland

Prereqs: C1 (accel + reliable panel) and C2 (touch). BT keyboard from
C3 helpful but not required.
1. BEFORE installing: fwupd UFS guard (mask fwupd or disable its UFS
   plugin in the device package) — a desktop pull-in must never offer
   UFS controller firmware updates. Also pre-disable GNOME auto
   suspend (first untested s2idle must not fire by timer).
2. apt install ubuntu-desktop-minimal on the running system (fast
   iteration); the build-ubuntu-rootfs.sh desktop profile (GDM +
   gnome-initial-setup) becomes the clean-image path once proven.
3. GDM on KMS; first-run through gnome-initial-setup ON GLASS with
   touch. Panel orientation transform + HiDPI scale in mutter.
4. Soak: a day of desktop use tethered; watch thermals
   (/sys/class/thermal) under stress-ng + glmark2.
Gate: daily-drivable desktop, no tether.

## C6 — Hardening / dailyability

- Suspend/resume campaign (s2idle): expect breakage; single-variable
  (wifi off, display off paths) with the serial console as witness.
- The filed one-shots: T+60 USB bounce, early console loss, battmgr
  uevent EAGAIN, depmod modules.builtin.modinfo, on-device
  update-initramfs writing an unused /boot initrd.
- Kernel update flow: runbook'd fastboot reflash (RAM-boot gate every
  time); the Fedora-style U-Boot chainload stays the phase-2
  candidate for PC-free kernel updates.
- Upstreaming hygiene: our carried patches (watchdog stop, panic=0
  drop, pwrseq pin fix when found) documented for the perpetua queue.

## Phase D — Waydroid (after C5 stable)

Binder/ashmem config audit in the perpetua tree, Waydroid image,
shared-kernel Android apps. Scoped when C5 lands.

## Master test order (one line each)

C0: NAT → apt → clock → hygiene.
C1: lottery census → probe fix (5/5) → weston/pixman → GPU fw
    (kmscube) → backlight.
C2: touch modprobe-with-panel → soak → coldplug 3/3 → unblacklist.
C3: pwrseq split v23 → v24 → pin fix → ath12k → BT (keyboard).
C4: audio PD → topology/UCM → low-volume amp test.
C5: fwupd guard + suspend-off → desktop install → GDM on glass →
    orientation/scale → soak.
C6: s2idle → filed one-shots → update flow → upstreaming.
D:  Waydroid.
