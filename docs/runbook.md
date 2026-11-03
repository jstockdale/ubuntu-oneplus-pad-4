# Runbook: from zero to Ubuntu on the dev unit

Last revised: 2026-10-29. This is the bench document: every command in order,
with what success looks like and what to do when it isn't. It assumes the
repo is at `~/projects/ubuntu-oneplus-pad-4` and nothing has been run yet.

Phases 1–2 need no tablet and no OTA. Phase 5 is the first hardware contact
and writes nothing. Flashing happens only in phase 7.

## 0. What you need

- The Pad 4 dev unit, charged, and a **data-capable** USB-C cable.
- A **USB-C hub + USB keyboard** for the tablet: the minimal image's login
  path is the framebuffer console, and headless Wi-Fi joining is misery.
- A Linux build host with root access and ~60 GB free (kernel tree ~6 GB,
  rootfs ~10 GB, images and scratch on top).
- Accepted up front: **unlocking wipes the tablet** (phase 3), **flashing
  userdata erases Android's data** (phase 7), and phase 1 is single-boot —
  returning to Android later means Android re-initialising userdata.
- The safety rules, which every tool here enforces but you should know cold:
  never `fastboot set_active`; never flash vbmeta/dtbo/vendor_boot; keep the
  stock OTA zip forever.

## 1. Build host setup

```bash
cd ~/projects/ubuntu-oneplus-pad-4
bash scripts/check-build-deps.sh
```

Install what it reports. On an Ubuntu/Debian host that is roughly:

```bash
sudo apt install git clang lld llvm make flex bison bc device-tree-compiler \
    mmdebstrap qemu-user-static binfmt-support debootstrap unzip \
    erofs-utils python3 mkbootimg lz4 cpio e2fsprogs zstd xz-utils zip \
    android-sdk-platform-tools
```

- `avbtool`: no apt or PyPI package exists (verified on resolute, 2026-10).
  It is a self-contained script in AOSP:

  ```bash
  git clone --depth 1 https://android.googlesource.com/platform/external/avb /tmp/aosp-avb
  sudo install -m 0755 /tmp/aosp-avb/avbtool.py /usr/local/bin/avbtool
  ```

- `payload-dumper-go`: grab the linux-amd64 release from
  github.com/ssut/payload-dumper-go, put the binary in `/usr/local/bin`.

Re-run `check-build-deps.sh` until it says everything is present, including
the `binfmt qemu-aarch64 registered` line — without it the rootfs stage
cannot run arm64 maintainer scripts.

Privileges are split by stage. The workdir `/srv/ubuntu-iceland` is
user-owned so that both the owner and Claude's sandboxed shell can run and
verify the root-free stages — fetch/kernel, stock staging, firmware
overlay, boot bundle, test image — as an ordinary user. Only three stages
genuinely need root and are run with plain `sudo bash scripts/...`:
`build-ubuntu-rootfs.sh` (mmdebstrap + chroots), `make-initramfs.sh`
(chroot) and `build-rootfs-image.sh` (loop mount). In-image file ownership
does not depend on who built the inputs: modules and firmware are forced
to root at the two merge points.

## 2. Kernel (no tablet, no OTA needed — do this today)

```bash
bash scripts/fetch-perpetua.sh
bash scripts/build-mainline-kernel.sh
```

- `fetch-perpetua.sh` clones ~3 GB and pins commit `7c98a10e…`; it fails if
  the pinned tree is missing any iceland file it needs.
- The build takes a while; success ends with `=== kernel ===` and
  `BUILD-METADATA.txt` naming the release (expect `7.3.x` + suffix) under
  `$UBUNTU_WORKDIR/out/kernel-iceland/`:
  `Image`, `iceland.dtb`, `kernel.config`, `kernel.release`, `modules-root/`.

Failure modes seen in advance:

- `DROPPED: wanted CONFIG_… ` — Kconfig refused a symbol from our fragments
  (`kernel/config/*.fragment`). Read the symbol's dependencies in the
  Perpetua tree and fix the fragment; do not delete the check.
- Ancient clang: Perpetua tracks mainline; use the distro's current clang/lld.

## 3. Tablet preparation (destructive step clearly marked)

1. Boot Android. Settings → About device: note the **build/version string**
   and region. Take updates until it reports up to date — the OTA you can
   download must match what is installed.
2. Install **Oxygen Updater** on the tablet; confirm it lists the Pad 4
   (OPD2514). In its settings enable **advanced mode** so it shows the full
   download URL of the current stable build. Download the **full** OTA zip
   (not an incremental, not a rollback package) and copy it to the build
   host. If Oxygen Updater has no Pad 4 entry, see `docs/stock-firmware.md`
   for the alternatives, including the dump-from-device plan B.
