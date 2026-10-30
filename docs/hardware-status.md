# Hardware status — OnePlus Pad 4 (iceland) under Ubuntu

Rule inherited from the gts9u port: a component is ✅ only with evidence
produced **by this port on this hardware** — a command output, a journal
excerpt, a measurement — recorded or linked here. Upstream claims (the
Perpetua tree, the Denial device matrix, the Nura wiki) justify ❓ "expected
to work", never ✅.

Status legend: ✅ verified here · 🟡 partial, limitation described ·
❌ tried and does not work · ❓ not yet tested · — hardware absent.

| Component | Status | Evidence / notes |
|---|---:|---|
| Boot to initramfs | ❓ | blocks everything; assumptions 1–4 in boot-strategy.md |
| Boot to rootfs (userdata) | ❓ | |
| Display (DSI panel, 144 Hz) | ❓ | panel driver `oneplus,iceland-nt36536` in Perpetua |
| Backlight | ❓ | KTZ8869 pair |
| GDM + GNOME session | ❓ | |
| GPU (Adreno 840, freedreno) | ❓ | needs Mesa 26 (in 26.04); zap fw `gen80200_zap.mbn` |
| Touchscreen | ❓ | NT36536 SPI, `=m` — must be in the initramfs or the panel-login path reviewed |
| Wi-Fi (WCN7860 / ath12k) | ❓ | firmware list unknown until `record` run |
| Bluetooth | ❓ | |
| Speakers (6× TFA9865) | ❓ | UCM profile will be needed; none written yet |
| Microphones | ❌ (upstream) | not yet supported in the kernel, per the Denial matrix |
| Cameras | ❌ (upstream) | CAMSS/Kaanapali bringup landing upstream Oct 2026; revisit on rebase |
| Battery telemetry | ❓ | oplus pmic-glink battmgr |
| SuperVOOC charging | ❓ | Denial matrix lists it working |
| USB peripheral (RNDIS/SSH) | ❓ | first diagnostic channel; kernel fragment keeps gadget support built in |
| USB host / OTG | ❓ | |
| USB-C DisplayPort out | ❓ | in the iceland DTS since 2026-09-21 |
| Suspend / resume | ❓ | SoC-level suspend "works" per Nura wiki |
| Sensors (accel/gyro/light) | ❓ | nothing in the iceland DTS yet; may follow the gts9u ADSP/hexagonrpcd path |
| Stylus | ❓ | existence of a supported stylus path unknown |
| Vibration | ❓ | nothing in the DTS |
| Waydroid | ❓ | binder/netfilter in `kernel/config/config-waydroid.fragment` |
| DRM streaming (Netflix etc.) | ❓ | browser + arm64 Widevine CDM (ChromeOS-sourced, Pi-style), L3 tier: HD yes, 4K/HDR no (no Linux has it); unlock's Android L1 loss is irrelevant to this path |
| Fingerprint | — | no hardware |
| Modem / GPS | — | Wi-Fi-only device |
| microSD | — | no slot |
