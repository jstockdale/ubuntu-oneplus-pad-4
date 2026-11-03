#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Install Ubuntu on the OnePlus Pad 4 (iceland) over fastboot.
#
# Shipped inside the release ZIP next to the images it flashes.  It flashes
# exactly three partitions — boot and init_boot on the CURRENT slot, and
# userdata — and refuses everything else.  It never switches slots, never
# touches vbmeta/dtbo/vendor_boot, and never erases anything.
#
# ⚠ Writing userdata erases everything Android kept there (apps, settings,
# files).  Android's system itself is untouched; booting back into Android
# later will make Android re-initialise userdata, i.e. remove Ubuntu.
# Back up first.  You need an unlocked bootloader.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# EXPECTED-PRODUCT is the fastboot product string, stamped by the release
# build from configs/install/expected-fastboot-product.  Note it is NOT the
# OTA metadata's product (OPD2514): this bootloader reports the platform
# name, "canoe" (per the iceland-mainline project; to be confirmed on our
# own unit).  The gate fails closed: no file, no flashing.
expected_product_file=$here/EXPECTED-PRODUCT

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v fastboot >/dev/null || die 'fastboot is not installed'
for f in boot.img init_boot.img ubuntu-iceland-userdata.img SHA256SUMS; do
	test -f "$here/$f" || die "missing $f next to this script"
done
test -f "$expected_product_file" || \
	die 'this bundle carries no EXPECTED-PRODUCT; it was not built from a
       stock OTA staging and must not be flashed'
expected_product=$(tr -d '[:space:]' < "$expected_product_file")

say 'verifying the bundle checksums'
(cd "$here" && sha256sum -c SHA256SUMS >/dev/null) || \
	die 'checksum mismatch; the download is corrupt'

say 'waiting for a device in fastboot mode (adb reboot bootloader)'
fastboot getvar product >/dev/null 2>&1 || fastboot wait-for-device

product=$(fastboot getvar product 2>&1 | sed -n 's/^product:[[:space:]]*//p')
[ -n "$product" ] || die 'could not read the product variable'
if [ "$product" != "$expected_product" ]; then
	die "this is '$product', the bundle is for '$expected_product'; refusing"
fi

unlocked=$(fastboot getvar unlocked 2>&1 | sed -n 's/^unlocked:[[:space:]]*//p')
case "$unlocked" in
	yes) ;;
	*) die "the bootloader does not report unlocked (got '$unlocked')" ;;
esac

slot=$(fastboot getvar current-slot 2>&1 | sed -n 's/^current-slot:[[:space:]]*//p')
case "$slot" in
	a|b) ;;
	*) die "could not determine the current slot (got '$slot')" ;;
esac
say "current slot: $slot (this installer never switches slots)"

say ''
say 'About to flash, on the CURRENT slot only:'
say "  boot_$slot       <- boot.img (Perpetua kernel, DTB built in)"
say "  init_boot_$slot  <- init_boot.img (Ubuntu initramfs)"
say '  userdata         <- ubuntu-iceland-userdata.img (ERASES Android data)'
say ''
printf 'Type exactly "flash iceland" to continue: '
read -r answer
[ "$answer" = 'flash iceland' ] || die 'aborted'

fastboot flash "boot_$slot" "$here/boot.img"
fastboot flash "init_boot_$slot" "$here/init_boot.img"
# -S 256M: the raw ext4 image is larger than the download buffer; fastboot
# splits it into sparse chunks the bootloader reassembles.
fastboot flash -S 256M userdata "$here/ubuntu-iceland-userdata.img"

say ''
say 'done; rebooting.  First boot grows the filesystem and starts the GNOME'
say 'first-boot wizard (or SSH, for a minimal/development image).'
say 'To return to stock: reflash the stock boot.img/init_boot.img from your'
say 'OTA package the same way, then let Android factory-reset userdata.'
fastboot reboot