3. Settings → About device → tap the build number 7× → back →
   System settings → Developer options: enable **OEM unlocking** and
   **USB debugging**.
4. Cable to the host, accept the ADB prompt on the tablet, then:

   ```bash
   adb devices           # must show the unit as "device"
   adb reboot bootloader
   fastboot devices      # if empty: run via sudo, or add a plugdev udev rule
   fastboot getvar product
   fastboot getvar current-slot
   ```

   Write down `product` — the release installer gates on it later — and the
   slot. Both also go in `docs/porting-log.md`. Also snapshot the stock
   properties while they are still readable
   (`adb shell getprop > work/getprop-stock-<date>.txt`) and check the
   OTHER slot is not ancient: `adb shell getprop ro.build.version.ota`
   names the active build; a unit that has taken at least one OTA since
   April 2026 has both slots populated, which also removes the empty-slot
   EDL hazard entirely.
5. **⚠ THIS WIPES THE TABLET:**

   ```bash
   fastboot flashing unlock
   ```

   Confirm on the device with the volume/power keys. It factory-resets and
   shows the unlocked-bootloader warning on every boot from now on.
6. After the wipe, skip through Android setup minimally and re-enable USB
   debugging (step 3) — or rely on the hardware combo (power off, then
   Power+VolDown) to reach the bootloader without adb.

## 4. Stage the stock package and record the firmware

```bash
bash scripts/stage-stock-images.sh /path/to/the-full-ota.zip
```

Success prints the `post-build` fingerprint, the `product` (compare with
`fastboot getvar product` from 3.4 — they must agree) and a listing under
`$UBUNTU_WORKDIR/stock/<build-id>/`, symlinked as `stock/current`.

Then measure the firmware manifest against the real package:

```bash
python3 scripts/stage-firmware.py record \
    --manifest configs/firmware/iceland.toml \
    --stock "$UBUNTU_WORKDIR/stock/current"
```

Expect `NOT FOUND` lines on the first run: the template's `source` paths are
conventional guesses. Find the real ones by extracting the images yourself:

```bash
mkdir /tmp/vendor-tree /tmp/odm-tree
fsck.erofs --extract=/tmp/vendor-tree "$UBUNTU_WORKDIR/stock/current/vendor.img"
fsck.erofs --extract=/tmp/odm-tree   "$UBUNTU_WORKDIR/stock/current/odm.img"
find /tmp/vendor-tree /tmp/odm-tree -iname '*zap*' -o -iname 'adsp*' \
    -o -ipath '*wlan*' -o -iname '*.mbn' | less
```

Fix the `source` (and `image`) fields in `configs/firmware/iceland.toml`,
re-run `record` until it exits clean, review the diff (every entry now has a
sha256), and commit it. This list will still grow in phase 7 from dmesg;
that is expected and each addition repeats this loop.

## 5. First hardware contact: the RAM boot (writes nothing)

Build the minimal development rootfs — known password, your SSH key:

```bash
ICELAND_PROFILE=minimal ICELAND_PW='choose-something' \
ICELAND_AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub \
    bash scripts/build-ubuntu-rootfs.sh
bash scripts/make-initramfs.sh
bash scripts/make-test-bootimg.sh
```

Notes:

- The rootfs stage is the long one (arm64 under qemu). If it completed once
  and you only changed modules or late stages, `RESUME_ROOTFS=1` reuses it.
- `make-initramfs.sh` prints the size against the init_boot budget — note
  the margin in the porting log.
- No firmware overlay is needed yet: the RAM test targets kernel + display +
  console, none of which load the staged blobs.

Then, with the tablet in the bootloader (`adb reboot bootloader` or
Power+VolDown from off):

