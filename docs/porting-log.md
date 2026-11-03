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

## 2026-11-01 — C3 COMPLETE: radios flashed, automatic, wireless

boot_b flashed with the R2-gated bundle (dd3de7d0…, kernel #31,
patches 0001-0005; verified five ways pre-flash — operator lesson:
`fastboot boot` from shell history is not `fastboot flash boot_b`;
the "Writing" line is the tell). 0.2.15 installed: pwrseq freed from
the blacklist (nt36536_ts alone remains, with the pwrseq tombstone
comment), NM wifi.powersave=2 shipped as policy. Finale reboot,
hands off: kernel #31 from flash, all three radio modules coldplugged
automatically, wifi self-connected (sloth, 192.168.1.250), BT
controller registered, zero failed units. The tablet is now a
self-booting, self-connecting wireless Ubuntu device.

Next: C2 touch per docs/touch-plan.md (T0 firmware verify, T1
unpatched modprobe on the live desktop, then the 0007/0008 ordering
patches). Queued behind it: ath12k patch-queue adoption at the next
kernel refresh (regdomain + RX-burst + power-save set), per-unit BT
MAC from persist, formal iperf, the DSI census, backlight sweep.

C4 doorbell, observed post-C3: with the audio modules coldplugging,
qcom-apm requests qcom/kaanapali/OnePlus-Pad4-tplg.bin and the
snd-sc8280xp card cleanly fails to instantiate (-2). The topology is
in NO local source (not in the Fedora clone, not in stock — Android
does not use ALSA topology): C4 starts by building it from the
audioreach-topology project or a newer sibling drop. First ops over
wifi today: dmesg pulled via 192.168.1.250.

## 2026-11-01 — C2 session one: the probe is tamed, the INT line is the war

T0 green (firmware hash on device, blacklist, panel, tools). T1: the
v17 ghost is exorcised — unpatched modprobe on the live mainline panel
registered NVTCapacitiveTouchScreen + NVTCapacitivePen and the panel
survived; but zero touch events, zero IRQs. Analysis per the plan's
stop-and-analyze branch, in order of elimination:
- Probe-time download skipped (panel already prepared at registration)
  → the 0007/0008 fix pair built, module-swapped, verified: download
  now runs at panel-enabled time ("Update firmware success", fw_ver
  0x15, PID 0x5F9A) — the fix works as designed.
- INT line (gpio158): pull-down in TLMM, parked low. Live pull-up via
  devmem: still low — actively held, not floating.
- Trigger experiment (level-low test module): 2.4 kHz interrupt storm,
  IC never releases, and the decisive twist — the storm is a free
  polling mode, and evtest during 43k polls while tapping produced
  NOTHING. The IC's touch engine is not running, despite healthy
  firmware dialogue over SPI.
- Eliminated against the working Fedora stack: firmware (hash), DT
  node/pins (downstream dtbo), pin bias (tested), panel reset sequence
  (absorbed upstream), panel DSI init tables (byte-identical, 114
  sequences), driver patches (0174/0180 adopted as 0007/0008).
- Found and adopted: their 0103 — our 144 Hz front porch is 68 (their
  pre-fix arithmetic slip); stock is 64. Ported as 0009 (panel is
  builtin → kernel+bundle rebuild in flight). Long shot for the
  symptom, correct regardless; fbcon likely runs the 144 Hz mode.
Rails held throughout: no rmmod ever (UAF), reboots swap modules,
hash-verified installs, one variable per flight. Rootfs currently
carries the LEVEL-LOW TEST module — restore the edge build before the
next flight.

## 2026-11-01 — TOUCH WORKS: the bonded-DSI orientation was the wall

P1 (porch fix): eliminated — correct timing, fresh verified download,
engine still dead (0009 kept; stock-correct). P2 (audit's #2): revert
perpetua's sync-on-DSI0 cherry-pick (5892773b169d) + panel primary
context dsi[0]→dsi[1] = the Fedora/upstream orientation, one variable.
Display survived the flip; boot-time probe download still left the
engine dormant — but the first panel cycle's enabled-time download
LIT IT: IRQ line pulsing (hundreds then 661+), full multitouch:
four corners at the four coordinate extremes (X 0..33920,
Y 0..24000), a mid-line horizontal drag tracking at 60 Hz reports,
slots and touch-major sane. Promoted as permanent 0010.

The TDDI moral: both ICs must hear their broadcast commands in the
order the firmware expects — the display tolerated either
orientation, the touch engine only starts under upstream's. Credit:
the parity audit's composed-tree diff found it (their port-log had
deliberately dropped the cherry-pick); the porch red herring fell to
the same method.

Boot-time-dormant quirk noted for T5: a modprobe-time download on an
already-enabled panel leaves the engine dormant until one panel
cycle; coldplug's deferral path (0007) should take the clean
enabled-time route naturally — T5 verifies, else a one-shot fix.
Next: T4 soak, T5 coldplug 3/3, T6 flash + 0.2.16 retiring the final
blacklist line.

## 2026-11-01 (night) — T6 flashed. C2 closed; the tablet is
## self-contained

Session-restart interlude first: the desktop session died mid
ship-build (background task orphaned), and a forked session's rerun
truncated build-ship.log before being killed in turn. The 18:51:59 PST
bundle survived intact (boot.img 7fa88c2e…, payload dc42b125…,
metadata + evidence self-verified). Provenance was re-established two
independent ways: the tablet was found *running* that exact kernel
(#33, build-stamp 18:47:09 PST — a fastboot RAM boot from the fork's
testing), while boot_b still hashed to the radio-era image
(dd3de7d0…). That settled "RAM or flashed?" decisively: RAM. The
worktree was left with all ten patches applied (seven files modified);
the build-dir Image of 20:10 is the killed rerun's orphan — the bundle
is the artifact of record.

Auditing that RAM boot caught a false T5: the journal showed the touch
module hand-modprobed at t=22.9s, and the #T5# blacklist comment
postdated the boot — udev auto-load had never actually been exercised.
Aliases verified matching (spi:NVT-ts-spi ↔ modules.alias), so the
first flashed boot became the real coldplug test.

T6 flight: fastboot flash boot_b — a real "Writing 'boot_b' OKAY" this
time (the fastboot-boot-vs-flash tell earns its keep again) — then
reboot. Verified: partition sha == bundle sha (7fa88c2e…); kernel
#33/18:47; touch AUTO-loaded at t=2.06s with zero manual modprobes;
wifi self-joined (predictable naming renamed wlan0 → wlp1s0;
192.168.1.250); BT UP; backlight 2047; qbootctl re-marked slot B
bootable+successful. User taps: IRQ 0 → 689 edges. The
boot-time-dormant worry dissolved exactly as 0007 predicted: at t≈2s
the panel is not yet enabled, so probe defers the download to
panel-enable time and the engine comes up live — no extra panel cycle
needed.

0.2.16 installed (blacklist file now tombstones only). Its postinst
triggered an initramfs regen (→ ac042cf4…), staged host-side at
out/initrd.img-7.3.0+.post-0.2.16 pending a sudo cp into rootfs/boot:
the flashed boot.img carries the old initrd (inert — real-root udev
governs), but the NEXT bundle must embed the clean one. depmod warned
modules.builtin.modinfo missing from the hand-installed module tree —
cosmetic; copy it from the build dir at the next modules_install.

