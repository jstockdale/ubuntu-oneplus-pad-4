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
package `ubuntu-iceland-device` 0.2.20.

| Component | Status | Evidence / notes |
|---|---:|---|
| Boot to initramfs | ✅ | 2026-10-30, Phase A: 18 RAM-boot flights; FDT handoff engaged (model "OnePlus Pad 4"), all six UFS LUNs seen |
| Boot to rootfs (userdata) | ✅ | 2026-10-31, Phase B: power-on → Ubuntu with no PC attached, zero failed units; `qbootctl.service` re-marks slot B every boot |
| Storage (UFS) | ✅ | 453 GB ext4 root on `userdata`, grown on first boot; the MCQ suspend fix is queued for the suspend phase |
| Co-processors (ADSP, CDSP, SOCCP) | ✅ | adsp and cdsp booted by the kernel, soccp attached; the audio protection domain publishes on every boot since the 2026-11-02 pd-mapper fix (10/10 reboots) |
| Display (dual-DSI NT36536, 3392×2400, up to 144 Hz) | ✅ | 2026-11-01: boot console and Wayland on glass; stock porch (0009) and sync orientation (0010); a formal multi-boot reliability census is still owed |
| Backlight (KTZ8869) | ✅ | driver bound, brightness readable/writable (max 2047); a full brightness sweep is still owed |
| GPU (Adreno 840, freedreno) | ✅ | 2026-11-01: Mesa 26, OpenGL ES 3.2; kmscube and Weston's GL renderer; vendor GMU/SQE/AQE firmware hash-manifested |
| Touchscreen (NT36536 over SPI) | ✅ | 2026-11-01, C2: 10-point multitouch, auto-loads at t≈2 s on every boot, 30-minute soak clean (patches 0007–0010) |
| Stylus / pen | 🟡 | the pen registers alongside touch; `BTN_STYLUS` and the physical-size properties are missing (sibling-port patch queued) |
| Buttons | ✅ | power (clean shutdown), volume up/down, resin |
| Wi-Fi (WCN7860 / ath12k) | ✅ | 2026-11-01, C3: joins the configured network by itself; ssh over the air both ways; regulatory db installed (patches 0003–0005) |
| Bluetooth (WCN7860) | 🟡 | controller up, BRAHMA firmware loads (0006); pairing untested; the per-unit address from `persist` is not wired yet |
| USB gadget (serial console + usb0 network) | ✅ | fixed-MAC ECM, 192.168.7.2, survives reboots with no manual steps; the fallback access path |
| USB host / OTG | ❓ | |
| USB-C DisplayPort out | ❓ | in the iceland DTS since 2026-09-21 |
| Speakers (6× TFA9865 over TDM) | ✅ | 2026-11-02, audio ladder A0–A7: stock loudness behind the PipeWire protection chain (HPF, EQ, SC4 compressor, −1 dBFS limiter) as the default output; all six amplifiers verified in their operating state at the stock ceiling |
| Microphones (WCD9395, codec DMA) | ✅ | 2026-11-02: kernel patch 0028 (every DSP capture completion had been dropped as "too short", 56 vs 60 bytes); voice recorded and played back on a cold boot; noise-floor comparison against the Fedora port still owed |
| Wired headphones | 🟡 | the output path starts (first buffers play) then stops with EIO — a separate issue; no headset was plugged in, and the Headphones UCM device does not exist yet |
| Battery telemetry | ✅ | pmic-glink battery manager: percentage, voltage, current, temperature live |
| Charging | ✅ | charge control is autonomous on the ADSP (as stock); USB-PD negotiates on a real charger; SuperVOOC fast charge ❓ (the Fedora port reports it unsupported) |
| Thermal | 🟡 | 63 kernel thermal zones registered; no skin-temperature model or policy daemon yet |
| Sensors (IMU, compass, light, hall) | ❓ | identified (Bosch IMU, AKM compass, light sensor, lid magnet), all behind the ADSP sensor hub; factory calibration captured; plan in sensors-plan.md |
| Suspend / resume | ❓ | deliberately untested; auto-suspend will be disabled before a desktop ships (C6) |
| Video decode (VPU) | ❓ | firmware staged on the device; driver not bound; plan in media-misc-plan.md |
| Cameras | ❓ | camss loads safely; no pipeline, sensor or firmware work yet; last phase |
| GDM + GNOME session | ❓ | not installed yet; Weston (GL) proven; prerequisites (fwupd UFS guard, autosuspend off) listed in bringup-plan.md C5 |
| Waydroid | ❓ | binder/netfilter in `kernel/config/config-waydroid.fragment`; phase D |
| DRM streaming (Netflix etc.) | ❓ | browser + arm64 Widevine CDM, L3 tier (HD, not 4K/HDR) is the only path on Linux |
| Haptics | — | no vibration motor in this tablet (stock disables it too) |
| GNSS / location | — | no GNSS hardware (modemless SoC) |
| Cellular | — | Wi-Fi-only device |
| Fingerprint | — | no hardware |
| microSD | — | no slot |