> Escape hatch, confirmed on this unit: **power + volume-up held ~10-15 s**
> forces a PMIC-level reset from any state, hung kernels included (volume-up
> is wired to the PMIC's RESIN line in the device tree). A RAM boot leaves
> nothing behind, so this always returns the tablet to stock Android.

```bash
fastboot boot "$UBUNTU_WORKDIR/out/test-boot.img"
```

The script printed the outcome ladder; what to do with each:

1. **Panel shows initramfs text / a busybox prompt** (it will sit waiting
   for `LABEL=UBPAD4_ROOT`, which does not exist yet, then drop to a shell —
   that IS success at this stage). Plug in the keyboard via the hub and poke
   around; `cat /proc/version`, `ls /dev/block/by-name/` are the two
   observations worth writing down. Assumptions 1 and 3 in
   `boot-strategy.md` are now answered — update it and the porting log.
2. **Nothing on the panel, device falls back to bootloader after ~10 s**:
   likely the FDT handoff refused (regional stock-model mismatch) or the
   kernel never started. Check your variant against the DTS's
   `fdt-handoff` `stock-model` (the pinned tree has the India "iceland-O IN"
   string); a different regional string is a one-line Perpetua patch —
   report it upstream and carry it in `kernel/patches/` meanwhile.
3. **Spontaneous reboot**: panic. Boot Android, then check `/sys/fs/pstore`
   from a later working boot, or re-test with a serial-less triage: it is
   usually the initramfs (rebuild with `MODULES=most` intact) or a module
   the console path needed.
4. **`fastboot boot` itself refused**: assumption 3 fails; we pivot to
   flashing the bundle on the active slot directly (phase 7) — more care,
   same images — and note it in boot-strategy.md.

A power cycle fully undoes a RAM boot. Iterate kernel → `make-initramfs.sh`
→ `make-test-bootimg.sh` → `fastboot boot` as often as needed.

## 5b. Slot-retry rules (learned 2026-10-30, from the sibling ports)

- Only partitions whose NAME STARTS WITH "boot" have their slot flags
  reset on flash (ABL source + measured by the Fedora port): flashing
  `boot_b` clears "successful" and maxes retries; flashing `init_boot_b`
  or `recovery_b` does NOT touch flags. Every normal power-on of a
  NOT-successful slot burns one retry; at zero the ABL marks the slot
  unbootable (switches only if the other slot is successful+bootable,
  else parks in fastboot — recoverable). fastboot-driven, recovery and
  charger boots burn nothing.
- So the diagnostic init_boot_b flash leaves slot flags untouched: a
  stray normal power-on just lands in our initramfs (hold Vol-Down+Power
  to get back to fastboot) and costs nothing. After testing, restore the
  stock init_boot and boot Android once to confirm all is normal.
- Flashing boot_b (the real install) IS the retry regime: after it, the
  installed system must mark its own slot good after each good boot
  (qbootctl -m; the Fedora port's iceland-slot-mark is the reference
  implementation, including making the boot LUN briefly writable).
- The installed Ubuntu system must mark its own slot good (qbootctl -m
  equivalent) during first boot, or the slot strands after ~3 boots.
- `reboot bootloader` requested from mainline Linux is ignored by this
  ABL: use Vol-Down+Power (~15 s) to reach fastboot from a Linux boot.
- RAM-boot reality on this ABL: `fastboot boot` never uses the
  downloaded image's ramdisk — the flashed init_boot always supplies
  the generic ramdisk, so kernel-only RAM boots + a flashed diag
  init_boot is the test vehicle.

## 6. Full build

With the firmware manifest recorded (phase 4):

```bash
bash scripts/build-rootfs-overlay.sh
bash scripts/build-rootfs-image.sh
INITRAMFS="$UBUNTU_WORKDIR/rootfs/boot/initrd.img-$(cat "$UBUNTU_WORKDIR/out/kernel-iceland/kernel.release")" \
    bash scripts/build-boot-bundle.sh
```

or, for the whole desktop release in one go (kernel → rootfs → overlay →
image → bundle → ZIP):

```bash
bash scripts/build-release.sh
```

For development keep `ICELAND_PROFILE=minimal` (export it before
`build-release.sh`) until the desktop matters; the pipeline is identical.

## 7. Flash (the only step that writes to the tablet)

Use the installer even on the dev unit — its gates are the point:

```bash
cd "$UBUNTU_WORKDIR/out" && unzip -o ubuntu-26.04-opd2514-v*.zip -d release && cd release
adb reboot bootloader   # or Power+VolDown
bash install.sh         # checks product + unlock + checksums, asks for
                        # the literal phrase, flashes boot_<slot>,
                        # init_boot_<slot>, userdata, reboots
```

First boot expectations:

- **Before anything else: capture the factory data.** The first booted
  Ubuntu is the first moment the per-unit partitions are readable (persist
  with the sensor calibration/registry, modemst1/2 + fsg NV data,
  oplusreserve*) — and nothing in this port ever writes them. From the
  host: `scripts/capture-device-data.sh ubuntu@<tablet-ip>`. Archive the
  result with the stock OTA zip. (Known, unavoidable loss: Widevine L1
  drops to L3 from the unlock itself.)
- `ubuntu-iceland-grow-rootfs` expands the filesystem (seconds).
- Minimal profile: framebuffer console login (`ubuntu` / your `ICELAND_PW`),
  keyboard via the hub. Join Wi-Fi with `nmcli dev wifi connect <ssid>
  password <pw>`, then `ssh ubuntu@<ip>` from the host and work comfortably.
- Desktop profile: GDM's first-boot wizard.
- Immediately harvest: `sudo dmesg | grep -iE 'firmware|direct-loading|fail'`
  → feed missing blobs back into the phase-4 manifest loop;
  `journalctl -b` for everything else. Update `hardware-status.md` rows from
  ❓ with the evidence.

Back to Android at any time: `fastboot flash boot_<slot>` /
`init_boot_<slot>` with the **stock** images from
`$UBUNTU_WORKDIR/stock/current/`, reboot, and let Android factory-reset
userdata.

## 8. The iteration loops

- **Kernel-only change** (flashed install): `build-mainline-kernel.sh` →
  `RESUME_ROOTFS=1 bash scripts/build-ubuntu-rootfs.sh` (restages modules) →
  `make-initramfs.sh` → `build-boot-bundle.sh` → flash just
  `boot_<slot>` + `init_boot_<slot>`. Or RAM-boot it first, always an option.
- **Perpetua pin bump**: edit `PERPETUA_COMMIT` (and branch, on a kernel
  version change) in `scripts/fetch-perpetua.sh`, log why in
  `porting-log.md`, rebuild from phase 2. Camera/mic support is landing
  upstream — expect to want this often at first.
- **New firmware request in dmesg**: add to `iceland.toml`, `record`,
  commit, re-run phase 6 from the overlay onward.
- **Rootfs package changes**: edit the package sets in
  `build-ubuntu-rootfs.sh`, full rootfs rebuild (no resume), then phase 6.

Every session ends with a `porting-log.md` entry: what was observed, which
assumption it answered, what the next session starts with.

## 9. Operating the flashed tablet (Phase B complete, 2026-11-01)

The tablet now boots Ubuntu from power-on; fastboot is only for diag
RAM boots and future kernel updates (RAM-boot gate first, always).

- Access, in order of preference: ssh ubuntu@192.168.7.2 (or
  ubuntu-iceland.local) over the gadget network; the serial getty on
  /dev/ttyACM0; the panel console (when the DSI lottery wins — census
  pending). Host side is automatic: fixed gadget MAC → iface
  enx026963656c68 → NM profile "iceland-usb" (autoconnect-retries 0).
- ONE serial listener only. Before any flight:
  `sudo lsof /dev/ttyACM0` and kill extras — concurrent readers eat
  the echo and look exactly like a dead console (the "deaf-RX"
  false mystery of 2026-10-31).
- Clean shutdown from any state: single short power press (logind).
  Hard reset: hold power+vol-up. On a charger the tablet auto-boots
  after poweroff.
- Internet on the tablet: host NAT (ip_forward + MASQUERADE out the
  uplink, FORWARD accepts for 192.168.7.0/24) — not yet persistent on
  the host; tablet side ships in 0.2.14 (route metric 1024 + DNS).
- Clock: syncs via NTP once internet is up. If apt says Release files
  are "not valid yet", the clock has not synced — fix time first
  (chronyc online/burst/makestep), never force apt.
- Slot discipline: qbootctl.service re-marks _b each boot. Slot _a is
  factory-flagged unbootable: there is NO automatic fallback. Recovery
  is button-combo fastboot + `fastboot flash boot_b
  /srv/ubuntu-iceland/factory/fcap/part-boot_b.img` (sha-verified
  stock copy; init_boot_b restore per section 7).
- Factory restore kit: /srv/ubuntu-iceland/factory/fcap (169 images +
  SHA256SUMS) and the 723 MB tarball on Drive
  (oneplus-pad4-iceland-2fe096b5-factory-2026-10-31.tar.zst,
  sha256 25749ef9…).
- Module policy lives in /usr/lib/modprobe.d/iceland.conf (package):
  pwrseq_qcom_wcn (probe hard-resets the SoC — XPU pin suspicion,
  split-node hunt in C3) and nt36536_ts (probe resets the panel IC —
  C2). Manual modprobe bypasses blacklists by design: that is the
  bisect lever, use it deliberately.
- GPU: firmware per docs/firmware-manifest.md. Weston launch for
  tests: mkdir/export XDG_RUNTIME_DIR, --continue-without-input while
  touch is blacklisted (no --tty in weston 14); stop with
  `pkill -x weston` (never pkill -f from an ssh one-liner — it
  matches itself).
- Never edit a script while it is running. bash reads a script file
  incrementally, by byte offset; inserting or removing lines above the
  current position of a long-running build script (even a comment or an
  SPDX header) makes bash resume at a shifted offset when the current
  command returns. On 2026-11-02 a `# ----` comment lost its `#` that
  way and the kernel build died with `------: command not found` after a
  clean compile. Edit scripts between runs, or run a copy.