Finale reboot: everything automatic from cold storage — kernel, panel,
touch (t=2.08s, zero manual), wifi + IP, BT, serial getty, slot flags
intact. C2 ledger: coldplug 2/2 on the flashed kernel (the plan's
3/3 RAM rehearsal was superseded by the flash-first reality; taps
verified on boot 1; every future boot extends the census). C2 CLOSED.
Cold power-on now yields a ten-patch Ubuntu with display, GPU,
10-point touch, wifi, BT, battery telemetry and dual consoles — no PC
in the loop.

Known-benign, filed for polish: one-shot WARN
"dsi0_phy_pll_out_dsiclk already disabled" (clk refcount in the
splash→DPU handoff, t=0.39s, taints 512/W); arm-smmu context faults
SID 0x800 in the same handoff window; ath12k regulatory grumbles;
OnePlus-Pad4-tplg.bin request (that one is C4's whole job).

## 2026-11-01 (later night) — C4 opens: topology built (A0), card
## instantiates (A1), TDM chain ported (A2 build)

Three research agents landed plans for every outstanding subsystem
(docs/audio-plan.md, sensors-plan.md, media-misc-plan.md — each checked
file-by-file against the Fedora port). Headlines beyond audio: the
IMU/sensors live behind the ADSP sensor hub (BMI3x0+AK09919+STK36C01+
hall, factory cal in persist; fastrpc/libssc/iio-sensor-proxy-3.9
route, /sys/bus/iio stays empty by design); VPU is near-free (~8
patches, our vpu40_2v.mbn byte-identical to Fedora's); haptics and
GNSS are NOT FITTED (no motor, modemless SoC — both close as paper);
suspend is a de-risked C6 (Fedora ships s2idle at 0.35%/h; our DTS
carries their known instant-wake wake-gpios bug).

A0: OnePlus-Pad4-tplg.bin BUILT on the host — linux-msm/
audioreach-topology @993a17d + the Fedora Pad-4 overlay (vendored
verbatim in configs/audio/topology/), VOL_CTRL_MAX forced to 2056
(-12 dB bring-up cap) at build time by scripts/build-audio-topology.sh.
Bit-reproducible: f9bfb173…; 8192 reference d8f4b5f3… (≠ phonewave's
prebuilt 11b78ff1 — their provenance still open). Banked in overlay +
manifest row.

A1 (one variable: the file appears): staged to /lib/firmware/qcom/
kaanapali/, asound.state wiped, reboot. GATE PASSED — card 0
"OnePlus-Pad4" registers, zero tplg errors, kernel-side PCMs all
present (MM1/2 playback, MM3/4 capture, MM6 DP, compr4); the only
ASoC line is a benign bind deferral at 7.7s. aplay absent = alsa-utils
not on the minimal rootfs (now installed). No regressions (touch/
wifi/BT clean).

A2 port: Fedora's TDM speaker chain adopted as kernel/patches/
0011-0024 (14 patches; their 0041/0042/0045/0048/0044/0049/0046/0047/
0104/0290/0051 + DT 0038/0043/0050, authorship preserved). Their 0059
(tx-macro ADPT disable) turned out FULLY absorbed in perpetua already
(POST_PMU write included, lpass-tx-macro.c:1066) — the parity table's
"partial" was stale; skipped. One real conflict: 0041's GRAPH_OPEN
error hunk collided with perpetua's superset handling (cleanup +
ERR_PTR); kept ours, folded their dev_err into the existing error
path. tfa9865.c verified BYTE-IDENTICAL to Fedora's final after the
four amp patches (plan's transcription rule). Port method: git am
onto a scratch worktree over our 0001-0010 baseline, then format-patch
regenerated — all 24 apply clean under build-mainline-kernel.sh's own
git apply --index. Rebuild running (build-a2.log); bundle will embed
the post-0.2.16 initrd (ac042cf4) directly from out/ — the canonical
rootfs/boot copy still awaits the user's sudo cp.

Flight plan next (plan §4): A2 bundle = RAM boot + hand-installed
modules, SILENT gate (six "Found TFA9865", EINVAL above 2056 on the
stream volume, routes read 0). First sound only at A3: 1 s, -30 dBFS,
440 Hz, hand on chassis, MANSTATE operating on all six.

## 2026-11-01 (23:00) — A2 flew clean; A3: FIRST SOUND

A2 bundle (kernel #35, 22:05 PST, patches 0001-0024, post-0.2.16
initrd ac042cf4) RAM-booted after rsync'ing the full stripped module
tree (audio set sha-verified against modules.sha256; depmod clean —
also retired the modules.builtin.modinfo warning). G-A2 all green,
silent: card up on the TDM DT, SIX "Found TFA9865 MN1" (right bank
enumerates as i2c bus 4, not downstream's 22 — cosmetic), speaker
route off, control ceiling hard at max=2056 (an attempted 8192 pins
to 2056; amixer clamps client-side so the EINVAL leg of 0021 goes
unexercised — the ceiling itself is proven). No regressions.

A3 (guarded): 1.0 s, 440 Hz, -30 dBFS stereo tone via
plughw:OnePlusPad4,0 with the MM1→PRIMARY_TDM_RX_0 route armed only
for the burst. Mid-play regmap reads: ALL SIX amps reg12=0x0929 —
MANSTATE 9, operating. Zero new dmesg lines across the window, route
verified off after. Replayed once; USER CONFIRMS AUDIBLE. First sound
on the port, at the bring-up cap. Per-side formal check rides A4's
channel test (GNOME part deferred to C5).

## 2026-11-02 — A3 speakers CONFIRMED; A4 up; A5 mic capture blocked
## (precise signature)

A3: user confirmed audible tone from the speakers on the A2 bundle
(kernel #35/#36). Speaker chain proven end to end at the -12 dB cap,
all six amps MANSTATE 9. This is the hardware-risk gate and it is
PASSED.

A4: device package 0.2.17 ships the Fedora UCM2 profile (speaker pin
held at the 2056 bring-up cap, not their 8192) + the phonewave
WirePlumber soft-mixer rule + pipewire/wireplumber/alsa-ucm-conf
deps. UCM loads (our card longname is "OnePlus-Pad4", so it needs its
own conf.d/kaanapali/OnePlus-Pad4.conf symlink beside Fedora's
oneplus-OnePlusPad4.conf). WirePlumber builds the Speaker sink and
"Internal microphones" source; soft-mixer active; playback through
PipeWire works.

GPR pair 0025/0026 (infiniti 0109 callback-before-probe + 0131
1024-byte intents) built into kernel #36. The boot-time "CMD timeout
for [1001021]" persists once (cosmetic, does not block the tplg).

A5 BLOCKED — mic capture returns EIO, zero frames, no hardware risk.
Signature, fully isolated:
 - FE "MultiMedia3 Capture" (hw:0,2) opens then fails: debugfs state
   = "No active DSP links" — the DPCM core attaches NO back end.
 - The whole capture DAPM chain stays Off even mid-arecord:
   TX_AIF1 Capture, ADC1 REQ, MIC BIAS1, TX SWR_INPUT0, TX_SWR_CLK.
 - tx-macro decimator path-ctl (reg 0x400 on 6ae0000.codec-tx_macro)
   never asserts CLK_EN; the POST_PMU unmute dwork never runs because
   the decimator widget never powers.
 - The routing mixer "MultiMedia3 Mixer TX_CODEC_DMA_TX_3" is a
   2-channel BOOLEAN reading on,off and refusing on,on — but the
   playback mixer "PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1" is also
   on,off and playback links fine, so the single enabled channel is
   not the blocker.
 - The BE widget "TX_CODEC_DMA_TX_3 Capture" EXISTS (dai_out, in 2
   out 0), statically wired from BOTH "TX_AIF1 Capture" (6ae0000
   tx-macro) and "WCD AIF1 Capture" (audio-codec) and out to
   device120.codec_dma_tx1 on the GPR service. All routes present;
   the link simply never activates.
 - Controls verified at stock: ADC1/2 Volume 14, TX_DEC0/1 84,
   muxes/switches on. Mic volumes and switches are not the cause.
So: a capture-only FE->BE DSP-link-formation failure in
q6routing/q6apm (or a topology capture-graph gap), distinct from the
working playback path. Handed to a focused debug pass against the
Fedora tree (which captures cleanly on this exact ADSP image).

## 2026-11-02 (cont.) — A5 round 2: latch DISPROVEN on-device;
## refined to a TX capture-path data-starvation bug

Tested the debug pass's #1 root cause (perpetua-only topology_uncertain
graph-open latch) empirically before patching. DISPROVEN for our
failure. With dynamic debug on soc-pcm + q6apm + q6apm-lpass-dais, an
`arecord -D hw:0,2` shows the FULL DPCM capture lifecycle SUCCEEDING:
"connected new DPCM Capture path MultiMedia3 Capture <- WCD Capture",
BE open, FE open, hw_params (48000/2), prepare, "trigger BE WCD
Capture cmd 1" then ~0.6s later "cmd 0"/hw_free/close. ZERO
occurrences of "Failed to open graph", "APM_CMD_GRAPH_OPEN failed",
EUCLEAN or EBUSY. The q6apm graph opens cleanly; the gate (confirmed
present at q6apm.c:52-55 etc., absent in v7.3) simply never fires
here. EIO surfaces at pcm_read = DATA STARVATION, not a setup error.

Refined diagnosis: the capture DSP graph starts but the LPASS TX
analog/SoundWire leg never powers. Mid-capture: tx-macro decimator
path-ctl reg 0x400 (6ae0000.codec-tx_macro) never asserts CLK_EN; DAPM
"TX_AIF1 Capture" = in 2 out 0 Off, "TX SWR_INPUT0" Off, "TX_SWR_CLK"
Off; the POST_PMU unmute dwork never runs. clk_summary shows no
tx-macro/swr2 TX mclk enabled during capture (PRI_TDM_IBIT 12.288MHz
is up = speakers).

Discriminator (SoundWire-wide vs TX-specific): WCD RX playback on swr1
(MultiMedia2 -> RX_CODEC_DMA_RX_0) links and clocks fine (lpass-rx-mclk
powers 6ad0000.soundwire). So the SoundWire framework + WCD + macros
work; the fault is TX-capture-specific (swr2 @7630000 / lpass-tx-macro).
Prime suspect: the perpetua-only ~180-line tx-macro rework
(capture_mute/stream_mute/dec_active + mute_lock; dec_active set true
only in the POST_PMU-queued unmute dwork). Handed back to the loaded
debug context to pin the exact source edit.

Fix-test loop confirmed: audio set is all =m but tx-macro is locked
under snd_soc_core (16 users) so no hot-swap; a tx-macro-only fix =
make modules + rsync + RAM-boot the existing #36 bundle (no Image
rebuild). DT/core fix = full bundle rebuild. Device held booted +
instrumented for a one-shot test when the fix lands.

## 2026-11-02 — A5 fix (0027) CONFIRMED at the analog layer; a
## second DSP-capture-DMA stall now isolated

Flew the tx-macro revert (patch 0027, module rebuilt sha 5425c7e0,
kernel #37 RAM boot). CONFIRMED it fixes the layer the debug pass
identified: via the UCM/PipeWire capture path the tx-macro chain now
fully powers (it never did before) — reg 0x400 = 0x24 (CLK_EN
asserted, was 0x14), DAPM "TX_AIF1 Capture"/"TX DEC0 MUX"/"ADC1" all
On with the WCD-direct leg correctly dark, and lpass-tx-mclk enabled
(9.6MHz) clocking swr2. The compose-capture-mutes abort was the
analog-path bug; 0027 resolves it.

Remaining (new, distinct layer): the capture PCM reaches state
RUNNING but hw_ptr is frozen at 0 (avail_max 0, delay 0) for the whole
capture — the DSP AudioReach capture graph runs but DMAs no data into
the ring; wav is header-only; no kernel errors. Selecting the real
tx-macro leg (the fix) exposed this: pre-fix, pw-record delivered
~215040 silent frames (ring advancing on the degenerate WCD-direct/
decimator-off path); post-fix the ring is frozen. So the analog
samples now reach the LPASS codec-DMA but the q6apm capture read path
(RD_SHARED_MEM / period completion) isn't filling userspace. Handed to
the loaded debug context (round 3) to pin the q6apm/q6apm-dai capture
data-delivery cause vs v7.3/Fedora. Device held on #37 for testing.

## 2026-11-02 — #37 FLASHED (speakers + analog mic fix permanent);
## mic capture narrowed to LPASS codec-DMA (everything else matches Fedora)

Flashed boot_b with the #37 bundle (891fcb6e, patches 0001-0027:
touch+wifi+BT+speakers+GPR pair+tx-macro revert). Verified: boot_b sha
== bundle, slot re-marked bootable+successful, flashed kernel carries
the fixed tx-macro (5425c7e0), touch/wifi/BT all coldplug, card
OnePlus-Pad4 registers. Speakers + the analog mic-path fix are now the
on-storage default (survive power-cycle). Decision (user): flash now,
keep pushing mics.

Mic capture — further narrowed. On the fixed+flashed kernel the FULL
2-channel analog chain powers and clocks during capture: BOTH
decimators (reg 0x400 DEC0 = 0x24 AND reg 0x480 DEC1 = 0x24, CLK_EN on
both), ADC1/ADC2/ADC1 REQ/ADC2 REQ/TX DEC0&1 MUX/TX SWR_INPUT0&1 all
On, lpass-tx-mclk clocking swr2. The one-decimator/channel-count
hypothesis is DISPROVEN. DT confirmed identical to Fedora (wcd_tx
tx-port-mapping <2 2 3 4>, &swr2 override, base-dtsi port framing).
Yet capture PCM = RUNNING with hw_ptr frozen at 0, zero read-done, no
errors. So C source + DT + firmware (adsp.mbn byte-identical) + the
live analog chain ALL match the working Fedora port; the remaining
difference must be the LPASS TX codec-DMA transfer, a kernel CONFIG,
or a runtime/userspace detail. Handed to the loaded debug context
(round 4) to deep-dive those against Fedora. Device flashed on #37,
held for testing.

## 2026-11-02 — SCOPE CHANGE: the bug is the LPASS codec-DMA (both
## directions), not mic-specific. Speakers (TDM) unaffected.

Round-4 decisive test: WCD HEADPHONE playback via RX_CODEC_DMA_RX_0
(hw:0,1) FAILS with the identical write EIO as mic capture. So the
LPASS codec-DMA transfer is broken in BOTH directions (playback +
capture). The "playback works" result was the TDM SPEAKER path only
(PRIMARY_TDM_RX_0 -> q6afe/PRM -> TFA amps), a DIFFERENT LPASS
interface that does NOT use codec-DMA. Consequences: built-in speakers
work (flashed, permanent); WCD headphone-out AND both mics (all
codec-DMA) do not.

Concrete lead: during an active codec-DMA stream, LPASS_CLK_ID_TX_CORE_
MCLK is enabled (4/4, held by codec@6ae0000 tx-macro) but
LPASS_CLK_ID_TX_CORE_NPL_MCLK is DISABLED (0/0, deviceless) — likewise
RX_CORE_NPL and VA_CORE_MCLK/2X are 0. LPASS_HW_MACRO + LPASS_HW_DCODEC
votes are held (6/6). Bit clock present, frame/word (NPL) clock absent
= codec-DMA periods never complete (hw_ptr frozen, EIO), matching the
observed stall in both directions.

Status of comparison vs Fedora: round 4 excluded CONFIG (our .config
has SND_SOC_LPASS_CDC_DMA=m, QDSP6 APM/PRM/LPASS set, etc.; Fedora
required.config forces only TFA9865=m), unadopted patches (none for
q6afe/codec-dma/capture), and q6prm clock-ID bugs (our 0012 is additive
TDM IDs only). Source (q6apm*, q6apm-lpass-dais, audioreach codec-dma,
soundwire/qcom, wcd939x, tx-macro post-0027), DT, and firmware
(adsp.mbn) all byte/functionally identical to v7.3/Fedora. So the
NPL-not-voted is a RUNTIME clock-tree behaviour, not a diffable source
regression — and we have NO working codec-DMA path on our own device to
diff against (only TDM works). Cracking it likely needs Fedora booted
on this unit for a live clk_summary/codec-dma register reference, or a
deep LPASS macro/q6prm clock-tree investigation. Precise known-issue;
speakers + everything else unaffected.

## 2026-11-02 — codec-DMA root cause = live SoundWire-bus transfer;
## static analysis exhausted (5 agent rounds). NPL was a red herring.

Round 5 (definitive negatives): there is NO missing codec-DMA init or
clock vote. sm8550/kaanapali tx-macro binds lpass_ver_11 (flags =
RESET_SWR only, NO HAS_NPL_CLOCK), so TX_CORE_NPL_MCLK / RX_CORE_NPL /
VA_CORE_MCLK being deviceless/0 is the CORRECT expected state (v9/sm8250
artifact, gone on v11). codec-DMA needs only TX/RX_CORE_MCLK (voted) +
LPASS_HW_MACRO/DCODEC (held 6/6) — all present. The SoundWire stream
IS prepared+enabled (sdw_prepare_stream + sdw_enable_stream,
sc8280xp.c:353-385 / sdw.c, byte-identical to v7.3). audioreach
codec-dma media-format/intf-cfg (audioreach.c:1018-1076) identical.
q6prm 0012 (additive TDM IDs) exonerated. flat-cache warning benign
(regmap touched while runtime-suspended). The Srinivas q6apm hw-pointer
fix is already in our tree. So kernel+clock+config+DT+firmware are all
exhaustively Fedora-identical and internally correct.

Localization: the two DEAD paths (RX codec-DMA via swr1, TX codec-DMA
via swr2) are exactly the two that ride SoundWire; the WORKING path
(TDM speakers) does not. Device evidence: WCD SDW slaves —
wcd_rx(sdw:2...:4)=Attached, wcd_tx(sdw:3...:3)=ALERT (persists during
capture); swr2 SWRM regs during capture show 0x010=0x40e 0x014=0x100001
but data-port regs 0x030/0x034=0x00 (no port transfer); bus clocks run
(lpass-tx-mclk->swr2 9.6MHz). No kernel errors (silent). BUT: RX
playback ALSO fails though wcd_rx is Attached — so it is NOT simply
"wcd_tx stuck in Alert"; the codec-DMA<->SoundWire port transfer fails
even with an attached slave. This is a live-bus / WCD-SDW-streaming or
DSP-codec-DMA-transfer condition.

Conclusion: static analysis is exhausted; every diffable input matches
the working Fedora port. The decisive next evidence requires a LIVE
reference we don't have on our own device (only TDM works). Paths
forward: (a) boot the Fedora iceland image on this unit once and diff
the running soundwire-device status + swr2 SWRM regs + GPR codec-DMA
graph trace during a working capture; (b) a GPR/DSP trace of the
codec-DMA graph on our side to see if the DSP faults the transfer; (c)
investigate the wcd_tx persistent-Alert (WCD-SDW interrupt/enumeration)
though it doesn't alone explain the RX failure. Tracked known-issue.
Built-in speakers + all other subsystems unaffected and working.

## 2026-11-02 — BREAKTHROUGH: codec-DMA regression identified w/
## external corroboration; sdw.c revert (0028) built

Round-6 external research (the "SWR read FIFO underflow" lead) found
the answer OUTSIDE our tree. The denialwm/phonewave project's own
FEATURES.md documents this EXACT bug as a REGRESSION on THREE devices:
 - iceland (ours): "Microphones | broken | Capture starts but no data
   arrives; aston too. Suspect 7c8cc30d7fc4"
 - aston (OnePlus 13) + nx809j: same "capture stalls now", worked
   ~Oct-22 (devices-73) -> broken ~Oct-28 (devices-139).
Commit 7c8cc30d7fc4 ("ASoC: qcom: hostless modem voice through q6apm",
Doctor Logix, Oct 24) is denialwm-ONLY — Fedora/mzakamin never carried
it. THAT is why 5 rounds of "everything matches Fedora" found nothing:
the regression is in a denialwm-exclusive commit, not a Fedora-vs-us
diff. (Same commit added the topology_uncertain latch we cleared in
round 2 and the GRAPH_OPEN handling; its codec-DMA-breaking part is the
sdw.c stream-lifecycle hunks.)

Root-cause hunk: 7c8cc30's additions to sound/soc/qcom/sdw.c — an
-EBUSY guard in qcom_snd_sdw_startup (aborts if a codec DAI stream is
already active), an err-path set_stream(NULL) clear loop, and a
set_stream(NULL) clear loop in qcom_snd_sdw_shutdown. This is the ONLY
part of 7c8cc30 in the SoundWire/codec-DMA path but NOT the (working)
TDM path. It wedges the WCD SoundWire stream -> both codec-DMA
directions starve (mic swr2 + headphone swr1), matching our Test-1
both-directions-dead finding, the wcd_tx ALERT, and the read-FIFO
underflow.

Fix: patch 0028 reverts ONLY the sdw.c hunks (voice frontend files left
in place, gated off on iceland). Verified the result == upstream v7.3
sdw.c (qcom_snd_sdw_startup + shutdown, diff-clean). All 28 patches
apply clean; sdw.c builds into snd-soc-qcom-common.ko (module-level
test loop). Bundle building; flight #38 next: expect arecord to deliver
real frames AND WCD headphone playback to return. First fix with direct
external corroboration (the denialwm devs' own open bug + suspect)
rather than inference. NOTE: denialwm may land their own fix upstream —
watch denialwm/linux-perpetua.

## 2026-11-02 — codec-DMA: root cause CONFIRMED but fix is upstream's
## to make; sdw.c revert insufficient; 0028 dropped, tracked.

Flew 0028 (sdw.c-hunks revert of 7c8cc30) as #38 RAM boot. Result:
did NOT fix codec-DMA capture. Behaviour is intermittent/racy —
PipeWire capture still freezes (decimator powers, reg 0x400=0x24, but
hw_ptr stuck at 0); raw arecord flips between 144000 silent frames and
pcm_read EIO run-to-run. So the sdw.c stream-lifecycle hunks were not
the whole regression.

Checked the other 7c8cc30 hunks for a next revert target: the
q6apm-lpass-dais.c (+13), sc8280xp.c (+68 voice links) and
audioreach.c (+361) hunks are ALL voice-gated — q6apm_voice_backend_link()
and q6apm_voice_board() return NULL/false on iceland (we are not
oneplus,aston), so they are inert here and reverting them changes
nothing. The q6apm.c latch does not fire (round 2). apr.c (+22, GPR
callback order) is shared with the WORKING TDM path. So sdw.c was the
only non-gated codec-DMA-path hunk, and it was insufficient — the
regression is a subtler interaction not isolatable to one cleanly-
revertable hunk on our tree, and a full revert of 7c8cc30 conflicts
with our speaker patches 0011-0024 (which were written on top of its
code in q6apm.c/audioreach.c/sc8280xp.c/topology.c).

Upstream status: fetched denialwm/linux-perpetua — 90 commits past our
pin, 7c8cc30 STILL present (not reverted), NO SoundWire/codec-DMA fix
among them. The denialwm devs have this open (FEATURES.md: iceland+
aston+nx809j broken, suspect 7c8cc30) with no fix yet. So nobody has
fixed it anywhere; it is genuinely an open upstream regression.

DECISION: dropped patch 0028 (verified-correct restore of upstream
sdw.c, but insufficient and could conflict with the eventual
authoritative fix; recoverable from git b2b11bf). Patch series back to
0001-0027 = exactly what is flashed on #37. codec-DMA audio (WCD
headphone-out + both mics) tracked as a precise known-issue pinned to
upstream regression 7c8cc30; the clean fix will come from the denialwm
project's own patch (watch perpetua/v7.3) or a kernel rebase past it.
Built-in SPEAKERS (TDM, confirmed + flashed) and every other subsystem
are unaffected. Net audio result: speakers work; mic/headphone await
the upstream fix. This closes the active audio push; next is the port's
other subsystems (VPU cheap next, then sensors/GNOME).

## 2026-11-02 — ROOT CAUSE PROVEN BY MEASUREMENT: perpetua 7c8cc30's
## READ_DONE payload-size check rejects the DSP's 56-byte completions

The double-check overturned the "live SoundWire/DSP starvation" verdict
with direct evidence. First, the initramfs carries ZERO audio modules
and the perpetua-only "TX_AIF1 Capture Switch" control is ABSENT on the
running system, so our module-level tests were valid (0027 really did
load; 0028-sdw really did load and really did not fix it). Then ftrace
on the capture event path during a 3 s capture: q6apm_graph_start 8,
q6apm_read 26, graph_callback 29, event_handler 0, snd_pcm_period_
elapsed 0. A kprobe on graph_callback decoding the GPR header showed ALL
16 packets are opcode 0x05001005 = DATA_CMD_RSP_RD_SH_MEM_EP_DATA_
BUFFER_V2 (READ_DONE) with clean tokens 0-7 — the DSP captures audio,
fills every buffer and reports each one; the kernel discards every
report before the client callback. Dumping the q6apm_graph object on
READ_DONE: cb == event_handler (kallsyms match), tx_data.buf non-NULL,
num_periods 8, ar_graph non-NULL — every guard passes except one: the
DSP's payload_size is 56 bytes while sizeof(struct data_cmd_rsp_rd_sh_
mem_ep_data_buffer_done_v2) is 15 x u32 = 60 (five trailing md_*
metadata words the firmware does not send). perpetua 7c8cc30d7fc4 added
"if (... data->payload_size < (int)sizeof(*rd_done)) break;" (git log
-S confirms) -> 56 < 60 -> silent drop of every READ_DONE. Upstream v7.3
has the identical 60-byte struct but NO size check (only !ar_graph) and
reads just status/buf_addr_lsw/msw — hence Fedora (no 7c8cc30) captures.
The WRITE_DONE case got the same check against a 32-byte struct with
an md_* tail -> WCD headphone playback dead the same way. This exactly
matches denialwm's fleet-wide "capture starts but no data arrives"
regression (iceland/aston/nx809j, suspect 7c8cc30). Earlier chain
summary stands: 0027 (tx-macro) fixed the analog/DAPM layer; the
"SoundWire slave Alert / read-FIFO underflow / data-port regs 0" were
side-effects of the stalled stream, not the cause; the NPL clock was a
red herring; the sdw.c hunks were not it.

Fix = patch 0028 (NEW, replaces the dropped sdw.c attempt): validate
READ/WRITE_DONE by the bytes actually dereferenced —
offsetofend(rd_done, buf_addr_msw) and offsetofend(done, status) —
keeping the NULL/bounds intent. One-hunk-pair change to
sound/soc/qcom/qdsp6/q6apm.c (snd_q6apm.ko, module-level test loop).
All 28 patches apply clean. Flight #39 next: expect READ_DONE ->
event_handler -> period_elapsed, hw_ptr advancing, real mic samples,
and WCD headphone playback restored.

## 2026-11-02 — CORRECTION to the #38 entry (test-validity audit)

The adversarial re-check found the #38 "sdw.c revert" flight was not a
proven test: sound/soc/qcom/sdw.c builds into snd-soc-qcom-SDW.ko
(Makefile: snd-soc-qcom-sdw-y := sdw.o; sc8280xp imports
qcom_snd_sdw_startup/shutdown from it), NOT snd-soc-qcom-common.ko as
the #38 entry stated. The on-tablet sha I verified (qcom-common
73c82991) is byte-identical across every build since Oct 30 because
common.c never changed — it proved nothing. The full-tree
rsync --checksum very likely did carry the changed snd-soc-qcom-sdw.ko
(211cab73 vs the pre-revert cbb4ccd8), but that was never verified on
the device, so #38's negative result is unproven. The verifier also
showed those sdw.c hunks mechanically cannot cause a silent
RUNNING/hw_ptr=0 stall (the -EBUSY guard runs in link startup before
the stream is active; the clear loops only on failed open/close), so
even a valid #38 would have been negative — consistent with the later
kprobe root cause (q6apm READ_DONE payload-size check). Lesson for the
runbook: after a module-level fix, verify the sha of the .ko that the
patched FILE builds into (check the Makefile), on the device, after
the boot — and that it is actually loaded (lsmod). 0027's #37 test was
valid (lpass-tx-macro.c -> snd-soc-lpass-tx-macro.ko, sha 5425c7e0 !=
pre-fix 5a1bf38a, behaviour changed). Initramfs shadowing excluded
(initrd carries only gpio-sbu-mux + qrtr).

