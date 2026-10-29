# Boot chain, installation and recovery

Last revised: 2026-10-29. Nothing in this document has been exercised on
hardware by this port yet; it inherits the chain the Perpetua kernel documents
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
is unpacked over it. **UNVERIFIED** but expected to be benign: our archive
owns `/init`, and later archive members win on path conflicts. Two rules
follow:

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
   in the release provenance (**UNVERIFIED**: the exact product string is
   recorded the first time `stage-stock-images.sh` sees a real OTA, and the
   installer refuses to run before one is recorded).
2. `fastboot getvar current-slot` — flash `boot_<slot>` and `init_boot_<slot>`
   of the **current** slot only.
3. `fastboot flash userdata` with the rootfs image (sparse-chunked with
   `-S 256M`; **UNVERIFIED** that this ABL accepts it — the fallback is
   writing from a booted initramfs over USB).
4. `fastboot reboot`. Nothing else: no `set_active`, no erase, no other
   partition, no `--disable-verity`, no vbmeta.

Where this ABL permits it, `fastboot boot` (one-shot boot from RAM,
**UNVERIFIED** on iceland) is the smoke test to run before the first real
flash of any new kernel. It takes a different image than the flashable pair:
`fastboot boot` does not read the flashed `init_boot`, so the test image must
carry kernel **and** initramfs together — `scripts/make-test-bootimg.sh`
builds exactly that (and must never be flashed).

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
- **Never flash `vbmeta`, `dtbo`, `vendor_boot`, or any bootloader/firmware
  partition.** This chain does not need it, and those writes are the ones a
  stock reflash cannot always undo.

## Open assumptions (each blocks a ✅ somewhere)

| # | Assumption | How it gets verified |
|---|---|---|
| 1 | Stock vendor-ramdisk prepended to our initramfs is benign | first boot: initramfs logs the pre-existing tree |
| 2 | `fastboot flash userdata <raw ext4>` works on this ABL | attempt on hardware; fallback documented above |
| 3 | `fastboot boot` is permitted by this ABL | attempt before the first real flash |
| 4 | Stock `init_boot` is large enough for an Ubuntu initramfs | `android-gki` hard-fails on size; `make-initramfs.sh` prints the margin |
| 5 | Product string for the installer gate | recorded by `stage-stock-images.sh` from the OTA metadata |
| 6 | Firmware file list under `qcom/kaanapali/iceland/` | `stage-firmware.py record` + dmesg firmware requests on first boots |
