# Porting log

Newest first. Every entry records what was done, what was observed (with the
command or file that shows it), and what it changed about the plan. Claims
about the hardware belong in `hardware-status.md` once they have evidence;
this file is the narrative.

## 2026-10-29 — project scaffolded

Decisions taken (and why):

- **Ubuntu 26.04 LTS** as the base: it carries Mesa 26, which has the initial
  Adreno 840 (Gen 8) support, so the GPU stack needs no backports. This is the
  one deliberate divergence from the gts9u template's 24.04.
- **GNOME on Wayland** and **Waydroid**, matching the template, so the device
  packages and docs stay structurally identical across ports.
- **Kernel = pinned [denialwm/linux-perpetua](https://github.com/denialwm/linux-perpetua)**,
  branch `perpetua/v7.3`, rather than the template's pinned-torvalds-plus-
  local-patches: Perpetua *is* the device source for iceland (DTS, panel,
  touch, backlight, speaker, Type-C mux drivers, and the `android-gki` boot
  packaging tool). Our `kernel/` carries only Ubuntu-facing config fragments
  and a (currently empty) patch directory. The pin is recorded in
  `scripts/fetch-perpetua.sh` and must move deliberately — upstream is
  landing camera support at a fast clip (CAMSS + four sensor drivers merged
  2026-10-25..28).

Facts established without hardware (sources in the repo's README and the
research notes in `~/projects/arch-oneplus-pad-4`):

- OnePlus Pad 4 = OPD2514 = Perpetua device `iceland`, SoC SM8850-AC
  ("kaanapali"), Adreno 840, 13.2″ 3392×2400 144 Hz, Wi-Fi-only, no microSD,
  no fingerprint.
- The iceland DTS already wires USB-C DP alt mode (`mdss_dp0` +
  `usb_dp_qmpphy`), dual-DSI NT36536 panel, SPI touch, KTZ8869 backlight, 6×
  TFA9865, WCD9395 + USBSS mux, WCN7860 (ath12k, `pci17cb,110e`), oplus
  battery manager. The modem node is deleted. Firmware is expected under
  `/lib/firmware/qcom/kaanapali/iceland/` (seen in the DTS:
  `adsp.mbn`, GPU zap `gen80200_zap.mbn`).
- Microphone and camera are the two gaps the Denial device matrix admits;
  camera kernel work is in flight upstream.

Open questions carried into the next session (also mirrored in
`boot-strategy.md`'s assumptions table): product string for the installer
gate, `fastboot boot` support, init_boot size margin, userdata raw-flash
behaviour, vendor-ramdisk concatenation hygiene, the full firmware file list,
suspend/battery behaviour under GNOME, stylus and sensors existence.

Next steps, in order:

1. `scripts/check-build-deps.sh` on the build host; fix what it reports.
2. `fetch-perpetua.sh` + `build-mainline-kernel.sh` — get a configured build
   with our fragments merged and the symbol check green (no hardware needed).
3. Obtain the stock OTA package for the installed firmware;
   `stage-stock-images.sh` and `stage-firmware.py record`.
4. Minimal-profile rootfs + first `fastboot boot` attempt (assumption 3), with
   USB networking + SSH as the only goal.
5. Only then the desktop profile, Waydroid, and the release pipeline
   end-to-end.

## 2026-10-29 — OTA located; the iceland-mainline ecosystem discovered

- Installed build identified from Oxygen Updater: `OPD2514_11.A.38_0380_202608042337`
  = **OxygenOS 16.0.10.501(EX01), GLO region** (catalog: roms.danielspringer.at
  OTA API). Full package: 6.74 GiB, MD5 `56fac9cb6aadebfb4104a7b2e7df6bcb`.
  The pending update is `11.C.08` = **ColorOS 17.0.0.101** — deliberately
  declined (OxygenOS is the base every iceland port was developed on; ColorOS
  unlock policy risk). Auto-update is to stay off on the dev unit.
- Discovered a second, further-along port ecosystem:
  **github.com/mzakamin-hub/{iceland-mainline,iceland-linux,iceland-firmware}**
  (+ iceland-u-boot; Fedora 44, U-Boot in boot_b, GRUB, btrfs on userdata,
  dual boot with BlissROM; kernel = patch queue on linux-next "7.4 base").
  Their hardware answers adopted as strong priors, each still to be confirmed
  on our unit: `fastboot getvar product` = **canoe**; `fastboot boot` works;
  sparse-flashing userdata works; stock 11.A.38 wanted on **both slots**;
  working camera/sensors/pen/DP; no SuperVOOC.
- Fixed in this repo accordingly: the installer's product gate now uses the
  repo constant `configs/install/expected-fastboot-product` (= canoe) instead
  of the OTA metadata product (OPD2514) — those are different namespaces and
  the old gate would have refused every real device.
- `mzakamin-hub/iceland-firmware` is built from stock **11.A.38** (our exact
  build) and its `MANIFEST.tsv` documents each blob's stock source path —
  next session: use it to replace the guessed `source` paths in
  `configs/firmware/iceland.toml` before the first `record` run.

## 2026-10-29 (later) — GLO support decided; handoff semantics understood

- Decision: this port targets the **GLO** variant (our dev unit's region).
- Read Perpetua's fdt-handoff binding and history: `stock-model` /
  `stock-compatible` / `stock-bootargs` are each "one of these" string
  arrays, ANDed; the model match exists because the **RedMagic 11 Pro shares
  the qcom,canoe bootloader**. A mismatch boots the vendor tree "as usual" —
  i.e. a silently dead tablet on mainline. The pinned DTS names only the IN
  model ("...Canoe MTP,iceland-O IN"), so a GLO mismatch is likely.
  `scripts/check-handoff-match.sh` now verifies model+compatible offline
  against the staged stock `vendor_boot.img`; stock-bootargs
  (`oplusboot.prjname=25978`) is ABL-appended at boot and only verifiable on
  the first RAM boot.
- Found and defused an initramfs landmine: the built-in tree's bootargs say
  **`rdinit=/rescue/mainline-init`** (Perpetua's boot userspace layout). Our
  initramfs now ships a `/rescue/mainline-init -> /init` symlink via the
  `iceland-rescue-init` initramfs-tools hook (zero kernel delta), and
  `make-initramfs.sh` refuses an archive without it.

## 2026-10-29 (evening) — GLO handoff fully verified offline; no patch needed

Measured from the staged GLO 11.A.38 firmware plus the running unit
(SELinux blocks adb's /proc/device-tree reads on OxygenOS; properties and
the OTA's own images do not lie):

- `ro.boot.dtb_idx=12` → base FDT = "CanoeP v2 SoC" (`qcom,canoep`);
  `ro.boot.dtbo_idx=6` → board overlay 06 of ten (five board variants ×
  two silicon families in dtbo).
- Overlay 06 root: model **"Qualcomm Technologies, Inc. Canoe
  MTP,iceland-O IN"** — identical to the pinned stock-model even on GLO
  firmware (OnePlus ships the IN board string for project 0x657a/25978
  globally) — and compatible "qcom,canoe-mtp qcom,canoe qcom,canoep-mtp
  qcom,canoep qcom,mtp", which contains the pinned `qcom,canoe`.
- `ro.boot.prjname=25978` matches stock-bootargs.
- VERDICT (scripts/check-handoff-final.sh): all three handoff legs MATCH;
  the pinned Perpetua tree accepts this unit unpatched. Assumption 5's
  product gate ("canoe") still gets its direct confirmation at first
  fastboot contact.

Tooling hardened along the way by real-world contact: quoted-string
parsing in check-handoff-match.sh, the pipefail/head trap in
inspect-dtbo.sh, zip-direct payload extraction in stage-stock-images.sh,
and check-handoff-final.sh for the composed-root question.

## 2026-10-29 (night) — shared workdir; firmware staged end-to-end; kernel rebuild

- Workdir relocated to user-owned **/srv/ubuntu-iceland** so Claude's
  sandboxed shell runs and verifies every root-free stage directly; only
  rootfs/initramfs/image keep sudo. In-image ownership made
  builder-independent (forced --owner=0 at both merge points).
- **Firmware chapter closed offline**: 28/28 phase-1 files staged from the
  owner's own OTA and hash-verified against the iceland-firmware 11.A.38
  manifest — including the pil-join (adsp/cdsp ×4) and FwUp-strip (touch)
  reimplementations, byte-exact on first run. Three real-world extraction
  lessons now in stage-firmware.py: EROFS/ext4/vfat by superblock magic,
  debugfs rdump for ext4, MTOOLS_SKIP_CHECK=1 for the zero-CHS NON-HLOS
  vfat (reproduced on a scratch image before shipping).
- First kernel build attempt died with a buried make Error 2; the 1000-line
  scrollback holds only successful lines. Box has 8 cores/14 GB and was
  simultaneously extracting a 6.7 GB payload — OOM during the vmlinux link
  is the working theory. Clean rebuild (relocation invalidated the old
  build dir's absolute paths anyway) now running detached under Claude's
  watch at -j6.

## 2026-10-30 — kernel green; the merge_config lesson

Both earlier build failures were one bug: scripts/kconfig/merge_config.sh
re-resolves through alldefconfig, which re-defaulted CONFIG_DRM_MSM (a
symbol no fragment mentions), demoting DRM_KMS_HELPER to =m and killing
the vmlinux link on undefined DRM helper symbols. Proven by config diff
plus an A/B of both merge strategies; fixed as append + olddefconfig.
The OOM theory was wrong.

Clean build: Linux 7.3.0+ at pin 7c98a10e, Image 42.8 MB with the iceland
DTB built in, 939 stripped modules (18 MB), fragment guard green on the
as-built config, and the built DTB's fdt-handoff matching every value
verified against the GLO unit. Artifacts staged with hashes under
out/kernel-iceland. Also ready ahead of first boot: the factory-data
capture script with its mock-tablet test (tests/check-capture-script.sh),
NOPASSWD sudo on dev images, and the DRM-streaming roadmap row.

Next: checkpoint 2 (minimal rootfs, sudo), then initramfs, test image,
tablet prep, RAM boot.

## 2026-10-29 (late night) — tablet unlocked; every live assumption confirmed

Pre-unlock snapshot banked (1,783 props, work/). Live fastboot contact:
**product: canoe** (assumption 5 closed on hardware), current-slot b,
unlocked: no → `fastboot flashing unlock` → confirmed on-device → wipe →
verifiedbootstate **orange**, vbmeta.device_state **unlocked**, still
slot _b. Active slot B means the unit has OTA'd and both slots are
populated: the empty-slot EDL hazard is retired for this device. Unit
serial 2fe096b5 (future factory-capture label). ColorOS 17 note: the
catalog offer came via Oxygen Updater only; stock's staged rollout has
not reached this unit; auto-update disabled regardless (and the wipe
removed Oxygen Updater itself).

Remaining before the RAM boot: rootfs (checkpoint 2) → initramfs →
test image. The tablet side is done.

## 2026-10-29 (midnight) — RAM-boot image ready; the initramfs education

Checkpoint 3 closed the hard way, every lesson caught by a gate rather
than a dark panel: MODULES=most blew the 8.4 MB init_boot budget (17.3 MB
— mostly udev hwdb and the module tree); MODULES=list left 13.2 MB of
stock payload; the trim hook plus the measured udev removal (verified
against the shipped scripts: wait_for_udev no-ops, resolve_device uses
blkid, the polling loop is the designed wait-for-root fallback) landed
2.53 MB with a 5.9 MB margin. The closure audit caught two real defects
en route: Ubuntu's own orphaned mount.fuse3, and the klibc runtime that
is no library but the INTERP of thirteen boot utilities. The real
system's udev is untouched: coldplug replays everything after
switch_root.

test-boot.img: 45,350,912 bytes (kernel with built-in DTB + the 2.53 MB
initramfs, v4, unsigned-footer). Known wrinkle: stock header OS version
fields read as unset and are mirrored as such. Next: fastboot boot.

## 2026-10-30 — Attempts 1–3 dark; the decompressor finds the bug

Three RAM boots (`fastboot boot test-boot.img`), three identical results:
"Booting OKAY", panel dark, the device gone from USB entirely, no
self-reboot (built-in `panic=0` makes a panic and a healthy headless boot
look alike — noted for later, fixed in the diag image). Attempt 2 flew an
ACM debug gadget in init-top that raced dwc3's asynchronous UDC
registration; attempt 3 flew the fixed script (backgrounded 30 s poll,
verified byte-for-byte in the flown archive) and still nothing — a clean
negative: the kernel never reached our initramfs.

Working the boot chain backwards found two candidate killers:

1. **The fdt-handoff match is stricter at runtime than offline.** Reading
   `arch/arm64/kernel/fdt-handoff.c`: `stock-model` is an exact `strcmp`
   against the *live* root model and `stock-bootargs`
   (`oplusboot.prjname=25978`) a word-match against the *live*
   `/chosen/bootargs` — both of which ABL composes at boot, and nothing
   guarantees RAM boots get the dtbo overlay applied. A failed match
   boots the Android tree silently (dark, dead USB); a passed match that
   then errors hangs on `cpu_relax()` forever. Both invisible.

2. **The ramdisk layout was fatal all along.** ABL prepends the stock
   vendor ramdisk — LZ4-legacy — to ours, and Ubuntu's initramfs-tools
   emits a *plain cpio segment first*. The kernel's LZ4-legacy decoder
   (`lib/decompress_unlz4.c`) has no end-of-stream marker: after the
   vendor frame it reads the next four bytes as a chunk size, and ASCII
   `0707` is an ~0.8 GB chunk. In the no-fill path there is not even a
   bounds check before `LZ4_decompress_safe` eats garbage; the whole
   unpack fails before PID 1 (`init/initramfs.c`). Android never hits
   this because its chain is LZ4 end to end; Perpetua's rescue ramdisk is
   a single LZ4 stream. Ours was the odd one out — and the old
   `make-initramfs.sh` gate even documented the prepend while blessing
   the layout that breaks under it.

Fixes, all verified offline: `make-initramfs.sh` now repacks the archive
as **one LZ4-legacy frame over the concatenated raw cpio bytes**
(entry-exact, decoded by the kernel as successive cpio archives, exactly
like stock's vendor+generic pair) and its gate now enforces LZ4-from-
byte-0. `make-diag-bootimg.sh` builds the attempt-4 image with no root
and no rootfs writes: the repacked initramfs plus an LZ4 overlay segment
carrying `scripts/diag/iceland-usb-debug-beacon` (ACM stream on UDC,
forced reboot after a 30 s UDC timeout), and a diagnostic kernel —
handoff match loosened to compatible-only (`qcom,canoe`/`qcom,canoep`,
covering a skipped dtbo) and `panic=0` → `panic=10` — built from the
release worktree and reverted after. Outcome map: ACM = read the log;
reboot ~15–25 s = post-handoff panic; reboot ~35–50 s = userspace ran,
USB never probed; dark = handoff hang or match still failing. RAM boot
only; nothing diagnostic is ever flashed.

## 2026-10-30 (later) — The control pair solves it: ABL ignores RAM-boot ramdisks

Flights 4–7 (gadget console, built-in watchdog, clk/pd sweep disabled)
all died identically: gadget on the bus at T+1 s, dead by ~T+6 s, reset
with no panic delay. Nothing kernel-side moved the needle — because
nothing we changed was in the air. The control pair told the truth:

- Stock kernel-only boot.img RAM-boots to full Android → the ABL
  substitutes flashed init_boot for a missing ramdisk; `fastboot boot`
  itself is fine.
- Stock kernel + OUR ramdisk in the image ALSO boots full Android,
  Android USB up 6 s after handoff → **the ABL never loaded our
  ramdisk at all**. On this ABL, `fastboot boot` always boots the
  flashed init_boot + vendor ramdisk.

So attempts 1–7 ran our kernel with Android's ramdisk: handoff fine,
rdinit=/rescue/mainline-init absent — and the kernel's fallback list
(/sbin/init, /etc/init, /bin/init, /bin/sh) does NOT include /init, so
Android's init never ran either: "No working init found" panic. Under
panic=0 (attempts 1–3) that HANGS until a forced reset — exactly what
we observed; under the diag panic=10 it resets ~10 s after the early
panic — the 7-s-black / 3-s-logo signature. Not a watchdog, not the clock sweep,
not TrustZone. The beacon never fired because our initramfs never flew;
qemu (which does load it) keeps proving the archive itself sound.

Consequences kept: the single-LZ4 repack stands (the FLASHED chain is
vendor LZ4 + our archive, where the boundary rule is real), QCOM_WDT=y
stands (a module-less initramfs must feed the dog itself once we are
actually in the air). Next flight: flash init_boot_b with our wrapped
initramfs (first persistent write, stock image retained for restore),
then `fastboot boot` a kernel-only image of our kernel — the full
Ubuntu chain with still nothing permanent on boot_b.

## 2026-10-30 (later still) — RAM-boot ramdisk delivery: every accepted path ignores the downloaded ramdisk

Confirming the control-pair finding against every delivery variant this
ABL offers:

- pre-built header-v4 image with ramdisk: boots, ramdisk ignored
  (the stock-kernel hybrid booted Android with our cpio aboard);
- `fastboot boot <kernel> <ramdisk>` (client-constructed, default
  header): accepted for download, refused at boot, silent fall-back to
  the fastboot screen;
- the same with --header-version 3: returned
  "Failed to load/authenticate boot image: Load Error" — but the command
  was issued while the ABL sat on its failure screen (winking mascot,
  CN text) left by the previous attempt, so that run was void. Retested
  from clean fastboot: v3 is ACCEPTED, the kernel starts, and the same
  7-s-black / 3-s-logo RESET follows (no-init panic + panic=10), after
  which the flashed stock chain boots Android normally — the
  v3-embedded ramdisk is ignored exactly like v4's. The failure screen still serves the
  fastboot protocol and `fastboot reboot` returns to Android.

Corroboration from the wild: cfig/Android_boot_image_editor
discussion #144 reports a Pixel ignoring the merged-in ramdisk on
`fastboot boot` the same way — AOSP leaves RAM-boot ramdisk semantics
to the vendor, and init_boot-era bootloaders took the license.

Conclusion: on this ABL the downloaded ramdisk is never used; only the
flashed init_boot reaches the kernel. Testing our chain therefore
requires the first persistent write — init_boot_b carrying our wrapped
initramfs (image staged, stock image retained for one-command restore)
with the kernel still RAM-booted. Held pending the external research
agents' reports, at the owner's call.

## 2026-10-30 — Device research lands: watchdog confirmed armed, slot-retry rules, sibling ports

The device-research sweep (primary sources, repos cloned) settles the
open questions:

- **ABL hands off with the APSS watchdog armed — by the maintainers' own
  word.** Perpetua's rescue PID1 loads qcom-wdt.ko as its FIRST act
  ("Let the standard watchdog core service a watchdog left running by
  ABL", phonewave usb_rescue_init.c); the Fedora port pets the same dog
  (Gunyah-emulated APSS WDT, 30 s once managed); upstream U-Boot stops
  it in probe on Snapdragon. Our CONFIG_QCOM_WDT=y (fragment, since v3)
  probes even earlier than their module load. Our flights never reached
  the bite because the no-init panic killed them first; with the
  flashed init_boot the dog is handled.
- **Slot mechanics (operational rules):** flashing boot* resets the
  slot's flags; every NORMAL boot of a not-yet-successful slot burns a
  retry; at zero ABL marks the slot unbootable and switches slots.
  fastboot/recovery/charger boots burn nothing. So while a diag
  init_boot is flashed: no normal power-on boots; fastboot-driven boots
  only; after restoring stock, boot Android fully once to re-mark the
  slot successful. For the real install, the rootfs must mark its own
  slot good (qbootctl -m) — added to the phase plan.
- **Diagnostics:** pstore/ramoops does NOT survive this device's resets
  (PS_HOLD re-initializes DDR); instead Android's /proc/bootloader_log
  records the reset reason — read it after any fuse event.
  qcom_scm.download_mode=full can hold crashes in dump mode.
- **ABL facts from the sibling ports:** fastboot boot skips verifying
  the downloaded image but loads dtbo/vendor_boot/init_boot from flash
  (their measurement matches our delivery matrix); `adb reboot
  bootloader`-style reboots requested from mainline Linux are ignored
  (use Vol-Down+Power); flashed boot_b MUST carry an AVB hash footer
  even unlocked (INVALID_METADATA strands the slot) — android-gki adds
  it; max-download-size 768 MiB; cable-in power-on = charger mode.
- **Ecosystem:** three sibling Linux ports exist for iceland — Arch
  (Perpetua, flash-only, ext4-on-userdata), Fedora (mzakamin-hub,
  U-Boot EFI chain, 555-patch display/GPU queue incl. the splash
  handover recipe), and an Ubuntu EDK2-BootApp port (SuperTurtleDev,
  custom GPT approach). Ours stays Perpetua-aligned (flash boot_b +
  init_boot_b only); the iceland-linux patch queue is the mining ground
  for display/GPU once we boot. tb323fu's bring-up cmdline (incl.
  initcall_blacklist=...genpd_power_off_unused — pd_ignore_unused alone
  does not stop of_genpd_sync_state) is the survival kit if later
  bring-up stalls; the idle cluster-off reset workaround exists if
  idle resets appear.

## 2026-10-30 — Fedora-port review: corrections and adoptions

The deep review of mzakamin-hub's Fedora port (the best-documented
sibling) lands these on our plan:

- **init_boot flashes do not touch slot flags** (only names starting
  with "boot" do; ABL source + measured) — Phase A is flag-neutral.
  The qbootctl -m requirement binds to Phase B's boot_b flash.
- **The handoff-memory hazard is already closed for us**: their sharpest
  warning (never boot a DT without ABL's real /memory; a zero-size
  memory node sent a OnePlus 15 to EDL) is exactly what Perpetua's
  fdt-handoff.c does right — we read the code: usable RAM comes from the
  STOCK tree's /memory minus its no-map holes, and kernel+initrd bounds
  are validated inside it (hard stop otherwise).
- **GPU firmware pair hazard for the desktop phase**: stock OTA's GMU
  5.3.39/SQE 0x103 resets the tablet early in boot when GPU preemption
  is enabled; mainline defaults preemption off — never enable it on the
  stock pair; the working "vendor533" pair is documented in their
  iceland-firmware MANIFEST.
- **fwupd ships with Ubuntu and lists UFS storage firmware as updatable
  by default** — the one software path to a dead tablet that bypasses
  partitions; the rootfs must disable/guard those fwupd plugins before
  first boot (Phase B item).
- Our initramfs already satisfies their hard rule (no remoteproc/
  firmware-consumer modules in the initramfs — ours carries none), and
  our bring-up-only use of clk/pd_ignore_unused matches their F24
  policy (never on the installed system).
- Adoption queue for after first light: splash-handover patch set
  (simple-framebuffer node with MMCX/MX/MXC TURBO votes + both MDSS
  GDSCs incl. INT2, video-mode splash detect, multi-PD mdss attach,
  KTZ8869 write-only-diffs), audio UCM2+topology (distribution-
  neutral), sensors (hexagonrpc/libssc/iio-sensor-proxy) recipe, config
  gotchas (DMABUF_DEBUG=n, GPIO_SHARED_PROXY=y,
  FW_DEVLINK_SYNC_STATE_TIMEOUT=y, CMA heap off), cpuidle 0277/0278
  ready-switches if idle resets appear, binder note (7.4 drops the C
  driver; binderfs path for Waydroid on any future rebase).

## 2026-10-30 (afternoon) — Phase A flight 1: the loop, the cmdline, the feeder

First flashed flight (diag init_boot_b + RAM-booted diag kernel): our
kernel raised the gadget at T+2 s and died before enumeration finished
(host journal), then every NORMAL boot looped at the logo ~4 s apart —
stock kernel + our ramdisk, and the watchdog petter Android normally
loads from vendor modules in its first second never loads from ours.
Slot flags survived untouched (b: successful, 6 retries; and we learned
slot a is marked unbootable on this unit — ABL would park in fastboot,
not switch). Stock init_boot restored; Android normal.

The bugreport captured what SELinux hides: the full runtime cmdline.
oplusboot.prjname=25978 IS a live cmdline word — the strict handoff
bootargs leg verifies at runtime on this GLO unit. Also: init=/init,
console=ttynull, panel mdss_dsi_panel_XN251_P_D_A0024_vid (NT36536),
oplus_region=167, verifiedbootstate=orange. LAST KMSG in the bugreport
is empty — pstore really does not survive these resets.

Open question: why our built-in qcom-wdt + HANDLE_BOOT_ENABLED did not
keep the dog fed (suspect: the already-running detection through the
hypervisor-emulated register). Countermeasure built: the diag overlay
now replaces rescue/mainline-init with a wrapper that disarms/feeds
/dev/watchdog* within ~2 s of kernel start, stamps kmsg markers, then
execs /init. New diag initrd + stock-templated init_boot rebuilt and
cross-verified.

## 2026-10-30 (evening) — The real killer: a usr-merge symlink losing to the vendor ramdisk

The panel console (v8, apps-SMMU left alone) finally showed the death in
writing: "Failed to execute /rescue/mainline-init (error -2)" → "No
working init found" at 0.65 s — with the whole UFS enumerated and
g_serial bound above it. Reproduced on the desk in qemu with the real
vendor blob prepended; our archive alone boots fine. An automated qemu
bisect over the vendor archive's 509 entries pinned the trigger to
entry 4, lib/modules — and with init/initramfs.c in hand the mechanism
is exact: the vendor ramdisk extracts first and owns a non-empty real
lib/; our usr-merge `lib -> usr/lib` symlink then silently loses
(rmdir of a non-empty directory, errors deliberately ignored), and
every dynamic executable afterwards fails ENOENT on
/lib/ld-linux-aarch64.so.1. PID 1 never existed; under panic=0 that
hang-then-forced-reset, under panic=10 the quick reset — every flight
of the flashed era, and the stock-kernel 4-second loop, were this one
bug. The SMMU only ever killed the screen that would have shown it.

Fix in scripts/repack-initramfs.py, shared by make-initramfs.sh and the
diag builder: the lib entry becomes a real directory carrying loader
symlinks (ld-linux-aarch64.so.1, klibc-*.so) that resolve through
usr/lib — it merges over the vendor's lib/ instead of fighting it.
Verified: the full vendor00+archive chain boots in qemu to the wrapper
(6.6 s), /init, and the 30 s beacon.

## 2026-10-30 (night) — PHASE A COMPLETE: interactive Ubuntu initramfs on hardware

Flight 18: stable `(initramfs)` shell over the USB ACM console, no
resets, waiting indefinitely. Evidence captured live
(out/flight-18.log on the build host):

- `/proc/device-tree/model` = "OnePlus Pad 4" — the built-in mainline
  DTS is what booted;
- `/proc/device-tree/chosen/linux,fdt-handoff` present — the handoff
  formally engaged, ABL memory map carried;
- all six UFS LUNs enumerated (sda..sdf incl. the 103-partition sde),
  zram0 present; `userdata` located at sda15 from inside the system;
- g_serial console enumerated as "Linux 7.3.0+ with dwc3-gadget";
- minutes idle without reset: the ABL-armed watchdog is genuinely
  handled by the built-in driver.

The road here, for the record: ABL ignores RAM-boot ramdisks (flash
init_boot_b instead); the archive must be one LZ4-legacy frame; lib/
must be a real directory with loader links or the vendor ramdisk
poisons every dynamic exec; the apps SMMU probe kills the splash
scanout (diag leaves it disabled; the kaanapali-mdss client patch is
the real fix later); panic=N doubles as initramfs-tools policy (keep it
off diag cmdlines; break=mount for a deliberate shell); the beacon
pattern must never reboot once a console exists.

Next: Phase B — rootfs image, release boot+init_boot pair via
android-gki, userdata (sda15) flash, first boot, factory-data capture
first, then the desktop profile.

## 2026-10-30 (late) — The rehearsal boots to login; three archive bugs dead

The qemu full-system rig (diag kernel + release initramfs + the flashed
userdata image, snapshot mode) earned its keep three times over before
the tablet flew B.4:

1. wait-for-root vanishes from the archive silently (mkinitramfs's own
   unconditional copy_exec loses it in the chroot) — now placed by our
   last-word zzz hook and gated by make-initramfs.
2. 26.04's wait-for-root binary links libudev and resolves through
   udevd — structurally incompatible with the udev-less archive.
   Replaced with a blkid shim honoring the same contract (wait for
   spec, print TYPE).
3. Our own conf.d shipped ROOTFLAGS=rw,noatime — the init script
   splices ROOTFLAGS verbatim expecting the "-o" form, so the root
   mount ran as `mount -r -t ext4 rw,noatime /dev/vda /root` and died
   on usage. Latent since day one; found via the in-guest debug trace.
   Options for / live in fstab.

Final rehearsal: resolve, mount, switch_root, systemd, zero failed
units, "ubuntu-iceland login:". Bundle init_boot rebuilt (ad589da5…).

## 2026-10-31 — The post-boot reset: evidence table and suspect ladder

Constant: every boot that reaches the full system dies 17-33 s after
kernel start; every boot held in the initramfs lives indefinitely; the
bootloader-era hangs (attempts 1-3) sat 90+ s without reset, so no
bootloader-armed fuse is in play. The killer is a booted-system actor.

Cleared by single-variable flights: the watchdog (v16/v17 carry a
probe-time stop patch; deaths unchanged), the NT36536 TDDI touch probe
(v17 disables its SPI; died on schedule — despite a seductive
mechanism: the module-only-in-booted-system timing, and a probe that
resets the live panel IC before deferring), every watchdog feeder
variant (all shortened life or changed nothing), and the first
service-mask flight (confounded by a feeder, rerun pending).

Remaining classes: (1) udev's module parade — v18 masks udev entirely;
if it lives, the bisect is interactive modprobe over the serial login,
no rebuilds; (2) base services; (3) storage writes — the booted system
is the only configuration that writes UFS (journal flush, online
resize), the initramfs flights never wrote a byte; testable with a
read-only boot if classes 1-2 clear.

## 2026-10-31 — v18/v20 verdicts; v21 scrapped on the pad; v22 is the rig

v18 (udevd + trigger masked) reached multi-user and graphical target,
only pd-mapper failed, and lived until we stopped watching. Killer
narrowed to what udev's coldplug does: load every module the DT
aliases ask for. Two misreadings along the way — the flight was twice
declared dead while its screen log was still growing. Rule: read the
whole log; a stall ("waiting for two dev units") is not a death.

v20 (only the trigger masked) stalled on device units: pre-existing
devices are announced ONLY by the coldplug trigger, so masking it
starves every dev-*.device — ttyGS0's getty included. Masking udev is
therefore not a shippable mitigation, just a diagnostic lever.

The parade, computed instead of guessed: 211 DT compatibles from the
live DTB crossed with modules.alias "of:" entries → 28 loadable
modules; +ath12k +btqca (non-of paths) → 30 blacklisted.

v21 was built with module_blacklist= and scrapped before flying:
that list is enforced in the kernel's load_module() — a listed module
is -EPERM for EVERY caller, our bisect modprobes included. v22 swaps
in modprobe.blacklist=, the kmod-level list: udev coldplug applies it
(KMOD_PROBE_APPLY_BLACKLIST), explicit modprobe by name bypasses it.
Same safety, one-flight interactive bisect.

Bisect ladder (least → most suspect; probe, settle ~20 s, next):
qcom_rng, leds_qcom_flash, leds_qcom_lpg, pci_pwrctrl_pwrseq,
pwrseq_qcom_wcn, nt36536_ts, i2c_qcom_cci, phy_qcom_mipi_csi2,
spi_geni_qcom, pinctrl_sm8650_lpass_lpi, qcom_camss, hci_uart, btqca,
fastrpc, snd_soc_tfa9865, snd_soc_wcd939x, soundwire_qcom,
snd_soc_lpass_tx_macro, snd_soc_lpass_rx_macro, snd_soc_lpass_va_macro,
snd_soc_lpass_wsa_macro, q6prm_clocks, q6prm, q6apm_dai,
q6apm_lpass_dais, snd_q6apm, snd_soc_sc8280xp, ipa, ath12k, and LAST
qcom_q6v5_pas — the TZ PAS remoteproc boot, the one class the Fedora
port keeps out of early boot, and the mechanism that best explains a
silent secure-side reset. The module whose probe resets the tablet is
the killer; the durable fix is a rootfs modprobe.d blacklist until its
bring-up phase.

Also landed: device 0.2.10 drops serial-getty@ttyGS0's BindsTo on the
udev device unit and waits for the node itself — v18 was a live system
nobody could type into; never again.

## 2026-10-31 — Flight v22: alive, loginless; the T+60 link bounce

v22 booted clean in ~8 s: full udev, coldplug done, zero failed units,
getty on ttyGS0, prompt on the host. It then LIVED — from boot to the
deliberate unplug five minutes later. Two independent proofs now stand
(v18, v22): the coldplug module parade kills the box; everything else
is innocent.

Nobody could type into the prompt. Audit of the whole serial path
against known good: u_serial.c (gs_open / gs_start_io / gs_start_rx /
gserial_connect / gserial_disconnect) is mainline-identical; config
carries U_SERIAL_CONSOLE + G_SERIAL + F_ACM correctly; the DT pins
dr_mode="peripheral" and deletes usb-role-switch (so no UCSI role
flip is possible); the prompt itself proves gs_start_io succeeded —
RX was armed on the first attach. No code defect found.

The host journal held the real event: the gadget link BOUNCED once at
T+~60 s (13:54:04 disconnect, 13:54:06 re-enumerate; no reboot — the
same boot continued). The first screen died with its port; a second
listener attached to the new port and never received a byte. On
disconnect u_serial calls tty_hangup(), so agetty was restarted by
systemd — its reprinted prompt SHOULD have reached attach #2. Its
absence is the one genuine device-side anomaly. Whether typing was
also dead before the bounce is unknown (the two screens are
indistinguishable to the operator). Host-side injection probes never
reached the wire (sandbox EACCES; screen holds the port), so they
exonerate nothing.

Attach #2 then stayed up 4.5 min: the bounce is ONE-SHOT, not
periodic. Candidates, ranked: deferred-probe-timeout cleanup at T+60;
gadget-side suspend mishandling; host autosuspend escalation;
pmic_glink aux probing (role flip excluded by DT). The tablet kept a
persistent journal (journal-flush ran) — the previous-boot kernel log
on sda15 names the culprit next login.

Next flight re-flies the same v22 image with a reattaching listener,
types within 30 s of the prompt (pre-bounce RX test), and tests again
after the bounce; if even pre-bounce typing is dead, a raw tee/cat
split test isolates host vs device without screen in the path.

## 2026-10-31 — The bisect convicts pwrseq_qcom_wcn (twice)

Factory capture first: 167 images + SHA256SUMS in /var/fcap on the
tablet (6.3 GB) — GPTs of all six LUNs, full lun-sd[b-f] images, every
partition <= 2 GiB including persist, devinfo, nonmodemst1/2, both
slots' whole boot chain. super (14.6 G) skipped: stock-ROM restorable.
Pull plan: scp over usb0 on the release-kernel flight.

The ladder then walked, hands off: qcom_rng, leds_qcom_flash,
leds_qcom_lpg, pci_pwrctrl_pwrseq all SURVIVED; pwrseq_qcom_wcn's
insmod printed at 14:58:29 and the log ends mid-settle. Identical
death one run earlier (confounded then by a Ctrl-C; not this time).
pwrseq_qcom_wcn powers the WCN radio rails and unblocks the deferred
qcom-pcie bridge, so the reset fires at rail-enable / PCIe link
bring-up. Mechanism TBD; identity confirmed.

25 rungs remain untested (qcom_q6v5_pas still the top remaining
suspect). Next boot: write the 30-module modprobe.d blacklist onto
the rootfs (makes the blacklist-less release kernel safe for the
capture pull), then run the remainder ladder without pwrseq_qcom_wcn.

## 2026-10-31 — Deaf-RX boot lottery, characterized

The serial-input failure is decided once per boot: a bad boot is deaf
(host->device) on its first attach, on the T+60 re-attach, after cable
replug and after direct writes to the port, while device->host streams
perfectly; a good boot hears from the first byte and stays good for
hours. Replug re-runs usb_ep_enable + gs_start_io (fresh requests both
sides), so connect-cycle state is exonerated — the poison lives below
that, per boot. Suspects: HS-PHY init vs dwc3 ordering races under the
diag cmdline (fw_devlink=off, initcall_blacklist, clk/pd_ignore), PHY
tuning/efuse application. Mitigation tonight: press Enter at the
prompt; deaf boot -> power-press (logind clean shutdown works
loginless) and re-fly. May not reproduce on the release kernel's
untouched cmdline; dedicated hunt after the parade is mapped.

## 2026-10-31 — Parade fully mapped: one killer; 0.2.11 ships the policy

The remainder ladder (24 rungs, pwrseq_qcom_wcn excluded) walked end
to end and SURVIVED — qcom_q6v5_pas, the whole audio stack, ipa and
ath12k included. The coldplug parade holds exactly one killer:
pwrseq_qcom_wcn.

Root-cause picture: the nubia kaanapali board wires its WCN PMU
identically (TLMM 16 wlan-enable, PMH0104 gpio5 bt-enable, same
supplies) and works; our board dies at driver BIND, where the
pinctrl-0 default states write both pins' config. Classic signature
of an XPU-protected pin write under OPLUS firmware. Confirmation plan
(WLAN phase): split the pmu node — BT half deleted, then WLAN half —
one flight names the guilty block, and the DT then reserves the pin
instead of blacklisting the driver.

Sequencing, one variable per flight: the gate flight keeps the full
30-line on-device parade file (its job is the capture pull + qbootctl,
minimal risk). Installing 0.2.11 over ssh during that session swaps in
the packaged 2-line policy (/usr/lib/modprobe.d/iceland.conf:
pwrseq_qcom_wcn + nt36536_ts, the latter because the release kernel
re-enables the touch SPI and the TDDI probe resets the live panel).
The NEXT release boot then validates full parallel coldplug of the
remaining 27 under the real config — apps_smmu live, no diag cmdline.

Also characterized today: the deaf-RX boot lottery (separate entry)
and the T+60 one-shot USB bounce (flight A only; never recurred).
Both filed for the hardening pass, neither blocks Phase B.

## 2026-10-31 — Gate flight: capture pulled, fixes installed, qbootctl proven

Release-kernel RAM boot (the exact flash-candidate configuration: same
kernel payload, same flashed init_boot_b initramfs). ACM+ECM composite
enumerated clean; host NetworkManager got a persistent iceland-usb
profile (192.168.7.1/24) after its DHCP attempt was found starving the
link. Pull: 169 files, 6.3 GB, zero bad checksums; tarballed as
oneplus-pad4-iceland-2fe096b5-factory-2026-10-31.tar.zst (723 MB,
sha256 25749ef9…) — serial 2fe096b5 from androidboot.serialno.

Surprises worth remembering: the flashed rootfs was still running
device package 0.2.1 (not 0.2.9 as assumed — the image predated the
late packages); 0.2.11 + qbootctl 0.2.2 now installed over ssh, old
parade file auto-removed, 2-line policy and getty drop-in verified on
disk. Slot dump: _b active/successful/bootable, _a flagged UNBOOTABLE
(OPLUS post-OTA state) — so no automatic Android fallback: a failing
boot_b ends at button-combo fastboot + stock reflash, not a slot
switch. qbootctl -m exercised live: exit 0, idempotent, table intact;
its service (multi-user) is the post-flash retry protection, needed
because flashing boot_b resets slot flags.

Gate-boot baseline archived to factory/gate-boot/ (journal, lsmod=20
under the parade file, cmdline "rdinit=… loglevel=7 … bootconfig" with
no blacklist, failed=pd-mapper only). dmesg errors all known classes:
UFS attr idn 13 noise, DSI PLL no-lock + missing gen80200_sqe.fw (the
display debt, probing without SMMU faults), battmgr uevent EAGAIN.
ModemManager AT-probes the gadget's login prompt from the host —
cosmetic; ignore-rule filed for the hardening pass.

Remaining unknown before B.5, by design: parallel coldplug of the 27
freed modules under the release kernel — the next validation flight.

## 2026-10-31 — Tracked: early serial output loss on some boots

Operator-observed: some boots show less early console output than
others on the host listener. Known contributors to fold into the
hardening pass alongside the deaf-RX lottery: the u_serial console
buffer is bounded (early lines overrun and drop until the host
enumerates and drains), the listener attaches only once /dev/ttyACM0
exists (bytes sent before attach are gone), and enumeration timing
varies boot to boot. Candidate fixes: larger gs_console buffer or
log_buf replay via the beacon on connect; listener pre-arm via udev
rule instead of poll loop.

## 2026-10-31 — Deaf-RX "lottery" solved: concurrent host readers

Operator-found: multiple listener loops/screen sessions (each restart
left the prior one alive under its orphaned sudo shell) were attached
to /dev/ttyACM0 simultaneously. Competing readers split the
device-to-host byte stream: typed input reached the tablet and agetty
echoed, but the echo was consumed by a hidden session, so the visible
one looked deaf and its -L log stayed frozen. Fits every observation
(usbmon showed host-to-device bulk completing; injected CRs never
appeared in the watched log; "per-boot" pattern tracked which stale
sessions existed at attach time). The USB PHY is exonerated; the
earlier deaf-RX entries stand corrected. Discipline: exactly one
listener; audit with lsof /dev/ttyACM0 before each flight. Still
open and unrelated: the validation boot's missing enumeration, and
flight A's one-shot T+60 re-enumeration.

## 2026-10-31 — Validation-boot verdict: one chmod; 0.2.12

The unreachable validation boot was healthy end to end: multi-user at
T+1 s, all 27 freed modules coldplugged in parallel cleanly, DSP stack
active (32 remoteproc/adsp lines, PDR avs/audio lookup -6 expected).
The only failure: ubuntu-iceland-usb-gadget.service died at EXEC —
the 0.2.11 deb shipped /usr/libexec/ubuntu-iceland-usb-gadget mode
644 (status 203/EXEC, "Permission denied"). Latent packaging-tree
regression, never caught because no package since 0.2.1 had been
installed on-device until today. Tree audit found a second 644
executable: hooks/zzz-iceland-ensure — the wait-for-root ensure hook,
which mkinitramfs would have SILENTLY SKIPPED on the next on-device
regen. Both fixed; 0.2.12 built with all six executables verified
rwxr-xr-x inside the archive; on-device chmod issued over serial for
the already-installed copies. Net: the parallel-coldplug gate PASSED;
access fixed; next release boot is the B.5 go/no-go.

## 2026-10-31 — B.5: boot_b flashed

Final release re-flight: zero failed units (pd-mapper green now that
the ADSP boots), 63 modules in parallel coldplug, qbootctl auto-marked
_b at T+1 s, gadget/getty active — and the panel lit: msm_dpu bound
both DSI controllers, DP and GPU, "Initialized msm 1.13.0", fb0
msmdrmfb — kernel console on glass (gen80200_sqe.fw still missing, no
acceleration; DSI PHY probe order still lottery-ish; display phase
will finish the job). 0.2.13 installed (fixed ECM MACs; host iface
becomes enx026963656c68 permanently).

Then the write: fastboot flash boot_b with bundle/boot.img
(e362bcf4…, the image that flew clean twice), 45 ms. fastboot reboot
issued — first standalone boot pending verification (battery pause).
Restore at arm's reach: factory/fcap/part-boot_b.img. From here the
tablet boots Ubuntu on power-on; fastboot boot remains for diag
kernels, and slot flags are re-marked by qbootctl.service each boot.

## 2026-10-31 — Phase B complete: standalone Ubuntu verified

First flashed boot, on battery at 1%: power-on to Ubuntu with no PC.
Zero failed units; slot _b re-marked Active/Successful/Bootable by
qbootctl.service after the flash's flag reset — the protection loop
closed exactly as designed. Gadget (fixed MAC enx026963656c68), getty
and ssh all up; kernel console on the panel; battery telemetry live
via ADSP battmgr. Three access paths, one write, full restore kit
banked on Drive. Next: Phase C — display proper (GPU firmware, DSI
PHY probe order), WLAN (pwrseq split-node XPU hunt), touch driver,
audio, then GNOME/Wayland and Waydroid.

## 2026-10-31 — Charging chain verified operational

On the standalone boot, measured not assumed: battery Charging
(charge_type Fast), +164→176 mA into the cell at 3.48 V / 27.0 °C,
USB input ~1.1 A @ 4.66 V from a PC SDP port, UCSI/Type-C stack live
(port0 + partner; no PD contract — source is a PC port). Charge
control is ADSP-autonomous as on stock; kernel side is telemetry +
Type-C only, all present. Net-positive even with SoC + panel running;
PD wall charger negotiates properly for real charge rates; pre-boot
(off) charging is charger-firmware-handled below the OS. Known
cosmetic: boot-time power_supply synthetic uevent EAGAIN; battmgr
input current_now reads slightly above its advertised current_max.

## 2026-11-01 — C0 complete; first Wayland desktop on glass

C0 gate met: host NAT (wlo1 masquerade) + tablet default route/DNS →
apt self-sufficient; first apt pass exposed a clock trap (epoch-pinned
Sep 16 made resolute-security Release files "not valid yet" — always
sync clock before judging apt); chrony kicked (online/burst/makestep)
→ Stratum 3 NTS, true time; update clean (22 suites), upgrade applied,
toolkit installed (weston kmscube mesa-utils evtest i2c-tools
stress-ng); mDNS works (ubuntu-iceland.local); MM ignore rule in;
single-listener discipline held.

Then, same boot, no reboot: Weston 14 on KMS. Launch lore: needs
XDG_RUNTIME_DIR provided, --tty is gone in 14, embedded-seatd builtin
seat works headless, --continue-without-input required while touch is
blacklisted, --renderer=pixman for the no-GPU path. Output DSI-1
enabled (SDR, sRGB), desktop visible on the panel, and weston-flower
runs as a live client — full pipeline client→compositor→KMS→DSI
proven on CPU rendering. Bonus input inventory for C2: pmic_pwrkey
(event0), pmic_resin (event1), gpio-keys (event2) — hardware buttons
already deliver input events. Battery net-positive under desktop load
(+364 mA at 2%, 28.0 C). Next: C1 proper — DSI lottery census once
charged, then GPU firmware for real rendering.

## 2026-11-01 — The Adreno 840 lives: GPU firmware landed, GL desktop up

The hunt took one evening because everything was already in reach. The
driver's manifest (a6xx_catalog): gen80200_sqe.fw + gen80200_gmu.bin +
gen80200_aqe.fw, zap at qcom/kaanapali/iceland/gen80200_zap.mbn (DTS).
The loader is strict (adreno_load_fw returns on any missing file), so
all four were required. Sources, every byte verified:
- SQE e2d4e742… + GMU 06f4484f… — the "vendor pair" (GMU v5.3.33,
  SQE 0x094) from the Fedora port's firmware repo clone, hashes
  matching its MANIFEST.tsv, itself triple-corroborated
  (SuperTurtleDev = map220v = Lenovo TB323FU stock). Chosen over
  stock's pair (GMU 5.3.39/SQE 0x103), which per that README resets
  the tablet early in boot unless GPU preemption is off.
- AQE ed7916ca… — extracted from OUR stock vendor.img (EROFS,
  fsck.erofs --extract; full tree now at stock/vendor-extracted/),
  byte-identical to SuperTurtleDev's published copy.
- Zap d185bfc9… — already shipped by our overlay; tablet copy =
  overlay = stock vendor extraction, three-way match.

Result on reboot: all three request_fw loads "from new location",
"[drm] Loaded GMU firmware v5.3.33", renderD128 appears; kmscube: 400
frames, exit 0, "renderer: Adreno (TM) 840", GLES 3.2, no faults;
weston relaunched WITHOUT pixman: "Using GL renderer" on DSI-1 — an
accelerated Wayland desktop on glass. Firmware banked into
out/rootfs-overlay/lib/firmware/qcom/ so every future image ships it.
Watch item: gcc/gxclkctl/gpucc report sync_state pending on the GMU —
benign so far, revisit if clock gating misbehaves.

Papercuts for device 0.2.14: access script should not tear down and
recreate an existing gadget (the 1 s bounce makes host NetworkManager
drop the profile; it also replayed an old interface-name into the
profile once via shell history); ship Gateway=192.168.7.1 + DNS with
a high metric in 80-iceland-usb0.network so route/DNS survive reboots.

C1 remaining: DSI PHY lottery census + probe-order fix (battery >20%
first), backlight sweep. Then C2 (touch) is the road to GNOME.

## 2026-11-01 — 0.2.14 installed: networking survives reboots

Route (proto static, metric 1024) + DNS now ship in the .network file
and applied live via postinst networkctl reload; internet verified
with no manual steps. Beacon gadget now opt-in (iceland-dbg bootargs
marker) in the packaged initramfs script — the flashed init_boot keeps
the old beacon until its next refresh, covered meanwhile by host NM
autoconnect-retries 0. Battery note: hours on the PC port still reads
1-2% — PD wall charger overnight before the census.

## 2026-11-01 — Overnight research: the WLAN reset has a prime suspect

Deep-research pass (agent, ~30 min) wrote docs/wifi-plan.md (674
lines, committed). Headlines: our captured dtbo/vendor_boot decompile
proves downstream uses the SAME pins as our DT (TLMM16 / PMIC-J gpio5
/ TLMM18 sw_ctrl) — wrong-pins hypothesis dead; Android's own cnss2
drives these pins, so static XPU is nearly excluded. Prime suspect
(~55%): upstream dbd674ccf30f ("power off WLAN at probe", post-rc7)
changed wlan-enable gpiod_get from GPIOD_ASIS to GPIOD_OUT_LOW — and
deleted a FIXME comment warning against exactly that — so v7.3-final
yanks a bootloader-live WCN low at bind; the working Fedora port runs
rc7 (no write). Flight matrix F0-F4 in the plan (F0 = devmem reads,
method-checked on a safe pin first); fix #1 = local ASIS revert +
upstream regression report (the line has flip-flopped twice before).
Firmware staging block ready (WCN7860/hw2.0, 6 files, hashes
transcribed from the Fedora MANIFEST.tsv). New rail from the research:
never dump whole-TLMM pinctrl/gpio debugfs on this device. Caveat for
the matrix: flight patches live in kernel/patches/ which release
builds also apply — remove 90-flight.patch before any release build.

## 2026-11-01 — The WLAN power-on hunt: a day of falsifications

F0/F1 (diag, zero-change): all four bind-time writes ran under trace,
probe returned 0, boot lived — probe-time theory dead, dbd674 revert
(v23) obsolete before flying. The deferred PCIe bridge then probed,
found the WCN alive on bootloader-leftover power, ath12k_wifi7 auto
loaded (cmdline blacklist says "ath12k"; the driver is ath12k_wifi7 —
gap noted), MHI powered on, and the SoC reset — at that time with no
firmware staged.

Supply archaeology: our DT and 7860 driver support both descend from
map220v (vddio-flavored, self-consistent); the Fedora port pairs the
infiniti driver list (vddcx-flavored) with their 0167 DT remap. We
adopted 0167 alone (v24) — wrong: our driver ignores vddcx, so S1J
(the radio's core rail) was never enabled; chip half-alive, link
trains nothing ("Device not found"), system lives. v25 same (module
trap: make-diag builds Image+dtbs only — the 0004 driver fix compiled
into nothing; rootfs module replaced by hand afterwards, original
kept at /root/pwrseq-qcom-wcn.ko.zst.orig). v25B (true pair, full
power-off first): instant silent reset at the pwrctrl modprobe.

The discriminator, 4/4 across flights: every configuration that votes
S1J from Linux resets instantly and silently; every one that leaves
S1J alone survives (v24, v25 alive; original map, v25B dead). S2J on
the same PMIC votes fine — it is S1J itself, not the PMIC path.

Verification pass (user-ordered) killed my favorite mechanism: the
rpmh readback feature is IN v7.3-rc7 (merge-base proof) — the working
Fedora stack shares it, and their S1J floor is the same 400 mV. The
mode-order fix (9561d678) is in our pin and absent from theirs.
Mechanism: unproven. v26 (S1J floor raised to the OnePlus-15 family
value, 892 mV — patch 0005, correct regardless): reset anyway.
Falsified as the trigger.

Standing hypothesis: the diag cmdline environment itself
(pd_ignore_unused, clk_ignore_unused, suppressed regulator/genpd late
init, fw_devlink=off) — every S1J conviction ran under it; no sibling
ever powers this radio under such a configuration. Test in flight:
release kernel rebuilt with 0003+0004+0005, RAM-booted (nothing
flashed), chain completed over ssh in the normal environment. Dying
diag boots leave no journal of the death (first-second flush only)
and no serial bytes — the reset outruns all I/O; this is expected,
not missing evidence.

Patches now permanent: 0003 (0167 DT supplies), 0004 (vendor 7860
role list), 0005 (S1J 892 mV floor). The preserved flashed image:
bundle/boot-e362bcf4-flashed-b5.img.

## 2026-11-01 — WIFI WORKS: hypothesis 2 confirmed, chain complete

Flight R2: release kernel #31 (bundle dd3de7d0…, patches 0001-0005),
RAM-booted, normal environment. modprobe pwrseq_qcom_wcn over ssh:
SURVIVED. The parked pwrctrl completed the chain: PCIe trained, WCN7860
enumerated, staged firmware booted (WLAN.GNG.2.0-01536, fw 0x200b7fff),
MHI mission mode, wlan0→wlp1s0. Scan saw the neighborhood (AP at 99%),
explicit NM profile associated (nmcli inline-password over ssh needs
the con-add form — no tty to prompt), DHCP 192.168.1.250, wifi default
route (metric 600) beat usb0 (1024) by design, internet over air at
22 ms, and ssh INTO the tablet over wifi works.

Resolution: the diag cmdline WAS the killer context — the identical
power-on that hard-reset four diag flights runs clean under the normal
boot. The S1J-vote discriminator was real but environment-bound
(pd/clk_ignore_unused + suppressed late regulator/genpd init turn a
legal RPMh sequence lethal; exact interaction left as a documented
open question — we ship the normal environment). Patches 0003-0005
remain: correct supplies, correct roles, correct floor.

Surfaced in the same flight: BT half now powers up and requests its
firmware (gngbtfw20.mbn) — the known naming debt, queued; ath12k
country-code warnings (sibling queue has fixes); wifi powersave is
real on this firmware (pin tip commit) — inbound latency until tuned;
iw not installed.

CRITICAL SEQUENCING RULE until the new kernel is flashed: the rootfs
blacklist MUST keep pwrseq_qcom_wcn — the flashed boot_b still runs
the old #17 kernel whose DT would power the radio wrong at coldplug.
Order: flash the new bundle to boot_b (after soak) → only then ship
0.2.15 dropping the pwrseq blacklist for automatic wifi every boot.