Addendum (same day): on-tablet sha of snd-soc-qcom-sdw.ko.zst reads
211cab73 = the REVERTED build, so the full-tree rsync did carry the
#38 fix and #38 WAS a valid negative test (only my hash check looked
at the wrong file). Consistent with the real cause. Corroboration for
0028: Reixo0's nx809j kernel commit fcabe5fd25c7 "ASoC: qcom: q6apm:
accept read-done replies without metadata" is the IDENTICAL one-line
fix (offsetofend(typeof(*rd_done), buf_addr_msw)); the AudioReach SPF
engine source (rd_sh_mem_ep_api.h) defines READ_DONE v2 as 14 x u32 =
56 bytes with no "offset" word, i.e. the kernel struct carries a
spurious field. Pre-fix on-tablet snd-q6apm.ko.zst = dcb101ed (the
#39 flight must show a different, loaded sha).

## 2026-11-02 — FLIGHT #39: MIC CAPTURE FIXED AT THE KERNEL (0028 PROVEN)

Kernel #39 (0001-0028, bundle a4060fbb) RAM-booted; fixed snd_q6apm.ko
(76954e7e, != pre-fix dcb101ed) verified on disk AND loaded. Raw
`arecord -D hw:0,2 -f S16_LE -r48000 -c2 -d4` with the UCM Mic device
enabled: READ_DONE packets 36, ALL payload_size 56; event_handler 36;
snd_pcm_period_elapsed 36 — every DSP completion now reaches the client
(was 0/0). pcm2c state RUNNING, hw_ptr 93599 and advancing (was frozen
at 0). arecord exit 0, no EIO. Mid-capture HW: DEC0/DEC1 reg 0x400/
0x480 = 0x24 (CLK_EN, unmuted), MIC BIAS1 On, ADC1 On, TX SWR_INPUT0
On, TX DEC0 MUX On, TX_AIF1 Capture On. Captured content: 374882 of
384000 samples nonzero, max|x| 2543 = REAL room audio through the
mics. A5 (mic capture) is RESOLVED at the kernel level by 0028.

Correction from the same flight: the first "mic" run on this boot
targeted node 50 by cached id; on THIS boot node 50 is still listed as
"Internal microphones" but pw-record against it produced 399
WRITE_DONEs (playback), pcm2c never opened, decimators 0x04, zeros —
i.e. PipeWire's UCM-derived source node does NOT open hw:0,2. So the
remaining mic item is PURELY USERSPACE (WirePlumber/UCM source
wiring), not kernel. Headphone (hw:0,1): WRITE_DONE arrives at
plsz=32 (passes even the old check — write-done size was never the
headphone cause); plays 4 periods then pcm_write EIO — a separate RX
issue, parked behind mic userspace wiring.

Node-id lesson: PipeWire node ids are per-boot; find the source BY
NAME ("Internal microphones"), never by a cached number.

## 2026-11-02 — PipeWire mic capture WORKS; A5 CLOSED end to end

pw-dump: node 50 = alsa_input.platform-sound.HiFi__Mic__source
(Audio/Source, api.alsa.path hw:OnePlusPad4,2 — correct) and it was
ALREADY the default source. The earlier zero-captures were a tooling
artefact: `pw-record --target 50` (numeric) was not honoured and
pw-link showed the stream linked to HiFi__Speaker__sink:monitor_FL/FR
(hence WRITE_DONEs + silence). `pw-record --target
alsa_input.platform-sound.HiFi__Mic__source` (by NAME) links to
Mic__source:capture_FL/FR. Result: DEC0/DEC1 0x24, MIC BIAS1/ADC1/
TX_AIF1 Capture On, pcm2c RUNNING hw_ptr 109439, READ_DONE 120 ->
event_handler 120 -> period_elapsed 120, capture 228352 frames
(4.76 s), 417061 nonzero samples, max 2287, RMS -42.4 dBFS = real
room audio through the desktop path. Apps using the default source
get the mics. Mic capture is DONE (kernel 0028 + existing 0.2.17 UCM/
WirePlumber userspace). Kernel #39 (0001-0028) is RAM-booted, NOT yet
flashed — flash to make the mic fix permanent. Remaining audio item:
WCD headphone-out (hw:0,1) plays 4 periods then EIO with a guessed
manual route and NO headset plugged in; needs a headset + a proper
Headphones UCM device to test for real. Audio ladder A6 (PipeWire
limiter chain) and A7 (gain raise to 8192) remain as planned.

## 2026-11-02 — #39 FLASHED: microphones permanent; voice loopback
## confirmed. C4 core audio complete (speakers + mics).

Flashed boot_b with the #39 bundle (a4060fbb, patches 0001-0028). On
the fresh storage boot: boot_b sha == bundle, slot B re-marked
bootable+successful, kernel #39, fixed snd-q6apm (76954e7e) loaded,
card OnePlus-Pad4 registered, touch/wifi/BT coldplug — no regressions.
Voice loopback on that same cold boot: pw-record from
alsa_input.platform-sound.HiFi__Mic__source for 5.18 s captured the
owner speaking at peaks 4961/5317 (ch0/ch1), RMS -35.0/-33.7 dBFS
(ambient earlier ~2300 peak / -42 dBFS), then pw-play rendered it
through the TDM speakers at the bring-up cap. The complete chain —
mics -> WCD9395 -> SoundWire -> tx-macro -> codec-DMA -> ADSP ->
q6apm (0028) -> PipeWire -> speakers — works from storage with no PC
in the loop.

Audio status: SPEAKERS working + flashed; MICROPHONES working +
flashed (kernel 0028 + 0.2.17 UCM/WirePlumber). Remaining audio
ladder: A6 PipeWire speaker-protection chain (swh-plugins limiter,
raw-sink demotion), A7 raise VOL_CTRL_MAX 2056 -> 8192 (stock
ceiling) only after A6 is default, wired headphones (hw:0,1 plays 4
periods then EIO; needs a headset + a Headphones UCM device), BT
pairing test, mic noise-floor check vs Fedora's -64 dBFS (ADPT
disable 0059 is in). Upstream: 0028 should be offered to denialwm
(their open iceland/aston/nx809j regression; Reixo0 carries the same
fix as fcabe5fd25c7).

