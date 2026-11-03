# Hardware status — OnePlus Pad 4 (iceland) under Ubuntu

Rule inherited from the gts9u port: a component is ✅ only with evidence
produced **by this port on this hardware** — a command output, a journal
excerpt, a measurement — recorded in [porting-log.md](porting-log.md) under
the date given here. Upstream claims (the Perpetua tree, the Denial device
matrix, the Fedora iceland port, the Nura wiki) justify ❓ "expected to
work", never ✅.

Status legend: ✅ verified here · 🟡 partial, limitation described ·
❌ tried and does not work · ❓ not yet tested · — hardware absent.

Last revised: 2026-11-02. Running kernel: Perpetua perpetua/v7.3 @
`7c98a10e6bb7` + patches 0001–0028 (build #39, flashed to `boot_b`); device
package `ubuntu-iceland-device` 0.2.21.

| Component | Status | Evidence / notes |
|---|---:|---|
| Boot to initramfs | ✅ | 2026-10-30, Phase A: 18 RAM-boot flights; FDT handoff engaged (model "OnePlus Pad 4"), all six UFS LUNs seen |
| Boot to rootfs (userdata) | ✅ | 2026-10-31, Phase B: power-on → Ubuntu with no PC attached, zero failed units; `qbootctl.service` re-marks slot B every boot |
| Storage (UFS) | ✅ | 453 GB ext4 root on `userdata`, grown on first boot; legacy single-queue UFS in our DT (no MCQ), so the Fedora MCQ/ESI suspend fix does not apply |
| Co-processors (ADSP, CDSP, SOCCP) | ✅ | adsp and cdsp booted by the kernel, soccp attached; the audio protection domain publishes on every boot since the 2026-11-02 pd-mapper fix (10/10 reboots) |
| Display (dual-DSI NT36536, 3392×2400, up to 144 Hz) | ✅ | 2026-11-01: boot console and Wayland on glass; stock porch (0009) and sync orientation (0010). Reliability census 2026-11-02: 20/20 boots (kernels #36–#39); the 8 "DSI PLL(0) lock failed" lines per boot are cosmetic. Panel blank/unblank ×3 clean (T2) |
| Backlight (KTZ8869) | ✅ | driver bound, brightness readable/writable (sysfs max_brightness 4095, runs at 2047); follows panel blank/unblank (T2, 2026-11-02); a full sweep is still owed |
| GPU (Adreno 840, freedreno) | ✅ | 2026-11-01: Mesa 26, OpenGL ES 3.2; kmscube and Weston's GL renderer; vendor GMU/SQE/AQE firmware hash-manifested |
| Touchscreen (NT36536 over SPI) | ✅ | 2026-11-01, C2: 10-point multitouch, auto-loads at t≈2 s on every boot (20/20), 30-minute soak clean (patches 0007–0010); survives panel blank/unblank ×3 (T2, 2026-11-02; tap confirmation pending) |
| Stylus / pen (OnePlus Stylo Pro) | 🟡 | position, pressure, tilt and hover already reported by the touch controller's driver; libinput ignores the device for lack of BTN_STYLUS + axis resolution (GNOME session log 2026-11-02); patches 0037–0039 in preparation (bringup-plan.md A.3); pen charging is a separate later rung |
| Buttons | ✅ | power (clean shutdown), volume up/down, resin |
| Wi-Fi (WCN7860 / ath12k) | ✅ | 2026-11-01, C3: joins the configured network by itself; ssh over the air both ways; regulatory db installed (patches 0003–0005). MAC is the firmware default 00:03:7f:12:34:56 (same per-unit identity gap as Bluetooth) |
| Bluetooth (WCN7860) | 🟡 | controller up, BRAHMA 2.0.1 firmware loads (0006); pairing untested; broadcasts the Perpetua board file's placeholder address AD:5A:00:00:00:25 — this unit's persist holds no bluetooth directory, so the address will be owner-supplied or derived from the SoC serial (bringup-plan.md A) |
| USB gadget (serial console + usb0 network) | ✅ | fixed-MAC ECM, 192.168.7.2, survives reboots with no manual steps; the fallback access path |
| USB host / OTG | ❓ | |
| USB-C DisplayPort out | ❓ | in the iceland DTS since 2026-09-21 |
| Speakers (6× TFA9865 over TDM) | ✅ | 2026-11-02, audio ladder A0–A7: stock loudness behind the PipeWire protection chain (HPF, EQ, SC4 compressor, −1 dBFS limiter) as the default output; all six amplifiers verified in their operating state at the stock ceiling |
| Microphones (WCD9395, codec DMA) | ✅ | 2026-11-02: kernel patch 0028 (every DSP capture completion had been dropped as "too short", 56 vs 60 bytes; the same fix landed in Perpetua as 9ba37ef1db70); voice recorded and played back on a cold boot; noise floor −61.5/−60.5 dBFS RMS vs the Fedora port's −64 (parity) |
| Wired headphones (USB-C analog) | ❓ | untestable without a USB-C analog headset/adapter (no 3.5 mm jack on this tablet): with no jack detected the HPH endpoint stays off and playback starves (the earlier "4 periods then EIO" was that, not a bug). MBHC + Type-C mux bound; the Headphones UCM device is still to be written from the wcd939x sequences alsa-ucm-conf ships |
| Battery telemetry | ✅ | pmic-glink battery manager: percentage, voltage, current, temperature live |
| Charging | ✅ | charge control is autonomous on the ADSP (as stock); USB-PD negotiates on a real charger; SuperVOOC fast charge ❓ (the Fedora port reports it unsupported) |
| Thermal | 🟡 | 63 zones; kernel passive loops on CPU (90 °C, step_wise, cpufreq cooling) and GPU (105 °C, devfreq); no NTC/skin zones in our DT yet, so no shell-temperature model or policy daemon |
| Sensors (IMU, compass, light, hall) | ❓ | identified (Bosch IMU, AKM compass, light sensor, lid magnet), all behind the ADSP sensor hub; factory calibration captured; plan in sensors-plan.md |
| Suspend / resume | ❓ | never attempted (suspend_stats 0/0); mem_sleep defaults to deep, sleep targets masked since 0.2.21; known hazards and the F1 procedure in bringup-plan.md C6 |
| Video decode / encode (VPU, iris) | 🟡 | 2026-11-02, RAM boot of kernel #41 (patches 0029–0036): iris decoder and encoder nodes up; hardware decode of 1080p30 H.264 (302 frames, bit-identical twice, 0.06 s CPU for 10 s of video), HEVC and VP9 verified; encoder produces a bitstream, decode-back still being checked; a malformed (4:4:4 10-bit) VP9 stream faulted the firmware once (robustness item). Not flashed yet — the fix set 0043–0055 (kernel #42) flies next |
| Cameras | ❓ | camss loads safely; no pipeline, sensor or firmware work yet; last phase |
| GDM + GNOME session | ✅ | 2026-11-02: owner logged in on glass with the on-screen keyboard — Wayland user session on seat0 (VT2), `ubuntu:GNOME`, 3392×2400@120 Hz at integer 2× scale, protected Speakers sink the default, no idle suspend, interactive power button, fwupd absent (ubuntu-desktop-minimal, 844 packages). First login had been blocked only by a `/tmp/.X11-unix` ownership artifact of starting GDM by hand (fixed; a reboot avoids it). Still owed: a cold-boot census with GDM, the 25-min idle and power-press checks, the pen (ignored by libinput until A.3) |
| Waydroid | ❓ | binder/netfilter in `kernel/config/config-waydroid.fragment`; phase D |
| DRM streaming (Netflix etc.) | ❓ | Google Chrome 156 arm64 installed 2026-11-02 and it bundles the Widevine CDM 4.10.3112.0 for linux_arm64 — L3 (HD) playback is now a test, not a hack; untested |
| Haptics | — | no vibration motor in this tablet (stock disables it too) |
| GNSS / location | — | no GNSS hardware (modemless SoC) |
| Cellular | — | Wi-Fi-only device |
| Fingerprint | — | no hardware |
| microSD | — | no slot |
