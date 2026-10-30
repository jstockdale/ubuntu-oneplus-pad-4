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
