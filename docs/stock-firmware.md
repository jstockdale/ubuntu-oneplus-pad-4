# Getting the stock firmware (and why the build needs it)

Last revised: 2026-10-29.

The port needs the owner's stock firmware for three separate jobs:

1. **Boot-image templates.** `android-gki` rebuilds our `boot.img` /
   `init_boot.img` *from the stock ones*, keeping their v4 headers, partition
   sizes and AVB properties. No stock images, no flashable bundle.
2. **Proprietary blobs.** Everything under
   `/lib/firmware/qcom/kaanapali/iceland/` plus the ath12k Wi-Fi firmware
   comes out of the stock `vendor`/`odm` EROFS images via
   `stage-firmware.py`.
3. **The way back.** Reflashing the stock `boot.img`/`init_boot.img` is the
   entire recovery story on a device with no usable EDL.

The package must match the **installed** build: update the tablet to the
newest available build first, then obtain that same build's full OTA, then
stop updating until the next deliberate re-stage. `stage-stock-images.sh`
records the post-build fingerprint and the installer refuses a mismatch.

## Where to get the full OTA

In order of preference:

1. **Oxygen Updater** (oxygenupdater.com, app on the tablet itself): fetches
   official full-OTA URLs straight from OnePlus's update servers. Check that
   the Pad 4 (OPD2514) is in its device list; its "advanced mode" shows the
   raw download URL so the zip can be pulled on the build host. Rollback
   packages listed on their site are **not** what we want — we want the
   current full stable OTA.
2. **The tablet's own updater cache**: during a system update the full zip
   passes through the device; community guides describe capturing it. Only
   works while an update is pending.
3. **Community mirrors** (oxygenupdater.com articles, XDA threads): fine as a
   convenience, but verify what you got — `stage-stock-images.sh` reads the
   `post-build` fingerprint from inside the zip and will tell you exactly
   what it is. Never flash anything from a mirror directly; this port only
   ever flashes images *derived* from the zip via the pinned pipeline.

Requirements on the zip: a **full** OTA (incrementals have no complete
`payload.bin` partitions and are rejected), for your unit's region/variant
(DocLogix's unit was the India "iceland-O IN" build; the fingerprint will
say).

## Plan B: no OTA obtainable — dump from the device

If no full OTA for the installed build can be found, the device itself is the
source, after the bootloader is unlocked:

1. Build a **rescue boot image from scratch** with `mkbootimg` (header v4,
   our kernel + our initramfs *together* in one image — a RAM boot does not
   need the flash layout) and start it with `fastboot boot`, which writes
   nothing.
2. From the booted initramfs/SSH, read the partitions by name
   (`/dev/block/by-name/boot_<slot>`, `init_boot_<slot>`, `vendor_a`,
   `odm_a`, …) with `dd`, pull them to the host, and feed them to
   `stage-firmware.py` (it takes partition images; the templates are the
   dumped `boot`/`init_boot`).

Caveat: plan B depends on our kernel booting with USB working before we have
the firmware staged — the GPU/Wi-Fi blobs are not needed for a USB-gadget
rescue boot, which is what makes this viable. It has not been exercised yet
(boot-strategy.md assumptions 1 and 3 gate it).
