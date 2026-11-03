# Ubuntu 26.04 LTS for the OnePlus Pad 4 ("iceland")

> ## ⚠️ Under heavy development — use with caution
>
> This repository is a live bring-up log as much as it is a port. Things
> change daily, some of them are flashed to a tablet minutes after they are
> written, and nothing here is a release. **Do not use any of it on a device
> you are not prepared to recover yourself**, and read the
> [safety rules](#safety-rules) before you type `fastboot`. If you are not
> comfortable rebuilding a kernel, repacking an Android boot image and
> reading a kernel log over a serial console, this is not ready for you yet;
> watch the repository instead.
>
> There are **no installable images** yet. What exists today is a build
> system, a kernel patch series, a device package, and a documented method
> that one tablet has been through.

Ubuntu 26.04 LTS (arm64) running natively on the OnePlus Pad 4 — model
`OPD2514`, codename `iceland`, Snapdragon 8 Elite Gen 5 (`SM8850`,
"kaanapali"), fastboot product `canoe` — on the
[Perpetua](https://github.com/denialwm/linux-perpetua) mainline kernel
(upstream Linux 7.3 plus the Denial project's iceland device support). GNOME
on Wayland and Waydroid are the goal; today the tablet boots to a console and
a GNOME on Wayland desktop with display, GPU, touch, the Stylo Pro pen, Wi-Fi,
speakers, microphones and hardware video decode working from its own storage.

The structure is modeled on
[agcarbajo/ubuntu-galaxy-tab-s9-ultra](https://github.com/agcarbajo/ubuntu-galaxy-tab-s9-ultra)
so that this family of ports stays alike: the same stage scripts, environment
variables, artifact layout and documentation discipline. Two sibling ports of
the same hardware are consulted constantly and credited throughout:
[mzakamin-hub/iceland-mainline](https://github.com/mzakamin-hub/iceland-mainline)
(Fedora on the same tablet) and
[joonhoekim/tb323fu-linux](https://github.com/joonhoekim/tb323fu-linux)
(the Lenovo Legion Y700 Gen 5, same SoC).

## Status

Verified on this hardware by this port, as of 2026-11-03. Each ✅ has its
evidence in [docs/hardware-status.md](docs/hardware-status.md) and the dated
entry in [docs/porting-log.md](docs/porting-log.md); upstream claims never
earn a ✅ here.

| Component | Status | Notes |
|---|---:|---|
| Boot from own storage (A/B slot, `qbootctl`) | ✅ | power-on → Ubuntu, no PC; slot re-marked every boot |
| Display (dual-DSI NT36536, 3392×2400, 144 Hz) | ✅ | console and Wayland on glass; stock timings |
| GPU (Adreno 840, Mesa 26 / freedreno) | ✅ | OpenGL ES 3.2, GL-composited Weston |
| Touchscreen (10-point) | ✅ | auto-loads every boot, 30-minute soak clean; touch-to-wake not yet (planned) |
| Stylus | 🟡 | writes with pressure, taps (click) and hovers, barrel button = right click, listed in GNOME's Graphics Tablets panel — kernel #45 with the Bluetooth-brokered handshake (bond + the iceland-pen bridge daemon since device package 0.2.28, the libwacom definition since 0.2.29); charged on the magnet edge on #44 (on #45 the charger's hBoost client is unmatched after a compatible rename in the pin — fix in the series, flies with build #46); the barrel's double/long-press codes, the middle-click mapping and the pen's battery in UPower still owed |
| Backlight, buttons | ✅ | |
| Wi-Fi (WCN7860 / ath12k) | ✅ | auto-joins; ssh over the air |
| Bluetooth | 🟡 | controller up on the device's factory address; BLE bonding verified — the Stylo Pro is bonded with LE Secure Connections and served by HOGP over uhid; classic pairing and A2DP untested (A2DP needs libspa-0.2-bluetooth) |
| USB gadget (serial console + network) | ✅ | the fallback access path |
| Speakers (6× TFA9865) | ✅ | stock loudness behind a PipeWire protection chain |
| Microphones | ✅ | the capture fix is upstream at the pin (Perpetua `9ba37ef1db70`; our 0028 now carries only the WRITE_DONE half, see [Upstreaming](#upstreaming)); the processed "voice processing" input with stock's recorder gain has been the default since device package 0.2.26, the raw source stays selectable |
| Wired headphones (USB-C analog) | ❓ | untestable without a USB-C analog headset — with no jack detected the HPH endpoint stays off and playback starves, which is what the earlier "starts then stops" was, not a bug |
| Battery telemetry, charging | 🟡 | telemetry ✅; 9 V PD contract on kernel #45 (flashed 2026-11-03; 13.1 W measured at 84 %, the firmware's PD cap); SuperVOOC (≈55 W) drivers bound, held in Standard until the staged validation with the OnePlus brick |
| Thermal | 🟡 | zones registered; no policy daemon yet |
| Sensors / IMU | ❓ | planned ([docs/sensors-plan.md](docs/sensors-plan.md)); no auto-rotation until then |
| Suspend / resume | ❓ | deliberately untested so far |
| Video decode / encode (VPU) | ✅ | 2026-11-02: hardware H.264/HEVC/VP9 decode and H.264 encode, flashed (kernel #42) |
| Cameras | ❓ | last phase ([docs/media-misc-plan.md](docs/media-misc-plan.md)) |
| GNOME on Wayland | ✅ | 2026-11-02: logged in on glass — Wayland session, 2× scale, 120 Hz, touch + on-screen keyboard; cold-boot census and idle checks still owed |
| Waydroid | ❓ | after the desktop is daily-drivable |
| Haptics, GNSS, cellular, fingerprint, microSD | — | not fitted on this device |

## How it boots

The long version, with every invariant, is
[docs/boot-strategy.md](docs/boot-strategy.md).

- The stock bootloader chain is kept. Perpetua builds the iceland device
  tree **into** the kernel image and swaps it in at boot (`ARM64_FDT_HANDOFF`),
  so `vendor_boot`, `dtbo` and `vbmeta` are **never written**.
- `boot.img` and `init_boot.img` are repacked from the owner's **own stock
  images** with Perpetua's `devices/boot/android-gki`, which keeps the stock
  v4 headers and AVB properties. Our initramfs goes into `init_boot.img`; this ABL ignores the
  ramdisk of a downloaded image, so a kernel is test-flown with `fastboot boot`
  of the kernel-only `boot.img` against the flashed `init_boot` before it is
  flashed itself.
- The root filesystem is an ext4 image written to `userdata`, found by label
  (`LABEL=UBPAD4_ROOT`); the first boot grows it to the whole partition.
- Everything is flashed over fastboot on the slot the device already uses.
  Nothing ever switches slots or touches any other partition.

Proprietary firmware (ADSP, CDSP, GPU, Wi-Fi, Bluetooth, touch…) is **not in
this repository**: `scripts/stage-firmware.py` extracts it from the owner's
stock partition images against the hash manifest in
[configs/firmware/iceland.toml](configs/firmware/iceland.toml). The audio
topology is *built* from Linaro's BSD-licensed sources
(`scripts/build-audio-topology.sh`), not copied from the device.

## Safety rules

This device has **no public EDL/Firehose loader** and is not serviced
everywhere. The one documented Pad 4 brick happened by switching to the
never-populated B slot. These rules are enforced by the installer and
repeated in every flashing document:

1. Never `fastboot set_active`.
2. Never write `vbmeta`, `dtbo`, `vendor_boot` or the partition table; never
   use EDL.
3. Flash only `boot`, `init_boot` and `userdata`, on the active slot.
4. Keep the stock OTA package: its `boot.img`/`init_boot.img` are both the
   repack templates and the way back.
5. One variable per flight; every kernel change is RAM-booted
   (`fastboot boot`) before it is flashed.
6. A versioned copy of every boot bundle before the next build — the build
   rewrites `out/bundle` and `out/kernel-iceland`, and the last good image is
   the way back when a flight fails.

## Building

Each stage is a separate script that can be run on its own; `build-release.sh`
only fixes the order and the data flow. Nothing here flashes a device. Run
`scripts/check-build-deps.sh` first.

| Stage | Script | Produces |
|---|---|---|
| 0 | `scripts/check-build-deps.sh` | a report of missing host tools |
| 1 | `scripts/fetch-perpetua.sh` | the pinned Perpetua kernel checkout |
| 2 | `scripts/build-mainline-kernel.sh` | `Image` (DTB built in), modules, config — with `kernel/patches/` applied |
| 3 | `scripts/stage-stock-images.sh` | stock `boot.img`/`init_boot.img` templates + provenance, from the owner's OTA package |
| 4 | `scripts/stage-firmware.py` | the verified proprietary firmware staging + `PROVENANCE.json` |
| 4a | `scripts/build-audio-topology.sh` | `OnePlus-Pad4-tplg.bin` from Linaro's audioreach-topology + the Pad 4 overlay |
| 5 | `scripts/build-ubuntu-rootfs.sh` | the Ubuntu 26.04 rootfs tree (mmdebstrap) |
| 5a | `scripts/build-device-package.sh` | `ubuntu-iceland-device_*.deb` from `packaging/` |
| 6 | `scripts/build-rootfs-overlay.sh` | firmware + anything the rootfs build cannot know |
| 7 | `scripts/build-rootfs-image.sh` | the ext4 `userdata` image (calls `make-initramfs.sh`) |
| 8 | `scripts/build-boot-bundle.sh` | `boot.img` + `init_boot.img` via Perpetua's `android-gki` — a separate step from the kernel build; run on its own it needs `INITRAMFS=` pointed at the rootfs's `initrd.img-<release>` |
| 9 | `scripts/build-release.sh` | one installable ZIP with a fastboot installer and a SHA-256 manifest |

Shared environment variables (same names as the gts9u port): `UBUNTU_WORKDIR`
(default `/srv/ubuntu-iceland`), `ROOTFS_DIR`, `KERNEL_OUT_DIR`,
`FIRMWARE_DIR`, `STOCK_DIR`, `RELEASE_VERSION`, `ICELAND_PROFILE`
(`minimal`/`desktop`), `ICELAND_USER`/`ICELAND_PW` (development images only).

## Repository layout

    scripts/      one script per build stage, orchestrated by build-release.sh
    kernel/       config fragments and the local patch series on top of pinned Perpetua
    configs/      firmware manifest, audio topology overlay, installer template
    packaging/    ubuntu-iceland-device: the board integration package
    docs/         boot strategy, hardware status (with evidence), porting log, per-subsystem plans
    tests/        checks that run against build artifacts
    artifacts/    released checksums and manifests, written by build-release.sh — none published yet, so the directory is not in the tree
    LICENSES/     the full text of every license used here

### Documentation

- [docs/porting-log.md](docs/porting-log.md) — the dated, evidence-first
  record of everything tried, including what did not work and why.
- [docs/bringup-plan.md](docs/bringup-plan.md) — the phase plan and the
  standing rules.
- [docs/boot-strategy.md](docs/boot-strategy.md), [docs/runbook.md](docs/runbook.md),
  [docs/stock-firmware.md](docs/stock-firmware.md), [docs/firmware-manifest.md](docs/firmware-manifest.md).
- Subsystem plans, each checked against the Fedora port:
  [audio](docs/audio-plan.md), [touch](docs/touch-plan.md),
  [Wi-Fi](docs/wifi-plan.md), [sensors](docs/sensors-plan.md),
  [media and the rest](docs/media-misc-plan.md),
  [Fedora parity audit](docs/fedora-parity-audit.md).
- [docs/upstreaming.md](docs/upstreaming.md) — what is being offered where.

## Kernel patches

`kernel/patches/` holds 62 patches (0001–0063, less the retired 0020) on top of the pinned Perpetua commit (`b7d639cfb282`, perpetua/v7.3, set in `scripts/fetch-perpetua.sh`); the
provenance of every one (ours, the Fedora iceland port's, infiniti-mainline's, Qualcomm's iris series carried through both)
is tabulated in [kernel/patches/README](kernel/patches/README). The rule is
that a local patch is a loan: it is either on its way upstream or marked
Ubuntu-specific with a reason.

### Upstreaming

The microphone fix (`0028`) corrected a Perpetua regression in the AudioReach
`q6apm` driver — a payload-size check that silently discarded every DSP
capture completion on this device. While this submission was being prepared
(2026-11-02) the Denial project landed the same fix for the capture path
(`9ba37ef1db70`), so that half was dropped at the kernel pin bump of
2026-11-03 (kernel #45 carries it from upstream); the remaining playback-path
half is carried as a one-line consistency patch, prepared on a branch and not
yet offered — no pull request or issue has been opened anywhere yet. The
ledger of everything carried here and where it is going is
[docs/upstreaming.md](docs/upstreaming.md).

Also carried on loan, each with its origin and exit condition in the ledger:
Qualcomm's kaanapali iris video series with the infiniti-mainline and Fedora
fixes (`0029`–`0036`, `0043`–`0055`, flashed with kernel #42), the nt36536 pen
series (`0037`–`0042`, `0063`, with the `0038` board DT), the Fedora port's
pen charger (`0056`–`0062`), and three userspace reports still to be filed —
PipeWire's second card object for an AudioReach compress node, WirePlumber
leaving a late-registering card without its UCM profile, and libwacom
rejecting SPI-attached tablets — each worked around in the device package.

## Licensing

Everything written for this port is **BSD-3-Clause** ([LICENSE](LICENSE));
the kernel patches take the license of the file they change — **GPL-2.0-only**
for drivers, **BSD-3-Clause** for the device-tree files (Qualcomm's SoC
include and the Denial project's board file carry that header). Files
derived from other projects keep their origin's license and say so in their
header:

| Path | License | Origin |
|---|---|---|
| `scripts/`, `configs/`, `packaging/`, `tests/`, `docs/` (default) | BSD-3-Clause | this port |
| `kernel/patches/*.patch` | GPL-2.0-only (drivers), BSD-3-Clause (the device-tree files), the one dt-binding (0059) dual GPL-2.0-only OR BSD-2-Clause as every kernel binding — each patch takes the license of the file it changes | this port, the Fedora iceland port (mzak), infiniti-mainline (Victor Fuentes), Qualcomm's kaanapali iris series (Vikash Garodia, Jingyi Wang, Wangao Wang, Vishnu Reddy) and Dmitry Baryshkov's iris fixes, carried through both — see the patch README |
| `scripts/build-mainline-kernel.sh`, `build-ubuntu-rootfs.sh`, `build-rootfs-image.sh`, `stage-firmware.py` | BSD-3-Clause, portions MIT | derived from agcarbajo/ubuntu-galaxy-tab-s9-ultra (MIT) |
| `configs/audio/topology/` | BSD-3-Clause (Linaro) | linux-msm/audioreach-topology, with the Fedora port's Pad 4 overlay under the same headers |
| `packaging/…/62-iceland-speakers.conf`, `62-iceland-speaker-raw.conf`, `iceland-speaker-default` | MIT | joonhoekim/tb323fu-linux, adapted via the Fedora iceland port |
| `packaging/…/alsa/ucm2/` | BSD-3-Clause | adapted from the Fedora iceland port's UCM2 profile |
| `packaging/…/iceland-pen`, `etc/iceland/pen.conf`, `74-iceland-pen.rules`, `etc/libwacom/oneplus-pad4.tablet` | BSD-3-Clause | this port — the pen bridge's protocol facts (the GATT characteristics, stock's acknowledgement values, the 0x7F/0x40 command family) were read from OnePlus's GPL-2.0 vendor driver and the stock logs as interface facts, never copied as code; the libwacom tablet definition is ours, written in libwacom's data-file format |
| `packaging/…/60-iceland-mic-processing.conf`, `61-iceland-mic-gain.conf`, `63-iceland-mic-raw.conf` | BSD-3-Clause | written for this package; the design and the measured values follow the Fedora iceland port's processed microphone (no license declared), credited in each file |

Full texts are in [LICENSES/](LICENSES/). One caveat is recorded honestly:
the Fedora iceland port (`mzakamin-hub/iceland-mainline`) declares no
repository-wide license; some of its files carry their own SPDX headers
(for example its bdaddr, provisioning and thermal helpers are
GPL-2.0-or-later), which govern those files, while the UCM profile and the
topology overlay we adapted carry none beyond Linaro's. The adapted pieces
carry attribution; the request to its author to state a license is drafted in
[docs/upstreaming.md](docs/upstreaming.md) and not yet sent. Its
kernel patches take the license of the file they change like any kernel
change — GPL-2.0-only for the driver and sound patches, BSD-3-Clause for the
board device-tree patches (0022–0024, 0061) — and carry the author's sign-off
where the original had one (0011 had none).

No proprietary firmware, stock partition image or device dump is, or ever will
be, committed here.

## Credits

- [DocLogix / the Denial project](https://github.com/denialwm) — the Perpetua
  kernel, the iceland device support and the boot tooling.
- [mzak](https://github.com/mzakamin-hub) — the Fedora iceland port: the TDM
  speaker chain, the touch and panel fixes, the pen's tablet capabilities, the
  MT5806 pen charger series, six of the iris fixes, the processed-microphone
  design, the firmware manifest cross-check.
- [Victor Fuentes](https://github.com/infiniti-mainline) — infiniti-mainline
  (OnePlus 15), the GPR patches, the carrier of Qualcomm's kaanapali iris
  (VPU) series and three of its fixes.
- [Joonhoe Kim](https://github.com/joonhoekim) — tb323fu-linux, the speaker
  protection chain.
- Vikash Garodia, Jingyi Wang, Wangao Wang and Vishnu Reddy (Qualcomm) and
  Dmitry Baryshkov — the kaanapali iris (VPU) series and its first fixes
  (0029–0036, 0046–0049), carried with their sign-offs.
- [Reixo](https://github.com/Reixo0) — the independent nx809j fix that
  confirmed 0028.
- [Arturo Gónzalez Carbajo](https://github.com/agcarbajo) — the
  ubuntu-galaxy-tab-s9-ultra port this project is structurally modeled on.
- Linaro — the AudioReach topology sources.
- The [Nura](https://nura.eco) (formerly postmarketOS) community — SoC
  mainlining and the device wiki.
