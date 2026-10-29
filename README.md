# Ubuntu 26.04 LTS for the OnePlus Pad 4

Ubuntu 26.04 LTS arm64 for the OnePlus Pad 4 (`OPD2514`, codename `iceland`),
running GNOME on Wayland on the [Perpetua](https://github.com/denialwm/linux-perpetua)
mainline kernel (upstream Linux 7.3 plus the iceland device support).

This port is modeled on
[agcarbajo/ubuntu-galaxy-tab-s9-ultra](https://github.com/agcarbajo/ubuntu-galaxy-tab-s9-ultra)
so that the family of ports stays structurally identical: the same stage
scripts, the same environment variables, the same artifact layout, the same
documentation discipline. Where this device allows something simpler, this
port diverges and [docs/boot-strategy.md](docs/boot-strategy.md) records why.

## Status

Nothing in this table has been validated on hardware by this port yet. The
"expected" column is what the Perpetua kernel and the Denial project's device
matrix claim for iceland; each row moves to ✅ only with evidence recorded in
[docs/hardware-status.md](docs/hardware-status.md).

| Component | Status | Expected (upstream claims) |
|---|---:|---|
| Display | ❓ | 13.2″ 3392×2400 dual-DSI NT36536, 144 Hz |
| Desktop | ❓ | GNOME on Wayland and GDM |
| GPU | ❓ | Adreno 840 via freedreno, Mesa 26 |
| Touchscreen | ❓ | NT36536 over SPI, multitouch |
| Wi-Fi | ❓ | WCN7860 / ath12k (PCIe) |
| Bluetooth | ❓ | WCN7860 |
| Speakers | ❓ | 6× TFA9865, WCD9395 codec |
| Microphones | ❓ | Not yet supported in the kernel |
| Cameras | ❓ | CAMSS bringup in progress upstream (Oct 2026) |
| Battery telemetry | ❓ | oplus pmic-glink battery manager |
| SuperVOOC charging | ❓ | Listed working by the Denial port |
| USB host / OTG | ❓ | |
| USB-C DisplayPort | ❓ | In the kernel since Sep 2026 ("Add DisplayPort to Kaanapali") |
| Suspend / resume | ❓ | Works at SoC level per Nura wiki |
| Sensors | ❓ | Unknown; not in the iceland DTS yet |
| Stylus | ❓ | Unknown |
| Waydroid | ❓ | Planned for phase 1 (binder enabled in our kernel fragment) |
| Fingerprint | — | No fingerprint hardware on this device |
| Modem / mobile data | — | Wi-Fi-only device |
| microSD | — | No card slot on this device |

## How this port boots

Short version (the long version with every invariant is
[docs/boot-strategy.md](docs/boot-strategy.md)):

- The stock bootloader chain is kept. Perpetua builds the iceland device tree
  **into** the kernel image and swaps it in at boot (`ARM64_FDT_HANDOFF`), so
  `vendor_boot`, `dtbo` and `vbmeta` are **never flashed**.
- `boot.img` (kernel) and `init_boot.img` (Ubuntu initramfs) are repacked from
  the owner's **own stock images** with Perpetua's `devices/boot/android-gki`,
  which preserves the stock v4 headers and AVB properties.
- The root filesystem is an ext4 image written to `userdata`, found by the
  initramfs by label (`LABEL=UBPAD4_ROOT`); the first boot grows it to the
  whole partition.
- Everything is flashed over **fastboot on the active slot**. The installer
  never switches slots and never touches any other partition.

## Building

Each stage is a separate script that can be run on its own; `build-release.sh`
only fixes the order and the data flow between them. Nothing here flashes a
device. Run `scripts/check-build-deps.sh` first.

| Stage | Script | Produces |
|---|---|---|
| 0 | `scripts/check-build-deps.sh` | a report of missing host tools |
| 1 | `scripts/fetch-perpetua.sh` | the pinned Perpetua kernel checkout |
| 2 | `scripts/build-mainline-kernel.sh` | `Image` (DTB built in), modules, config |
| 3 | `scripts/stage-stock-images.sh` | stock `boot.img`/`init_boot.img` templates + provenance, from the owner's OTA package |
| 4 | `scripts/stage-firmware.py` | the verified proprietary firmware staging + `PROVENANCE.json` |
| 5 | `scripts/build-ubuntu-rootfs.sh` | the Ubuntu 26.04 rootfs tree (mmdebstrap, one invocation) |
| 6 | `scripts/build-rootfs-overlay.sh` | firmware + anything the rootfs build cannot know |
| 7 | `scripts/build-rootfs-image.sh` | the ext4 `userdata` image (calls `make-initramfs.sh`) |
| 8 | `scripts/build-boot-bundle.sh` | `boot.img` + `init_boot.img` via Perpetua's `android-gki` |
| 9 | `scripts/build-release.sh` | one installable ZIP with a fastboot installer and a SHA-256 manifest |

Shared environment variables (same names as the gts9u port): `UBUNTU_WORKDIR`
(default `/root/ubuntu-iceland`), `ROOTFS_DIR`, `KERNEL_OUT_DIR`,
`FIRMWARE_DIR`, `STOCK_DIR`, `RELEASE_VERSION`, `ICELAND_PROFILE`
(`minimal`/`desktop`), `ICELAND_USER`/`ICELAND_PW` (development images only).

## Repository layout

    scripts/      one script per build stage, orchestrated by build-release.sh
    kernel/       config fragments and local patches on top of pinned Perpetua
    configs/      firmware manifest, installer template
    packaging/    ubuntu-iceland-device and future device packages
    docs/         boot strategy, hardware status (with evidence), porting log
    tests/        checks that run against build artifacts
    artifacts/    released checksums and manifests (committed)
    work/         scratch (ignored)

## ⚠️ Safety

This device family has **no public EDL/Firehose loader** and is not serviced
outside China/India. The one documented Pad 4 brick happened by switching to
the never-populated B slot. The rules, enforced by the installer and repeated
in every flashing document:

1. Never `fastboot set_active`.
2. Flash only `boot`, `init_boot` and `userdata`, on the active slot.
3. Keep the stock OTA package; its `boot.img`/`init_boot.img` are both the
   repack templates and the way back.

## Credits

- [Arturo Gónzalez Carbajo](https://github.com/agcarbajo) — the
  ubuntu-galaxy-tab-s9-ultra port this project is structurally modeled on.
- [DocLogix / the Denial project](https://github.com/denialwm) — the Perpetua
  kernel and the iceland device support.
- The [Nura](https://nura.eco) (formerly postmarketOS) community — SoC
  mainlining and the device wiki.
