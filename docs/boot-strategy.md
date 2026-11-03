# Boot chain, installation and recovery

Last revised: 2026-11-03. The chain below has been exercised on hardware by
this port since 2026-10-30 — Phase A's 18 RAM-boot flights to an interactive
initramfs, Phase B's flash of `boot_b` on 2026-10-31 (power-on to Ubuntu with
no PC), and six kernel flashes to `boot_b` since, the last build #45 on
2026-11-03; it inherits the chain the Perpetua kernel documents
and ships tooling for (`devices/README` and `devices/boot/android-gki` in
[denialwm/linux-perpetua](https://github.com/denialwm/linux-perpetua)), which
is the chain the Denial project's own OnePlus Pad 4 runs. Every claim below
that is still an assumption is marked **UNVERIFIED** and listed again at the
end; each gets removed only when the porting log records the observation.

## The chain

- The OPD2514 is an A/B device with a standard Qualcomm ABL: `fastboot` and
  `fastbootd` exist, and the GKI (Android 13+) boot layout applies: the kernel
  lives alone in `boot`, the generic ramdisk alone in `init_boot`, and the
  DTB, kernel cmdline and bootconfig come from `vendor_boot`.
- Perpetua inverts the usual DTB problem: the device tree is **built into the
  kernel** (`CONFIG_BUILTIN_DTB_NAME="qcom/kaanapali-oneplus-iceland"`) and
  `ARM64_FDT_HANDOFF` replaces the bootloader-supplied tree at boot, carrying
  over only what the bootloader owns (memory map, initrd location). The DTS's
  `/chosen/fdt-handoff` node names the stock tree it may replace
  (`qcom,canoe`, model `"... Canoe MTP,iceland-O IN"`), so the kernel refuses
  to hand off on a tree that is not this device's.
- Consequence, and the single biggest simplification over the Samsung port:
  **`vendor_boot`, `dtbo` and `vbmeta` are never rewritten.** Changing the DTS
  means rebuilding the kernel image, nothing else.
- `devices/boot/android-gki` writes our two images from the owner's **stock**
  `boot.img`/`init_boot.img`: the stock v4 header, partition size, AVB salt
  and AVB properties are kept, only the payload changes, and the image gets
  the same unsigned AVB hash footer stock GKI images carry. An unlocked
  bootloader accepts that. This is why the stock OTA package is a build input
  and not just a backup.

### The initrd concatenation

In the GKI layout ABL hands the kernel a concatenation: the `vendor_boot`
vendor-ramdisk fragments first, then the `init_boot` generic ramdisk. We leave
`vendor_boot` stock, so Android's vendor ramdisk (early-mount configuration,
vendor kernel modules) is unpacked into our initramfs root before our archive
is unpacked over it. VERIFIED 2026-10-30, and not benign as first expected:
our archive owns `/init`, and later archive members do win on path conflicts
— except that a later symlink cannot replace an earlier non-empty directory
(`init/initramfs.c` ignores the rmdir failure), so the vendor ramdisk's real
`lib/` silently beat our usr-merge `lib -> usr/lib` link and every dynamic
executable failed on the loader. `scripts/repack-initramfs.py` (shared by
`make-initramfs.sh` and the diag builder) now ships `lib/` as a real directory
carrying loader symlinks that resolve through `usr/lib`, merging over the
vendor's instead of fighting it. Two rules follow:

- Our initramfs must use the compression the stock chain uses, **LZ4 legacy**
  (the gts9u port physically established that a gzip generic ramdisk after an
  LZ4 vendor fragment makes Linux reject the initrd). `make-initramfs.sh`
  enforces the magic.
- Nothing in our initramfs may depend on a path the vendor ramdisk also ships;
  a diagnostic in the initramfs should log what the vendor fragment left
  behind the first time we boot one.

### Root filesystem discovery

The kernel cmdline lives in stock `vendor_boot` and therefore contains no
`root=`. The Ubuntu initramfs instead carries
`/conf/conf.d/iceland-root` (shipped as
`/etc/initramfs-tools/conf.d/iceland-root` by the `ubuntu-iceland-device`
package), which sets `ROOT=LABEL=UBPAD4_ROOT`. initramfs-tools sources
`conf.d` before parsing the cmdline, and a cmdline that never says `root=`
leaves the conf.d value in force. The root filesystem is found by label, never
by device name: UFS LUN enumeration order is not a contract.

### The root filesystem lives in `userdata`

Like the gts9u UFS install: a bare ext4 filesystem (no partition table)
written into the existing `userdata` partition. ABL reads no filesystems, so
nothing on the device ever creates, moves or deletes a partition and the GPT
stays exactly as OnePlus shipped it. `/boot` stays inside the root filesystem;
it is content for humans and `update-initramfs`, not for the bootloader. The
image ships small and the first boot grows it to the whole partition
(`ubuntu-iceland-grow-rootfs.service`; the filesystem is created with enough
reserved descriptor blocks for an online resize to any iceland storage size).

Writing `userdata` destroys everything Android kept there. Android itself (in
`super`) is untouched, but booting Android again means Android reformatting
`userdata` — single boot is the phase-1 deal. Dual boot, when it comes,
follows the gts9u userdata-split model, **never** slot switching.

## Installation (what the release ZIP's installer does, and all it does)

1. `fastboot getvar product` — refuse unless it matches the product recorded
   in the release provenance (the product string is `canoe` — the platform
   name the ABL reports, not the OTA metadata's OPD2514 — carried as the repo
   constant `configs/install/expected-fastboot-product` and confirmed on the
   owner's unit at first fastboot contact, 2026-10-29; the installer refuses
   to run without the EXPECTED-PRODUCT file the release build stamps from it).
2. `fastboot getvar current-slot` — flash `boot_<slot>` and `init_boot_<slot>`
   of the **current** slot only.
3. `fastboot flash userdata` with the rootfs image (sparse-chunked with
   `-S 256M`). The rootfs has booted from `userdata` since Phase B
   (2026-10-31; 453 GB ext4, grown on the first boot), so the write is proven
   on this unit; the porting log did not record the command line, and the
   installer script has not run end to end yet (no release ZIP has been
   built), so the sibling ports' sparse-flash report still stands behind
   `-S 256M` — the fallback remains writing from a booted initramfs over USB.
4. `fastboot reboot`. Nothing else: no `set_active`, no erase, no other
   partition, no `--disable-verity`, no vbmeta.

Kernel updates on the installed tablet write less still: `fastboot flash
boot_b` with the new bundle's `boot.img` only — `init_boot_b` stays unless the
initramfs changed, `userdata` never — always after a RAM boot of the same file
(six times so far, #31 through #45), each followed by the lock-in check:
`boot_b` sha256 equals the bundle, `boot_a` 1f11e2c6… untouched, slot _b
bootable + successful, `qbootctl` active.

`fastboot boot` (one-shot boot from RAM) is permitted by this ABL — verified
2026-10-30, and the gate every kernel has passed before its flash since — but
it works the other way round from the AOSP expectation: the ABL ignores
whatever ramdisk the downloaded image carries and always pairs the downloaded
kernel with the FLASHED `init_boot` + vendor ramdisk (control pair,
2026-10-30: a stock kernel carrying our ramdisk booted Android untouched). So
the smoke test is `fastboot boot` of the bundle's own `boot.img` (kernel with
built-in DTB) over the installed `init_boot_b`, and the kernel+initramfs image
of `scripts/make-test-bootimg.sh` is retired on this device — its initramfs
never flies.

## Requirements

1. **An unlocked bootloader** — Developer options → OEM unlocking, then
   `fastboot flashing unlock` (wipes the device). The Denial project calls
   this device "particularly easy to unlock"; the CN/ColorOS variant instead
   goes through OnePlus's approval-and-quota process.
2. **The stock OTA package matching the installed firmware** — the source of
   the `boot.img`/`init_boot.img` templates, the proprietary firmware, and
   the recovery path.

## Recovery

- A kernel that does not boot: hold Power+VolDown for the bootloader, reflash
  the stock `boot.img`/`init_boot.img` from the OTA dump. Routine and safe —
  the Android system was never touched.
- EDL (Qualcomm 9008): there is **no public Firehose loader** for this device
  and no service outside China/India. Treat EDL as unrecoverable. The only
  documented way a Pad 4 reached EDL was activating the empty B slot of a
  never-updated unit; the installer and these documents exist so that nothing
  this port does can reproduce that.

Two invariants that cannot be touched:

- **Never `fastboot set_active`.** On a unit that has never taken an OTA the
  other slot is empty and activating it ends in EDL.
- **Never flash `vbmeta`, `dtbo`, `vendor_boot`, the partition table, or any
  bootloader/firmware partition — and never EDL.** This chain does not need
  it, and those writes are the ones a
  stock reflash cannot always undo.

## Open assumptions (each blocks a ✅ somewhere)

| # | Assumption | How it gets verified |
|---|---|---|
| 1 | ~~Stock vendor-ramdisk prepended to our initramfs is benign~~ **REVISED 2026-10-30**: this ABL IGNORES the downloaded boot image's ramdisk on `fastboot boot` and always uses flashed init_boot + vendor ramdisk (proven: a stock-kernel image carrying our ramdisk booted Android untouched). RAM-boot attempts 1–7 therefore flew our kernel with ANDROID's ramdisk; Android init on a mainline kernel calls reboot() within ~5 s — the constant early reset. The LZ4-chain rule below still governs the FLASHED path: vendor ramdisk (LZ4-legacy) + our archive must chain as LZ4 frames, so `make-initramfs.sh` repacks to a single LZ4-legacy frame | Done — Phase A flight 18, 2026-10-30: interactive initramfs over the flashed init_boot_b, FDT handoff engaged (model "OnePlus Pad 4"), all six UFS LUNs; the `lib/` directory rule above was the last fix on the way |
| 2 | ~~`fastboot flash userdata <raw ext4>` works on this ABL~~ **CLOSED 2026-10-31**: the rootfs image is on `userdata` and boots (Phase B; 453 GB ext4, grown on first boot); the installer script itself is still unexercised — no release ZIP built yet | — |
| 3 | ~~`fastboot boot` is permitted by this ABL~~ **CLOSED 2026-10-30**: permitted, and the RAM-boot gate every flashed kernel has passed since — with row 1's caveat that the downloaded ramdisk is ignored | — |
| 4 | ~~Stock `init_boot` is large enough for an Ubuntu initramfs~~ **CLOSED 2026-10-29**: 8.4 MB budget; the trimmed archive is 2.53 MB (5.9 MB margin), `MODULES=most` (17.3 MB) does not fit | — |
| 5 | ~~Product string for the installer gate~~ **CLOSED 2026-10-29**: `canoe` on the owner's unit (`fastboot getvar product`), carried as the repo constant `configs/install/expected-fastboot-product` — not read from the OTA metadata, whose product (OPD2514) is a different namespace | — |
| 6 | Firmware file list under `qcom/kaanapali/iceland/` — **status 2026-11-03**: recorded (`configs/firmware/iceland.toml`, 28 files hash-verified against the owner's OTA on 2026-10-29) and running — ADSP/CDSP/VPU, Wi-Fi (ath12k, since 2026-11-01), touch, GPU zap; the GPU SQE/GMU/AQE set, the BT `brh*` files and the built audio topology are staged outside the TOML and documented in docs/firmware-manifest.md. Still open: the sensor-hub tree and the SpeakerBoost ACDB | dmesg firmware requests on every new kernel |

## Alternatives considered (reviewed 2026-10-30, agents' deep reads of all three sibling ports)

Three independent Linux ports exist for iceland. Verdicts for our port:

| Approach | Boot chain | Writes | Verdict for us |
|---|---|---|---|
| **Perpetua (Arch)** — ours | stock ABL → repacked GKI boot_b (DTB-in-Image, FDT handoff) → init_boot_b ramdisk → ext4 on userdata | boot_b, init_boot_b, userdata only; stock GPT untouched | **Keep.** Safe-by-construction; proven on this device; our scaffolding is built for it |
| **Fedora (mzakamin-hub)** — U-Boot EFI | stock ABL → U-Boot in boot_b (Android-image-wrapped) → blkmap → shim/GRUB → EFI from a GPT disk image inside userdata | boot_b, userdata (dual-boot variant edits GPT — out of scope) | **Phase-2 candidate** for the kernel-update problem (apt upgrade + GRUB trial-boot + btrfs rollback vs our repack-and-reflash); not for first light. Their kernel patch queue (display splash handover, audio, sensors, thermal) is our adoption mine regardless |
| **SuperTurtleDev (Ubuntu)** — EDK2 BootApp | patched-ABL/SuperFb BDS (gbl_root_canoe lineage, efisp-resident) → BootApp.efi → kernel/dtb/bootcfg/initrd from NEW GPT partitions | **deletes super+userdata, rewrites GPT**, creates 6 partitions; installed chain likely depends on a raw efisp write + GBL-vulnerable ABL | **Avoid the architecture entirely** (violates every brick rail; build-verified only, never run on hardware). But their netdeploy tooling is liftable: deployd/deployclient/makeblob (MIT, ~500 lines total) stream a CRC-framed Android-sparse rootfs over a USB-NCM gadget straight onto any block device, memory-bounded — pointable at userdata with no GPT change. Their ALSA UCM + sensors debs and bare-ext4+sparse image pipeline are also liftable |

Shared lineage note: both alternatives build on map220v/sm8850-mainline's
iceland DTS — the same ancestry as Perpetua — so kernel-side fixes port
between all three trees with modest effort.
