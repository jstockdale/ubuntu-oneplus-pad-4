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
