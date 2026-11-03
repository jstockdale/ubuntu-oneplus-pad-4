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
a Weston session with display, GPU, touch, Wi-Fi, speakers and microphones
working from its own storage.

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

Verified on this hardware by this port, as of 2026-11-02. Each ✅ has its
evidence in [docs/hardware-status.md](docs/hardware-status.md) and the dated
entry in [docs/porting-log.md](docs/porting-log.md); upstream claims never
earn a ✅ here.

| Component | Status | Notes |
|---|---:|---|
| Boot from own storage (A/B slot, `qbootctl`) | ✅ | power-on → Ubuntu, no PC; slot re-marked every boot |
| Display (dual-DSI NT36536, 3392×2400, 144 Hz) | ✅ | console and Wayland on glass; stock timings |
| GPU (Adreno 840, Mesa 26 / freedreno) | ✅ | OpenGL ES 3.2, GL-composited Weston |
| Touchscreen (10-point) | ✅ | auto-loads every boot, 30-minute soak clean |
| Stylus | 🟡 | registers; button and size properties missing |
| Backlight, buttons | ✅ | |
| Wi-Fi (WCN7860 / ath12k) | ✅ | auto-joins; ssh over the air |
| Bluetooth | 🟡 | controller up; pairing untested |
| USB gadget (serial console + network) | ✅ | the fallback access path |
| Speakers (6× TFA9865) | ✅ | stock loudness behind a PipeWire protection chain |
| Microphones | ✅ | kernel patch 0028 (see [Upstreaming](#upstreaming)) |
| Wired headphones | 🟡 | path starts then stops; untested with a headset |
| Battery telemetry, charging | ✅ | fast charge (SuperVOOC) not verified |
| Thermal | 🟡 | zones registered; no policy daemon yet |
| Sensors / IMU | ❓ | planned ([docs/sensors-plan.md](docs/sensors-plan.md)) |
| Suspend / resume | ❓ | deliberately untested so far |
| Video decode (VPU), cameras | ❓ | planned ([docs/media-misc-plan.md](docs/media-misc-plan.md)) |
| GNOME on Wayland, Waydroid | ❓ | next phases |
| Haptics, GNSS, cellular, fingerprint, microSD | — | not fitted on this device |

## How it boots

The long version, with every invariant, is
[docs/boot-strategy.md](docs/boot-strategy.md).

- The stock bootloader chain is kept. Perpetua builds the iceland device
  tree **into** the kernel image and swaps it in at boot (`ARM64_FDT_HANDOFF`),
  so `vendor_boot`, `dtbo` and `vbmeta` are **never written**.
- `boot.img` and `init_boot.img` are repacked from the owner's **own stock
  images** with Perpetua's `devices/boot/android-gki`, which keeps the stock
  v4 headers and AVB properties. Our initramfs rides inside the boot image so
  that a kernel can be test-flown with `fastboot boot` before it is flashed.
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
| 8 | `scripts/build-boot-bundle.sh` | `boot.img` + `init_boot.img` via Perpetua's `android-gki` |
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
    artifacts/    released checksums and manifests (none published yet)
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

`kernel/patches/` holds 28 patches on top of the pinned Perpetua commit; the
provenance of every one (ours, the Fedora iceland port's, infiniti-mainline's)
is tabulated in [kernel/patches/README](kernel/patches/README). The rule is
that a local patch is a loan: it is either on its way upstream or marked
Ubuntu-specific with a reason.

### Upstreaming

The microphone fix (`0028`) corrects a Perpetua regression in the AudioReach
`q6apm` driver — a payload-size check that silently discarded every DSP
capture completion on this device. While this submission was being prepared
(2026-11-02) the Denial project landed the same fix for the capture path
(`9ba37ef1db70`), so that half is dropped at the next kernel pin bump; the
remaining playback-path half is offered as a small consistency patch. The
ledger of everything carried here and where it is going is
[docs/upstreaming.md](docs/upstreaming.md).

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
| `kernel/patches/*.patch` | GPL-2.0-only (drivers), BSD-3-Clause (the device-tree files) — each patch takes the license of the file it changes | this port, the Fedora iceland port (mzak), infiniti-mainline (Victor Fuentes) — see the patch README |
| `scripts/build-mainline-kernel.sh`, `build-ubuntu-rootfs.sh`, `build-rootfs-image.sh`, `stage-firmware.py` | BSD-3-Clause, portions MIT | derived from agcarbajo/ubuntu-galaxy-tab-s9-ultra (MIT) |
| `configs/audio/topology/` | BSD-3-Clause (Linaro) | linux-msm/audioreach-topology, with the Fedora port's Pad 4 overlay under the same headers |
| `packaging/…/62-iceland-speakers.conf`, `62-iceland-speaker-raw.conf`, `iceland-speaker-default` | MIT | joonhoekim/tb323fu-linux, adapted via the Fedora iceland port |
| `packaging/…/alsa/ucm2/` | BSD-3-Clause | adapted from the Fedora iceland port's UCM2 profile |

Full texts are in [LICENSES/](LICENSES/). One caveat is recorded honestly:
the Fedora iceland port (`mzakamin-hub/iceland-mainline`) declares no
repository-wide license; some of its files carry their own SPDX headers
(for example its bdaddr, provisioning and thermal helpers are
GPL-2.0-or-later), which govern those files, while the UCM profile and the
topology overlay we adapted carry none beyond Linaro's. The adapted pieces
carry attribution and we are asking its author to state a license. Its
kernel patches are GPL-2.0 like any kernel change and carry the author's
sign-off.

No proprietary firmware, stock partition image or device dump is, or ever will
be, committed here.

## Credits

- [DocLogix / the Denial project](https://github.com/denialwm) — the Perpetua
  kernel, the iceland device support and the boot tooling.
- [mzak](https://github.com/mzakamin-hub) — the Fedora iceland port: the TDM
  speaker chain, the touch and panel fixes, the firmware manifest cross-check.
- [Victor Fuentes](https://github.com/infiniti-mainline) — infiniti-mainline
  (OnePlus 15), the GPR patches.
- [Joonhoe Kim](https://github.com/joonhoekim) — tb323fu-linux, the speaker
  protection chain.
- [Reixo](https://github.com/Reixo0) — the independent nx809j fix that
  confirmed 0028.
- [Arturo Gónzalez Carbajo](https://github.com/agcarbajo) — the
  ubuntu-galaxy-tab-s9-ultra port this project is structurally modeled on.
- Linaro — the AudioReach topology sources.
- The [Nura](https://nura.eco) (formerly postmarketOS) community — SoC
  mainlining and the device wiki.