## 2026-11-02 — A6 speaker-protection chain (0.2.18) + A7 prepped

Interim lever: the PipeWire speaker sink soft volume was 0.40 (plus
the -12 dB DSP cap) — the owner heard playback "like 25%". Raised the
soft volume to 1.0 (wpctl; WirePlumber persists it) — safe, the 2056
DSP cap still bounds everything. Owner-confirmed louder replay.

A6 (0.2.18): ported the Fedora chain verbatim — /usr/share/pipewire/
pipewire.conf.d/62-iceland-speakers.conf (filter-chain sink "Speakers"
= effect_input.speakers: 4th-order 150 Hz HPF -> stock-tone EQ cuts ->
sc4 compressor 2.5:1 over -24 dBFS +9 dB make-up -> fast_lookahead_
limiter at -1 dBFS; flags ifexists+nofail; target.object = our
alsa_output.platform-sound.HiFi__Speaker__sink), /usr/share/wireplumber/
wireplumber.conf.d/62-iceland-speaker-raw.conf (raw sink -> "Speakers
(raw, unprotected)", priority.session 100), /usr/libexec/iceland/
iceland-speaker-default + user unit (WantedBy wireplumber.service,
enabled --global in postinst) which sets effect_input.speakers as the
CONFIGURED default (WirePlumber 0.5 lists filter sinks under Filters
and never picks them by priority). Depends += swh-plugins 0.4.17
(LADSPA sc4_1882 + fast_lookahead_limiter_1913 in /usr/lib/ladspa).
On-device: chain nodes present (plugins loaded), raw sink demoted,
effect_output.speakers -> raw sink linked, voice recording played
through the chain. Packaging bug found + fixed: build-device-package.sh
restored exec bits with a non-recursive chmod usr/libexec/* so the
promoter in usr/libexec/iceland/ shipped 0644 ("Permission denied");
now `find usr/libexec -type f -exec chmod 0755`. Promoter verified
manually: "configured default output effect_input.speakers",
wpctl @DEFAULT_AUDIO_SINK@ = Speakers.

A7 prepped (not deployed): topology rebuilt at VOL_CTRL_MAX=8192 into
out/tplg-8192/ (sha d8f4b5f3, == the earlier reference build —
reproducible); 0.2.19 with the UCM Speaker pin AND FixedBootSequence at
8192. Deploy = stage the 8192 tplg to /lib/firmware/qcom/kaanapali/ +
install 0.2.19 + reboot (rootfs-only; the flashed #39 kernel is
untouched), then verify control max 8192, chain default, listening.

## 2026-11-02 — A7 deploy hit an unrelated boot race: audio stack
## deferred when the ADSP GPR services never registered

A7 deployed (8192 tplg d8f4b5f3 staged + 0.2.19 UCM pin 8192, asound.
state wiped, `sudo reboot`). On that boot: "--- no soundcards ---".
NOT the display lottery (fb0 up, backlight 2047) and NOT A7 (the 8192
topology is structurally identical to the proven 2056 one — the
generated conf differs in exactly three `max` lines; binary
reproduces). /sys/kernel/debug/devices_deferred told the story:
7660000.codec (va_macro) "unable to get macro clock" -> 6ae0000/6aa0000/
6b00000/6ac0000.codec "supplier 7660000.codec not ready" -> 6ad0000/
7630000.soundwire "wait for supplier pinctrl@7760000 rx/tx-swr-active-
state" (7760000.pinctrl itself deferred) -> sound "snd-sc8280xp:
Primary TDM Playback: error getting cpu dai name". Root: the macro
clock comes from q6prm (DSP PRM clock service over GPR); dmesg on that
boot had NO "gprsvc:service" registrations at all although remoteproc
adsp was "running" — the ADSP GPR/APR services did not come up, so
q6prm never probed and everything audio stayed deferred past the
deferred-probe window. A plain reboot: card registered at 0 minutes,
deferred list clean. => intermittent ADSP GPR-registration race.
TRACKED (A8 hardening): adopt Fedora 0130 (ADSP reserved memory
0x4c00000 -> 0x5000000, "the signed ADSP image spans 0x5000000") and
0194 (ADSP remote-heap no-map) — the most plausible fixes for a flaky
ADSP bring-up; census how often it recurs. Runbook: after any reboot,
confirm /proc/asound/cards before audio tests; if empty, check
devices_deferred, then reboot.

## 2026-11-02 — A7 PASSED: speakers at the STOCK ceiling behind the
## protection chain. Audio ladder A0-A7 COMPLETE.

On a good boot (card at 0 min, deferred list clean): control
"stream0.vol_ctrl0 MultiMedia1 Playback Volu" max=8192, value 8192
(0.2.19 UCM FixedBootSequence + Speaker pin); a write of 9999 pins at
8192 (amixer client clamp + kernel 0021 clamp). iceland-speaker-default
active on the fresh boot, @DEFAULT_AUDIO_SINK@ = effect_input.speakers.
3 s -20 dBFS tone through the chain at the stock ceiling: effect_output
-> raw sink linked, ALL SIX TFA9865 reg 0x12 = 0x0929 (MANSTATE 9,
operating), zero new dmesg. Mic sanity on the 8192 topology: DEC0 0x24,
151552 frames, 266098 nonzero, max 2742. Banked: 8192 tplg into
out/rootfs-overlay (d8f4b5f3), build-audio-topology.sh default 8192,
manifest updated. A7 is rootfs-only (firmware file + 0.2.19) — already
permanent on the tablet; kernel #39 flashed unchanged.

AUDIO STATUS: speakers at stock loudness with HPF/EQ/compressor/-1 dBFS
limiter protection as the default sink; microphones working (kernel
0028 + UCM); all permanent. Open audio items: (1) ADSP GPR-registration
boot race -> whole audio stack deferred, seen once (hardening: Fedora
0130/0194 ADSP memory patches, a kernel/DT flight); (2) wired
headphones (hw:0,1 plays 4 periods then EIO; needs a headset + a
Headphones UCM device); (3) BT audio pairing test; (4) mic noise-floor
check vs Fedora's -64 dBFS; (5) offer 0028 upstream to denialwm.

## 2026-11-02 — ADSP boot-race hardening prepped: patch 0029 (Fedora/
## infiniti 0130, ADSP reserved memory 0x4c00000 -> 0x5000000)

Rationale: "the signed ADSP image spans 0x5000000 bytes" but our
kaanapali.dtsi reserves 0x4c00000 at 0xa1400000 — the last 4 MiB of
the signed image lie outside the carveout, so Linux can allocate those
pages and corrupt the DSP: a textbook cause of an INTERMITTENT ADSP/
GPR bring-up failure (works until the overlap is touched), matching the
once-seen "no gprsvc registrations -> q6prm never probes -> whole audio
stack deferred" boot. Applies cleanly as 0029 (one-line DT change ->
Image/DTB rebuild, bundle flight, flash). Fedora 0194 (ADSP remote-heap
no-map) is NOT adopted: it conflicts and is a prerequisite for a
linux-next fastrpc backport we do not carry. Proof of the race fix is
statistical (census boots); 0029 is correct on its own merits.

## 2026-11-02 — CORRECTION: 0029 was a no-op; the real audio boot race was
## the userspace pd-mapper. FIXED (rootfs-only, 0.2.20), 10/10 reboots clean.

0029 withdrawn. The claim behind it ("the signed ADSP image spans 0x5000000
but the carveout is 0x4c00000") is true of kaanapali.dtsi — measured: the
loadable ELF span of qcom/kaanapali/iceland/adsp.mbn is exactly 0x5000000
(0x9f300000..0xa4300000, 80.0 MiB; ph51 is real code/data ending 1.3 MiB
past the old boundary) — but it does not apply to this device: the board
file kaanapali-oneplus-iceland.dts:21 does `/delete-node/ &adspslpi_mem;`
and redefines adspslpi@a1400000 at :223 with `0x5000000`. The live DT on
kernel #39 already reads `00 00 00 00 a1 40 00 00 00 00 00 00 05 00 00 00`
and /proc/iomem starts System RAM at 0xa6400000. The DTB with and without
0029 is identical for iceland, so the "hardening flight" would have tested
nothing. Removed from the series (28 patches, 0001-0028); the mdt_loader
bounds check (drivers/soc/qcom/mdt_loader.c:397 "segment outside memory
range") would have refused the image outright had the carveout been short,
which is the tell I should have checked first. Lesson, again: measure the
live device before adopting a sibling's fix.

The actual race, from the persistent journal (41 boots on this rootfs):
three boots (-33, -22, -1) had "no soundcards". Signature in every one:
ADSP "is now up" at ~2.3 s as always, then

    PDR: service lookup for avs/audio failed: -6

and never a single "Adding APR/GPR dev". -6 = -ENXIO = the ADSP's service
locator answered but did not list avs/audio in msm/adsp/audio_pd.
pdr_interface.c:448 returns without clearing need_locator_lookup, and
pdr_locator_work only re-runs when a locator server (re)appears — so one
wrong answer leaves audio dead until the next reboot (q6prm never probes,
va_macro "unable to get macro clock", every macro/swr/card deferred).

Why the ADSP sometimes did not list it: two protection-domain mappers were
answering the DSP's domain query. The kernel's qcom_pd_mapper (=m,
autoloaded on the qcom_common.pd-mapper auxiliary device) carries the
kaanapali table (qcom_pd_mapper.c:394 kaanapali_domains = adsp audio, ois,
root, sensor + cdsp root). Ubuntu's protection-domain-mapper package also
runs pd-mapper.service, which reads JSON service lists from /lib/firmware
— and the only one present is adspr.jsn (the ADSP root PD). Census of all
41 boots, "Started pd-mapper.service" time vs the PDR outcome line:
every failure had the userspace mapper up BEFORE the lookup (3 failures in
8 such boots: -1 by 60 ms, -22 by 91 ms, -33 by 77 ms); 0 failures in the
22 boots where it came up after. qrtr-ns.service is the kernel name
service's dormant twin ("nameserver already running, going dormant").

Fix: mask pd-mapper.service and qrtr-ns.service (device package 0.2.20
postinst; postrm unmasks on purge). Rootfs-only — no kernel change, no
flash. Applied live first (`systemctl mask --now`, mic still capturing),
then an automatic 10-cycle reboot census over usb0: 10/10 boots published
the audio PD at 2.29-2.38 s ("PDR: Indication received from
msm/adsp/audio_pd"), card present, 2 GPR services each time. Not added:
early loading of qrtr_smd/qcom_pd_mapper via modules-load.d — no evidence
the kernel mapper was ever late (0/22), so it stays one variable per flight.

Also measured on the way: adsp.mbn loadable span 0x5000000 (the board DT
is right); CoreSight TNOC `111b8000.tn` is the only entry in
devices_deferred (clock from aoss_qmp; harmless, not audio).

## 2026-11-02 — Repository published: github.com/jstockdale/ubuntu-oneplus-pad-4

Before the first push: history rewritten to drop out/kernel (a 39 MiB
Image committed with the 2026-10-30 gadget-serial work) and out/ramdisk —
148 commits kept, pack 424 KiB; full-history scan for credentials (none;
the Wi-Fi profile was only ever applied by hand on the device) and device
identifiers (only the fastboot serial in four provenance notes, kept on
purpose). Licensing made explicit: BSD-3-Clause for everything this port
wrote (SPDX headers on every script and config that takes a comment),
GPL-2.0-only for kernel/patches (From/Signed-off-by completed on our
own patches), MIT inherited by the three PipeWire speaker files from
tb323fu-linux and acknowledged for the four scripts derived from the gts9u
port; the Fedora iceland port's userspace (UCM, chain adaptation) carries
attribution and a note that that repository declares no license. 0028 is
prepared for Perpetua in docs/upstreaming.md. README rewritten with the
"heavy development" banner at the top and the verified status table;
hardware-status.md brought up to date.

## 2026-11-02 — 0028 upstream status: Perpetua fixed READ_DONE itself today

While preparing the submission (upstream head 5c1eafa7b755 still had both
strict checks), perpetua/v7.3 moved to b7d639cfb282 and gained
9ba37ef1db70 "ASoC: qcom: q6apm: accept short read-done responses"
(Doctor Logix, 2026-11-02): READ_DONE now requires
offsetofend(typeof(*rd_done), buf_addr_msw) — our 0028 READ_DONE hunk,
with the comment "Kaanapali's DSP sends 56 bytes, short of the metadata
fields at the end". So the microphone regression is fixed upstream
independently (third implementation of the same fix: ours, Reixo0's
fcabe5fd25c7, theirs). Consequences: 0028's READ_DONE hunk is dropped at
the next pin bump (pin must pass 9ba37ef1db70); the WRITE_DONE hunk,
which upstream still lacks, has no observed failure behind it on this
device (its DSP sends the full 32 bytes) and is prepared as a one-line
consistency patch (branch q6apm-write-done-payload-size in the local
clone, docs/upstreaming.md) for the owner to open if wanted.

Also seen on the branch since our pin, worth the next pin bump: kaanapali
CPU passive cooling for every board (8bd03159587a), qcom_battmgr asking
Oplus PD sources for 9 V (006b67a31bae), ath12k PCIe DRV wake knobs
(476ac2f9e476), dpu/dp fixes for DisplayPort over USB-C.

Bundle note: the 29-patch build kicked before 0029 was withdrawn did NOT
produce a bundle. Its compile completed (every module linked), but the
script's staging steps failed with exit 127: bash reads a script by byte
offset as it runs, and three header lines (the SPDX/MIT notice) were
inserted at the top of scripts/build-mainline-kernel.sh while it sat in
the long make; on return bash resumed mid-comment and executed "------"
as a command. Self-inflicted; the kernel is fine. out/ is unchanged
(Image c242a7ed, DTB 7a366caa, 938 modules, bundle a4060fbb = #39, all
re-hashed). The compiled 29-patch DTB left in the build directory is
byte-identical to #39's (cmp, 7a366caa) — the build-level proof that
0029 changed nothing for this board. Nothing to fly or flash; #39 stays
on boot_b. Rule, added to the runbook: never edit a script while it is
running. The tablet's initramfs regenerated by 0.2.20 (0e12c8cf) is
staged at out/initrd.img-7.3.0+.post-0.2.20 for the next bundle build.
