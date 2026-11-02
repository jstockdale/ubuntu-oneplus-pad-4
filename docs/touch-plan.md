# Touch bring-up plan (C2): NT36536 TDDI on the mainline panel

Written 2026-11-01 from source research only — no device contact, no tree
edits. Kernel of record: perpetua pin `7c98a10e6bb75d64a9f2e7b1e152ad1234a38659`
(worktree `/srv/ubuntu-iceland/build/linux-src-iceland`; its nt36536 driver
directory is byte-identical to the pristine `/srv/ubuntu-iceland/linux-perpetua`
— verified by diff today, so every "our tree" citation below is also a
perpetua-upstream fact). Current bundle: `out/bundle/boot.img`
(kernel_release 7.3.0+, built 2026-11-01T22:11, patches 0001–0006).

Status quo: display is Linux-driven (DRM msm, GL Weston on DSI-1, porting-log
2026-11-01), and `nt36536_ts` is blacklisted on the rootfs
(`packaging/ubuntu-iceland-device/usr/lib/modprobe.d/iceland.conf:1-4`)
because "the TDDI touch probe resets the live panel IC before deferring."
This plan takes touch from blacklisted to shipped, one variable per flight.

## Safety rails (non-negotiable, inherited + touch-specific)

- **RAM boots only; nothing flashed for touch testing.** Release-kernel
  `fastboot boot` flights, normal environment, manual `modprobe` first —
  the blacklist is bypassed by name-modprobe by design (runbook §9).
- **No diag-kernel touch flights, ever.** The diag DTS disables `&spi19`
  wholesale (`scripts/make-diag-bootimg.sh:189-193`) and the display; and the
  WLAN hunt proved the diag cmdline context can make legal sequences lethal
  (porting-log 2026-11-01 "WIFI WORKS" entry). Touch needs the opposite of
  diag: a live panel.
- **One variable per flight. One serial listener. Never leave
  `90-flight.patch` in `kernel/patches/` after a flight build** (release
  builds apply everything there — wifi-plan §4.0 precedent).
- **`nt36536_ts` stays blacklisted until the ladder below passes AND a
  fixed kernel is flashed** (the pwrseq_qcom_wcn flash-first sequencing rule,
  porting-log 2026-11-01, applies verbatim to touch).
- A dead panel in a flight is recoverable: DPMS cycle re-runs the panel's
  prepare (hardware reset + full re-init), and worst case is a reboot of a
  RAM boot. Nothing persistent is at risk while the rails hold.

---

## 1. Findings

Legend: **[V]** verified in a tree/image we hold (cited file:line);
**[S]** verified in a sibling port's tree/scripts; **[I]** inferred.

### 1.1 Hardware and DT facts

- **[V]** Our touch node: `kaanapali-oneplus-iceland.dts:1282-1302` —
  `&spi19` (status okay) → `touchscreen@0`, `compatible =
  "novatek,NVT-ts-spi"`, `spi-max-frequency = <12000000>` (:1289),
  `irq-gpios = <&tlmm 158 0x2002>` (:1290), `novatek,pen-support` (:1292),
  **`panel = <&display_panel>`** (:1294), `firmware-name =
  "novatek/novatek_nt36536_fw.bin"` (:1296), `touchscreen-size-x = <24000>`
  / `-y = <33920>` / `-inverted-x` / `-swapped-x-y` (:1297-1300).
  **No `reset-gpios`.** Identical in pristine perpetua (worktree diff today
  shows only bootargs/WLAN/regulator deltas in this DTS).
- **[V]** SPI controller: `spi19` = `qcom,geni-spi` @0x1a80000, QUP wrap4
  SE0, GPI DMA, pins gpio48/49/50 (data/clk) + gpio51 (CS), drive 6 mA,
  bias-disable (`kaanapali.dtsi:2199-2224, 5716-5730`).
- **[V]** The panel node owns the only hardware reset of the IC:
  `display_panel` `reset-gpios = <&tlmm 171 GPIO_ACTIVE_LOW>`
  (`kaanapali-oneplus-iceland.dts:1077`), dual-DSI, compatible
  `"oneplus,iceland-nt36536"` (:1056). TDDI = touch and display are one
  chip; the touch side has **no reset line of its own** — all touch-driver
  "resets" are SPI register writes.
- **[V, downstream]** Stock dtbo (re-extracted today from
  `factory/fcap/part-dtbo_a.img`, entry 00, scratchpad `dtb-work/`): node
  `nt36536@0`, compatible `"novatek,nf_nt36536"`, `spi-max-frequency =
  <0xb71b00>` (= 12 MHz, matches), `irq-gpio = <&tlmm 0x9e 0x2002>`
  (= gpio 158, matches — our 0x2002 flag cell is a downstream-habit copy),
  `cs-gpio` = gpio 0x33 (= 51, matches), **no reset-gpio** (matches),
  `touchpanel,panel-coords = <0x5dc0 0x8480>` (= 24000×33920, matches our
  size props), `touchpanel,tx-rx-num = <0x3c 0x28>` (= 60×40, matches the
  driver defaults `nt36xxx.h:68-69`), plus
  `lcd_trigger_load_tp_fw_support`, `noflash_support`, `incell_screen`,
  `fw_update_in_probe_with_headfile`, `firmware_name = "0x2XN251CN00"`
  (panel model XN251 = the HUAXING panel; a single FW variant on this
  device). Downstream also has one touch pinctrl state (likely INT bias) that
  neither mainline DT carries — flag as a contingency only.
- **[I]** `0x2002` in `irq-gpios` is downstream `IRQF_ONESHOT|
  IRQ_TYPE_EDGE_FALLING` leakage into a GPIO cell. Our driver ignores DT
  trigger flags and hardcodes `INT_TRIGGER_TYPE IRQ_TYPE_EDGE_RISING`
  (`nt36xxx.h:48`); both sibling ports run exactly this and touch works, so
  the edge choice is not a flight variable. Revisit only if events stutter.

### 1.2 The driver, end to end (our tree = perpetua)

Files: `drivers/input/touchscreen/nt36536/{nt36xxx.c (1792 l), nt36xxx.h,
nt36xxx_fw_update.c (901 l), nt36xxx_mem_map.h}`; module `nt36536_ts`
(`CONFIG_TOUCHSCREEN_NT36536_SPI=m`, build `.config:2994`); vendor Novatek
"host download / no-flash" driver (FW lives in IC SRAM, re-downloaded by the
host after every IC reset).

Reset inventory (all SPI writes):

| action | write | where defined | callers |
|---|---|---|---|
| eng reset | 0x5A → `ENG_RST_ADDR` 0x7FFF80 (`nt36xxx.c:48`) | `nvt_eng_reset()` :457-463 | **probe :1276**; legacy (non-hw-crc) download `nt36xxx_fw_update.c:786` |
| bootloader reset | 0x69 → `swrst_sif_addr` (0x1FB43E for NT36536, `nt36xxx_mem_map.h:108-112`) | `nvt_bootloader_reset()` :504-517 | chip-ID detect :1084 (×5 retries ×3 reg tables); hw-crc download `fw_update.c:709` |
| sw reset / idle | 0x55 / 0xAA → swrst_sif | :473-495 | ESD recovery :933 |

Probe sequence (`nvt_ts_probe`, `nt36xxx.c:1210-1491`), annotated:

1. :1217-1255 alloc, `spi_setup` (mode 0, 8 bpw; full-duplex required).
2. :1258 `nvt_parse_dt` (:740-781): `irq` gpiod; **optional `reset` gpiod
   acquired asserted** (`GPIOD_OUT_HIGH`, :756 — NULL on our DT, no-op);
   `firmware-name` → `ts->fw_name` (:774-778).
3. :1267-1273 **panel-follower registration**: `drm_is_panel_follower()`
   keys on the `panel` DT property; `devm_drm_panel_add_follower()`
   **return value ignored** — if the panel driver hasn't registered the
   panel yet this is a silently-lost `-EPROBE_DEFER`
   (`drm_panel.c:480-499` via `find_panel_by_dev`).
4. :1276 **`nvt_eng_reset()` — unconditional, before any panel check.**
   Then :1277 deasserts the (absent) reset gpio, :1280 10 ms.
5. :1282-1291 the panel gate: poll `ts->panel_on` 6×200 ms, then
   **`-EPROBE_DEFER`** ("panel wait failed"). `panel_on` is set only by the
   follower callback — so when the panel isn't up, **the probe has already
   eng-reset the IC and then abandons it** (root cause, §2).
6. :1294 chip-ID detect (`nvt_ts_check_chip_ver_trim_loop`, :1176-1195 →
   :1062-1166): bootloader-resets the MCU per attempt. NT36536 IDs map to
   `NT36532_hw_info` → `hw_crc = HWCRC_LEN_3Bytes`, auto-copy
   `CHECK_TX_AUTO_COPY_EN` (`nt36xxx_mem_map.h:638-643, 702-707`): all
   firmware downloads take the **hw-crc path (bootloader reset only, no eng
   reset)** — `nvt_download_firmware_hw_crc()` `fw_update.c:700-764`.
7. :1307-1351 input device; **`touchscreen-size-x/y` are mandatory**
   (:1334-1339 fails probe without them — a perpetua rework; the Fedora
   driver variant has no such requirement, §1.4).
8. :1390-1403 IRQ: `gpio_to_irq(158)`, threaded, `IRQ_TYPE_EDGE_RISING |
   IRQF_ONESHOT`, disabled immediately.
9. :1410-1420 **first FW download queued at 0 delay** on `nvt_fwu_wq`
   (`Boot_Update_Firmware` → `nvt_update_firmware(fw_name)`,
   `fw_update.c:894-901, 837-884`), under the vendor comment :1418
   *"please make sure boot update start after display reset(RESX)
   sequence"*. Download = request_firmware → parse ("NVT"/"MOD" end flag,
   FW_VER+BAR==0xFF, `fw_update.c:41-68, 361-373`) → bootloader reset →
   write ILM/DLM/overlays to SRAM → CRC → `BOOT_RDY` → wait
   `RESET_STATE_INIT`. **No REK wait in the boot path** (REK only in
   resume, below).
10. :1422-1435 event workqueue, `resume_work`, IRQ enabled. Probe returns 0.

Panel-follower hooks (:1699-1731): `.panel_prepared` → `panel_on = true`,
queue `resume_work` (no-op if `event_wq` not created yet, i.e. during the
probe-time immediate callback); `.panel_unpreparing` → `panel_on = false` +
`nvt_ts_suspend`. Resume (`nvt_ts_resume` :1651-1696) re-downloads FW and
**waits for `RESET_STATE_REK`** under the vendor comment :1672 *"please make
sure display reset(RESX) sequence and mipi dsi cmds sent before this"*.
Suspend (:1582-1642) composes a deep-sleep command but **never writes it**
(:1603-1606 — dead code; harmless under follower use, the panel power-cycle
suspends the IC).

Other load-bearing driver facts:

- **[V]** ESD/WDT recovery: IRQ handler patterns 0x77 / 0xFD / 0xFE trigger
  release-events + **FW re-download on a live panel** (:928-947) — the
  vendor explicitly supports mid-session downloads under a scanning display.
- **[V]** `rmmod` is unsafe: `nvt_ts_remove` (:1500-1554) frees `ts`
  (:1549) and also `mutex_destroy`s a never-initialized `pen_switch_lock`
  (:1506); the devm follower release then runs *after* remove and the
  `panel_unpreparing` callback writes `ts->panel_on` through a freed
  pointer (:1716-1724). `bTouchIsAwake=0` (:1504) makes the suspend body
  early-return, but the UAF write stands. **Reboot between driver swaps,
  never rmmod** (§7).
- **[V]** drm_panel core semantics in our tree: followers registered while
  the panel is already prepared/enabled get the callbacks **immediately at
  registration** (`drm_panel.c:589-622`, prepared :605, enabled :611);
  `drm_panel_enable()` fires `panel_enabled` followers even when the panel
  driver has no `.enable` op (`drm_panel.c:243-283`) — which ours doesn't.

### 1.3 Panel-driver coordination (display side)

- **[V]** Our panel driver `panel-oneplus-iceland-nt36536.c` (compatible
  `"oneplus,iceland-nt36536"` :512-514, **built-in**,
  `CONFIG_DRM_PANEL_ONEPLUS_ICELAND_NT36536=y`, `.config:4899`; generic
  `panel-novatek-nt36536.c` binds only `"csot,pp8807hb1-1"` :469-470 and is
  **off** :4898): `.prepare` = regulators on → **reset pulse on tlmm 171**
  (:315-323: released 10 ms, asserted 5 ms, released 10 ms — physical
  high/low/high 10/5/10, identical to stock's
  `qcom,mdss-dsi-reset-sequence` per the sibling's 0108 commit) → DSI init
  sequence ending in `exit_sleep_mode` + `set_display_on` (:209, :213).
  `.disable` = display-off + enter-sleep (:348-362). `.unprepare` = reset
  asserted + regulators off (:364-372). `prepare_prev_first = true` (:490):
  prepare runs **before the DSI host streams video**.
- **[V]** `CONFIG_DRM_MSM=y` (`.config:4811`): the whole display stack and
  the panel are built-in, so on release boots the panel is prepared+enabled
  long before udev's module parade could coldplug a touch module (kernel
  console on glass at T+1 s, porting-log B.5).
- **Consequence [V+S]**: every panel prepare = hardware reset + full
  re-init of the shared TDDI IC. Whatever state a touch probe wrecks, the
  next panel prepare repairs — *when a Linux panel driver exists in that
  boot*. That is the exact difference between today and v17 (§2), and it is
  why both sibling ports run this same vendor probe safely under DRM.

### 1.4 Sibling ports: what they did about exactly this

**Fedora port (mzakamin iceland-linux, old-session clone, read-only at
`/tmp/claude-1000/-home-jstockdale-projects-arch-oneplus-pad-4/29772f33-…/scratchpad/mzakamin-review/iceland-linux/`,
base v7.3-rc7 + 132 infiniti + ~300 iceland patches):**

Touch-relevant queue, in order (`patches/0002-iceland/`):

| patch | what it does |
|---|---|
| 0009 Input: Add NT36536 touch driver | map220v's vendor driver import (same lineage as ours; see divergence below) |
| 0010 ICELAND: Add touchscreen node | same node as ours minus the size/orientation props (their driver hardcodes the transform), same 12 MHz / gpio158 / `panel` phandle / firmware-name |
| 0036 Input: nt36536: give the pen its tablet capabilities | BTN_STYLUS/BTN_STYLUS2 from the already-parsed pen_btn1/2 + axis resolution from new `touchscreen-x-mm`/`-y-mm` props — libinput refuses the pen device without them |
| 0037 dts: give the touchscreen its physical size | `touchscreen-x-mm = <274>; touchscreen-y-mm = <193>` |
| 0174 Input: nt36536: do not log the panel wait deferral as an error | `dev_err_probe(-EPROBE_DEFER)` — *proves their probe defers up to 3× per boot on the panel gate, i.e. the eng-reset-then-defer cycle runs on every Fedora boot and their panel still comes up* (the panel prepare repairs it, §1.3) |
| **0180 Input: nt36536: follow the panel's enable/disable, not its prepare** | **The TDDI sequencing fix.** At `panel_prepared` the DSI host is not streaming yet (`prepare_prev_first`), the resume-work FW download then times out waiting for REK ("retry=51, buf[1]=0xA0" — controller stuck in INIT). Observed 0.6 s after a 60→120 Hz modeset and after a display-off period; never without a modeset. Stock resumes on UNBLANK / suspends on EARLY_BLANK. Fix: switch the follower to `.panel_enabled` / `.panel_disabling` (called after the display is actually on / before it goes off, independent of the panel's own enable op). |

Driver divergence (our perpetua copy vs their final, reconstructed today by
applying 0009+0036+0174+0180 and diffing):

- Ours (perpetua) is *more* upstream-idiomatic: `touchscreen_parse_properties`
  + `touchscreen_report_pos` with mandatory DT size props and DT-driven
  inversion/swap (`nt36xxx.c:970, 1334-1339`); optional reset gpiod.
  Theirs hardcodes the swap/invert in the IRQ handler and has no reset-gpio
  handling at all.
- Ours **lacks** 0174 and 0180 (verified: `NVT_ERR("panel wait failed")`
  :1284-1285 and `.panel_prepared/.panel_unpreparing` :1727-1730).
- `nt36xxx_fw_update.c` and `nt36xxx_mem_map.h` are byte-identical between
  the two ports (diffed today).
- Their config: `CONFIG_TOUCHSCREEN_NT36536_SPI=m` + panel `=y`
  (`configs/required.config:11-13`) — same shape as ours. No touch
  blacklist anywhere in their packaging: they let it coldplug and eat the
  deferrals (0174).

**Arch/phonewave port (perpetua ecosystem, old-session clone at
`…/scratchpad/research/repos/phonewave/devices/iceland/`):** runs (apparently)
our very driver generation and solves sequencing **in userspace**:
`pad4-hardware.service` (After=systemd-udev-trigger.service) →
`pad4-hardware-init`: sha256-verifies firmware **including
`usr/lib/firmware/novatek/novatek_nt36536_fw.bin
5e9d9651…`**, runs `pad4-display-init` (waits for /dev/dri/card0 + fb0 and
reads `card0-DSI-1/status`), then `modprobe spi-geni-qcom`, **`modprobe
nt36536_ts`**, and asserts `NVTCapacitiveTouchScreen` appears in
`/proc/bus/input/devices`. I.e. **modprobe-after-display-up, on this exact
hardware, with this driver lineage, panel surviving** — the strongest
external predictor for our flight T1. (`rootfs/usr/local/sbin/pad4-hardware-init`,
`pad4-display-init`, `etc/systemd/system/pad4-hardware.service`.)

### 1.5 Firmware (all hashes verified today)

- **DT-requested name:** `novatek/novatek_nt36536_fw.bin` (DTS :1296;
  driver fallback name `novatek/nt36536.bin`, `nt36xxx.h:83`, is irrelevant
  since the DT prop wins, `nt36xxx.c:774-778`).
- **Payload:** sha256
  `5e9d96517199ce11d44db90436e5835fed7982031102f52a74b7230ad64d83e2`,
  258048 bytes. Triple-corroborated:
  1. **OUR stock ROM** (OPD2514_16.0.10.501_GLO_11.A.38; odm.img sha256
     `c7b3945e…`, PROVENANCE.json): EROFS path
     `/firmware/tp/25926/FW_NT36536_HUAXING.img` (258256 B, sha256
     `768ffdf8731a3185b4bcca786422f748c235c97d762ca3f92be1d12e3876b20c`) is
     an **"FwUp!"-magic container**; stripping the 80-byte header +
     128-byte trailer yields the payload byte-exact (reproduced today:
     `dd skip=80 count=258048 | sha256sum` = 5e9d9651…).
  2. Fedora `iceland-firmware` repo: MANIFEST.tsv row + on-disk file, same
     hash/size, same documented source and FwUp strip.
  3. phonewave `pad4-hardware-init` pins the same hash at runtime.
- **Already staged in our pipeline [V]:**
  `configs/firmware/iceland.toml:165-171` (`image = "odm"`, `source =
  "firmware/tp/25926/FW_NT36536_HUAXING.img"`, `transform =
  "fwup-strip-80-128"`) and the overlay copy
  `/srv/ubuntu-iceland/out/rootfs-overlay/lib/firmware/novatek/novatek_nt36536_fw.bin`
  re-hashed today = 5e9d9651… (staged 2026-10-29). The
  `docs/firmware-manifest.md` "Still owed — Touch" line is stale; T0 below
  closes it with an on-device check and a manifest block (§6).
- **Variants NOT to ship:** `FW_NT36536_HUAXING_FAE.img` (088a37a8…) and
  `FW_NT36536_HUAXING_TEST.bin` (144c9d8d…) are different builds;
  `LIMIT_NT36536_HUAXING.img` (4732c249…) is factory MP test limits, not
  runtime firmware.
- **Per-unit calibration: none found.** persist (factory/fcap
  part-persist.img, listed read-only today) has no touch/tp entries at the
  root or under data/engineermode/display; the NT36xxx no-flash design
  calibrates at runtime (the REK baseline). The FW is panel-model-specific
  (single HUAXING/XN251 variant on this device, §1.1) — no per-unit or
  multi-vendor selection problem.
- **Driver-side validity preconditions** the payload must meet (it does for
  both siblings): "NVT"/"MOD" sector end-flag and FW_VER+FW_VER_BAR==0xFF
  (`fw_update.c:41-68, 366-373`).

### 1.6 Cross-evidence table

| question | answer | basis |
|---|---|---|
| Does the probe reset the IC before knowing the panel state? | yes — eng reset :1276 precedes the gate :1282 | [V] code |
| Can a deferring probe leave the IC dead? | yes — defer path does no cleanup/re-download | [V] code; [V] v17 observation (porting-log :509-514) |
| Does the completed probe+download sequence kill a live DRM panel? | no on both siblings | [S] phonewave init script asserts input device with display up; [S] Fedora runs it at every coldplug |
| Does DPMS/modeset cycling break touch with our hook choice? | yes, REK timeout at panel_prepared-time resume | [S] 0180 commit evidence (R1d/R2 rehearsals); [V] our tree has the prepared-hooks |
| Is there a touch reset GPIO to misconfigure? | no — panel owns tlmm 171 | [V] both DTs, [V] downstream dtbo |
| Is firmware per-unit? | no | [V] persist listing; [S] both siblings ship one static file |
| Will udev coldplug load it once unblacklisted? | yes — modalias `of:N*T*Cnovatek,NVT-ts-spi` present in the built module | [V] modinfo on `out/kernel-iceland/modules-root/...nt36536_ts.ko.zst` |

---

## 2. Root cause of the v17 reset ("probe resets the panel IC before deferring")

**Statement.** `nvt_ts_probe()` writes the engineering-reset command (0x5A →
0x7FFF80, `nvt_eng_reset()`, nt36xxx.c:457-463) over SPI at :1276,
unconditionally, *before* the panel gate at :1282-1291. On a TDDI the touch
MCU and the display driver are one chip: the eng reset halts the running IC.
In the October diag flights the display was **bootloader-lit** — no Linux
panel driver existed in that boot (diag disables the display stack), so
when the gate then timed out and the probe returned `-EPROBE_DEFER`, nothing
ever re-initialized the IC: **reset-then-abandon**. The splash died and
stayed dead. Every deferred re-probe repeats the same write (follower
registration is devm-released on probe failure, so `panel_on` can never
become true in such a boot).

**Why the same code is survivable today [V+S]:** under mainline DRM the
panel driver owns tlmm 171 and re-initializes the entire IC on every prepare
(§1.3); and when the panel *is* up, the gate passes and the probe runs to
completion — chip-ID detect (bootloader resets) + hw-crc FW download +
BOOT_RDY — the exact sequence the vendor designed to run beneath a scanning
display (resume comment :1672, downstream `lcd_trigger_load_tp_fw_support`).
Both sibling ports run it routinely with the panel alive.

**Verified vs inferred:** the write-before-gate ordering, the ignored
follower-registration return (:1271), and the defer path are code-verified.
That the eng reset (rather than, say, accumulated deferral cycles) was the
specific killer of the bootloader splash is inferred — it is the only SPI
write the v17 probe could issue before deferring (chip-ID detect sits after
the gate), and the flight observation (porting-log :509-514, iceland.conf
comment) is consistent. Nothing in the plan depends on resolving that last
distinction: the fix is the same.

**"No-reset attach" assessment:** not meaningfully available. On our boots
nobody has downloaded touch firmware (the bootloader doesn't; only this
driver does), so the IC always needs bootloader-reset + SRAM download — a
reset-free attach to running stock FW is not our situation. The correct
reformulation is **no-touch-until-the-panel-stack-can-repair**: never write
to the IC in a boot/phase where no panel driver will re-initialize it, and
do the first download only once the display is actually up.

---

## 3. Implementation options, ranked

### Option 1 — Flights on the unmodified driver, runtime-sequenced modprobe (do first)

Exactly the phonewave model: display up → `modprobe nt36536_ts` → evtest.
Zero kernel delta; tests the vendor-designed path in the environment it was
designed for; both siblings predict success.
**Limits:** leaves the blacklist permanently necessary (coldplug on a boot
where the panel loses the DSI lottery would eng-reset-and-defer — harmless
to an already-dead display, but endless deferral noise, and the latent v17
class stays armed); and the DPMS/modeset REK bug (0180 evidence) remains —
touch can die after a blank/unblank until the hooks move.
**Upstreamability:** n/a (userspace). Shippable as an interim
`pad4-hardware.service`-style unit if the kernel fix stalls, but inferior.

### Option 2 — Small driver patch set: gate-before-reset + enabled-hooks (the fix; flights T3+)

Three independent, minimal changes to `nt36xxx.c` (one patch file each or
one series; order of adoption as listed):

- **2a (ours, new): defer with zero IC writes.** Check the return of
  `devm_drm_panel_add_follower()` (:1271) and `return dev_err_probe(...)`
  on error; move `nvt_eng_reset()` + the 10 ms settle (:1276-1280) to
  *after* the `panel_on` gate (:1282-1291). Result: a probe that defers has
  touched nothing; the first IC write happens only with a prepared panel.
  This is the direct v17 root-cause fix and makes coldplug
  safe-by-construction on lottery boots.
- **2b (adopt Fedora 0180): follower hooks → `.panel_enabled` /
  `.panel_disabling`.** Fixes the REK-timeout class after modesets and
  display-off periods (their R1d/R2 evidence); matches stock's
  UNBLANK/EARLY_BLANK ordering; our drm_panel core already calls
  `panel_enabled` followers with no panel `.enable` op (§1.2). Adopt by
  intent; the hunks apply to our file with trivial fuzz (the follower block
  is identical in both ports).
- **2c (adopt Fedora 0174): `dev_err_probe` for the deferral** — log
  hygiene, keeps the deferred-probe list informative. Merges into 2a
  naturally.

**Interaction note [V]:** with 2b, a probe on an already-enabled panel gets
`panel_enabled` at registration time (drm_panel.c:611-616) — before
`event_wq` exists, so the callback's early-return (:1706-1708) keeps probe
ordering sane and the :1419 boot-download still does the first load. With 2a
the gate needs `panel_on` set by the *enabled* hook — on a live desktop
that's immediate; on a cold boot it tracks display enable. (If a gap shows
up where the panel is prepared-but-never-enabled, the gate simply defers —
with 2a that is now free of side effects.)

**Upstreamability:** the driver is a vendor import that will never go to
mainline Linux as-is, but perpetua is our upstream and already carries its
own rework of this file; 2a-2c are exactly the kind of patch it takes.
Submit 2a+2c as one patch and 2b as a cherry-pick/port of mzak's 0180 (keep
their authorship), after our flights supply the on-device evidence. The
long-term mainline answer is a clean `drivers/input/touchscreen` driver
using the panel-follower API (which upstream built for TDDI) — out of C2
scope; note it in the porting log as a someday item.

### Option 3 — Adopt the Fedora driver wholesale

Rejected. Their remaining deltas are a *less* upstream coordinate transform
(hardcoded swap/invert vs our DT-driven `touchscreen_report_pos`) and the
pen-capabilities patch 0036. 0036 **is** worth having (GNOME/libinput
ignores the pen without BTN_STYLUS + axis resolution), but it needs adapting
to our properties flavor and new DT props (`touchscreen-x-mm/y-mm`, 274×193,
their 0037) — queue it as a C2 follow-up after the gate, not in the ladder.

### Option 4 — DT-only mitigation

None exists: no DT property gates the eng reset, and there is no touch reset
GPIO to withhold (already absent). The DT is already correct against both
the downstream extraction and the sibling (§1.1); only the orientation
props are ours-only and get validated empirically in T1.

---

## 4. Flight ladder

All flights: release-kernel RAM boot (`fastboot boot` of the current
`out/bundle/boot.img` or its T3 successor), normal cmdline, display up,
ssh + one serial listener, serial `tee` log running before every modprobe.
Record per flight: commands, dmesg excerpts, survived/died, panel state,
evtest result. A reset mid-flight lands back in flashed slot-B Ubuntu where
`nt36536_ts` is still blacklisted — safe by construction.

### T0 — prep and preconditions (any boot incl. the flashed one; no module load)

1. Firmware on device: `sha256sum /lib/firmware/novatek/novatek_nt36536_fw.bin`
   must print `5e9d9651…` (if absent: `scp` the overlay copy; the overlay
   and iceland.toml already carry it, §1.5). **No flight proceeds without
   this** — a probe without firmware is reset-then-abandon by another name
   (§7).
2. `lsmod | grep nt36536` empty; blacklist line present in
   `/usr/lib/modprobe.d/iceland.conf`; module file exists:
   `/lib/modules/$(uname -r)/kernel/drivers/input/touchscreen/nt36536/nt36536_ts.ko.zst`.
3. Display live: `cat /sys/class/drm/card0-DSI-1/status` + something on
   glass (console or Weston). `evtest` installed (it is, C0 toolkit).
4. Bookkeeping: add the §6 block to `docs/firmware-manifest.md` (moves
   Touch out of "Still owed").

### T1 — the cheapest decisive test: unmodified modprobe on a live desktop

**Change:** none (kernel, DT, rootfs all stock-release).
**Procedure:** Weston running (GL, DSI-1) or kernel console on glass; start
serial log; `sudo modprobe nt36536_ts`; watch `dmesg -w` for: probe start,
chip-ID trim ("This is NVT touch IC"), "Update firmware success", FW info
(`fw_ver/PID`, abs 24000×33920). Then `evtest` on
`NVTCapacitiveTouchScreen`: tap corners + 2-finger drag.
**Proves:** the vendor probe→download path under live mainline DRM on our
unit (the sibling-predicted result); panel survival through eng reset +
bootloader resets + SRAM download; IRQ delivery on gpio158; coordinate
orientation of our DT props (check corner mapping — if mirrored/rotated,
that is a one-line DT prop fix, its own later flight, NOT fixed in this one).
**Outcomes:**
- *Pass* (touch events, panel alive): core path proven; go to T2.
- *Touch dead, panel alive:* capture dmesg (REK/CRC/IRQ class tells which);
  likely FW or IRQ issue; stop and analyze — do not iterate blind.
- *Panel dies:* note exact dmesg line; recover with a DPMS cycle
  (`echo 4 > /sys/class/graphics/fb0/blank; sleep 2; echo 0 > …` — the
  fbdev path runs the panel unprepare/prepare, i.e. hardware reset +
  re-init; or restart Weston), confirm recovery works — that datum alone is
  valuable (recoverable ≠ v17). Escalate to Option 2 flights with an extra
  change: drop/move the probe-time eng reset entirely (the hw-crc download
  never uses it, §1.2) — one variable, T3 absorbs it.
- *SoC reset (WLAN-style):* nothing persistent lost; re-fly once to confirm
  reproducibility, then stop and research (not sibling-predicted at all).

### T2 — DPMS cycle with the unpatched driver (same boot as a passing T1)

**Change:** none. **Procedure:** with the module loaded and touch proven:
make the DPMS cycle deterministic — `pkill -x weston` (console/fbcon takes
the display), then `echo 4 > /sys/class/graphics/fb0/blank; sleep 3;
echo 0 > /sys/class/graphics/fb0/blank` (fbdev emulation runs the real
panel unprepare/prepare; with Weston still master the write may not reach
the CRTC). After unblank, `evtest` again; repeat ×3. Also, if a second
mode is exposed, one modeset toggle.
**Proves/expects:** the mzak 0180 failure class on our tree — resume FW
download at prepared-time racing the not-yet-streaming DSI host: REK timeout
("retry=51, buf[1]=0xA0") and possibly dead touch until the next cycle;
display itself should survive. Either result is a datum: failure justifies
2b with on-device evidence; survival (3/3) downgrades 2b to modeset-only
risk (still adopt it — their evidence stands).

### T3 — the patched driver (Option 2), module-swap flight

**Change (one logical change: "the C2 driver fix"):** add to
`kernel/patches/` as the next permanent numbers (0007: 2a+2c; 0008: 2b
port). Rebuild kernel (`scripts/build-mainline-kernel.sh` — applies
kernel/patches/ to the worktree) and bundle
(`make-initramfs.sh`/`build-boot-bundle.sh` per runbook §8). Build the
module (precedent: `out/build-modules-0006.log` — a targeted module build in
`/srv/ubuntu-iceland/build/linux-iceland`); on the tablet, keep the original
(`cp /lib/modules/7.3.0+/kernel/drivers/input/touchscreen/nt36536/nt36536_ts.ko.zst
/root/nt36536_ts.ko.zst.orig`), install the patched one (zstd-compressed,
same path — the pwrseq hand-replacement precedent, porting-log 2026-11-01),
and **verify the rootfs module is the patched build by sha256 against the
build artifact** (the v25 "module trap" lesson: never assume the module
followed the kernel).
**Procedure:** RAM-boot the new bundle; repeat T1's modprobe + evtest, then
T2's DPMS cycles ×3 (+ modeset if available).
**Proves:** fix correctness: probe behaves identically on the happy path;
DPMS resume now downloads at panel-enabled time → REK passes
(`nvt_check_fw_reset_state(RESET_STATE_REK)` returns before timeout), touch
alive after every cycle. Also sanity-check the deferral path if cheap: with
the panel up this needs no extra flight — code review stands in (2a is
mechanical reordering).

### T4 — 20-minute soak (same boot as a passing T3)

**Change:** none. Weston up, module loaded. Every ~2 min: touches/drags
(evtest or the desktop itself), watch dmesg for ESD/WDT recovery storms
(0x77/0xFD/0xFE patterns, :928-947), SPI errors, DPU underruns; one DPMS
cycle mid-soak. **Gate datum:** 20 min, zero panel incidents, touch
responsive at the end. (Battery note: net-positive even under desktop load,
porting-log C0 — soak is safe at current charge discipline.)

### T5 — coldplug rehearsal, 3/3 (RAM boots of the T3 bundle)

**Change (one):** comment out `blacklist nt36536_ts` in
`/usr/lib/modprobe.d/iceland.conf` on the tablet **for the session**.
**Procedure:** three consecutive `fastboot boot` cycles of the T3 bundle;
each boot: no manual modprobe — udev coldplug must load nt36536_ts (alias
verified, §1.6); check journal timing (probe vs panel-enable), panel on
glass, `evtest` contacts. **Then restore the blacklist line** before ending
the session (the flashed kernel is still the old driver until §T6 —
flash-first rule).
**Proves:** unattended boot ordering under the full parade with the fixed
driver: either the panel is up before the touch probe (expected, display
built-in) or the probe defers harmlessly (2a) and binds on a later trigger.
3/3 = the bring-up gate's coldplug criterion.

### T6 — ship sequence (leaves flight-land; follows the pwrseq precedent)

1. Flash gate per runbook §7-8: the next boot_b flash carries the already
   queued patches 0001–0006 (WLAN supplies/roles/floor + BT names) plus the
   new 0007/0008 touch fix — the flash was already pending for WLAN; one
   flash, RAM-boot-gated first.
2. Only after that flash verifies: device package 0.2.x removes
   `blacklist nt36536_ts` from
   `packaging/ubuntu-iceland-device/usr/lib/modprobe.d/iceland.conf`
   (leave a tombstone comment like pwrseq's) and installs on-device.
3. Verify 3/3 **power-on** coldplug boots on the flashed system (not
   fastboot-fed): touch works in the session each time, panel never resets.
4. Paperwork: hardware-status.md touch row → ✅ with date; porting-log
   entry; firmware-manifest block (if not done in T0); upstream 2a+2c and
   the 0180 port to perpetua; queue the pen patch (0036+0037 adaptation)
   and GNOME orientation/HiDPI work as C2 follow-ups.

**Success gate (the whole ladder, verbatim target):** `evtest` shows
contacts; the panel survives every flight; a 20-minute soak is clean; 3/3
coldplug reboots pass — only then unblacklist (and only on the fixed,
flashed kernel).

Expected timeline: T0-T2 one session (no builds); T3-T5 one session after
the patch build; T6 rides the already-planned WLAN flash.

---

## 5. Contingency levers (one variable each, only if the ladder stalls)

- **IRQ flakiness** (events stutter/stop, FW alive): try downstream's edge
  (falling) as a driver constant flight (`nt36xxx.h:48`), or add a tlmm
  pinctrl bias state for gpio158 (downstream has a touch pinctrl state we
  don't, §1.1).
- **Orientation wrong in T1:** flip `touchscreen-inverted-x` /
  `-swapped-x-y` / add `-inverted-y` in the DT (90-flight.patch DT edit, one
  flight; the driver's transform is `touchscreen_report_pos` :970).
- **REK timeout even at enabled-time (T3):** add a bounded retry of the
  download in the resume path (sibling didn't need it; only with evidence).
- **Probe-order noise at coldplug (T5):** `softdep` is useless here
  (ordering is panel-readiness, not module deps); acceptable fallback is the
  phonewave-style late-modprobe unit shipped in the device package — ship
  that rather than slipping the phase.

## 6. Firmware staging block (manifest-ready, mirrors the GPU/BT precedent)

For `docs/firmware-manifest.md` (new section "Touch (NT36536 TDDI, staged
2026-10-29, verified 2026-11-01)"; delete the "Still owed — Touch" line):

| file | sha256 | size | source | provenance |
|---|---|---|---|---|
| novatek/novatek_nt36536_fw.bin | 5e9d96517199ce11d44db90436e5835fed7982031102f52a74b7230ad64d83e2 | 258048 | OUR stock odm.img → /firmware/tp/25926/FW_NT36536_HUAXING.img, FwUp container stripped (80-byte header + 128-byte trailer; transform `fwup-strip-80-128`, configs/firmware/iceland.toml:165-171) | byte-identical to the Fedora iceland-firmware repo file (MANIFEST.tsv row, same strip documented) and to the hash pinned by the Arch/phonewave port's pad4-hardware-init; container sha256 768ffdf8731a3185b4bcca786422f748c235c97d762ca3f92be1d12e3876b20c in odm.img c7b3945e… (OPD2514_16.0.10.501_GLO_11.A.38) |

Notes for the manifest: no per-unit calibration (persist checked; REK
runtime baseline is the calibration); FAE (088a37a8…) and TEST (144c9d8d…)
variants and LIMIT_NT36536_HUAXING.img (4732c249…, factory MP limits)
deliberately not shipped. Overlay copy
`out/rootfs-overlay/lib/firmware/novatek/novatek_nt36536_fw.bin` hash-checked
2026-11-01.

## 7. What NOT to do

- **Never load nt36536_ts without the firmware staged and hash-verified
  on that boot.** A probe whose download cannot complete leaves the TDDI
  MCU halted — the reset-then-abandon mechanism that killed the v17 splash,
  now aimed at OUR panel (the probe still returns 0 with FW missing; the
  damage is silent until the screen state degrades).
- **Never rmmod nt36536_ts.** The devm panel-follower release runs after
  `remove()` has freed `ts` and writes through the dangling pointer
  (nt36xxx.c:1716-1724 vs :1549). Swap drivers by replacing the .ko.zst and
  rebooting.
- **Never test touch on a diag boot** (spi19 and the display are disabled
  there; and diag-cmdline context falsified a week of WLAN theories).
- **Never fire the ladder with the panel off/blanked.** With the unpatched
  driver a probe during prepared-but-dark windows reproduces the REK race
  instead of the result you wanted; flights specify "display up" as a
  precondition, not a nicety.
- **Never unblacklist while boot_b runs an unfixed kernel** — and restore
  the T5 session edit before ending the session. The blacklist is the only
  thing keeping a flashed-kernel coldplug from running the eng-reset-then-
  defer loop on a lottery boot (flash first, unblacklist second — the
  pwrseq rule).
- **Never leave `90-flight.patch` (or any uncommitted flight patch) in
  `kernel/patches/`** after a flight build — release builds apply the whole
  directory.
- **Never flash anything for touch testing.** No vbmeta/dtbo/vendor_boot/
  set_active writes, ever (standing rails).
- **Never poke tlmm 171** (panel reset) from userspace/gpioset or scripts:
  it hardware-resets the entire TDDI including the display. Panel resets
  belong to the panel driver alone.
- **Never dump whole-TLMM pinctrl/gpio debugfs** (XPU read-reset hazard —
  standing rail from the WLAN plan).
- **Don't ship or test the FAE/TEST firmware variants**, and don't adopt
  the Fedora driver files wholesale over ours (their coordinate transform
  would silently fight our DT size/orientation properties, :1334-1339).
- **Don't run two serial listeners** (deaf-RX false mystery), and read the
  whole log before declaring a flight dead (v18 lesson).

## 8. Reference anchors (for the flight notebook)

- Driver: `drivers/input/touchscreen/nt36536/nt36xxx.c` — eng reset def
  :457, probe eng reset :1276, panel gate :1282, chip detect :1294 (resets
  :1084), follower reg :1267-1273 (return ignored :1271), FW work :1419,
  follower hooks :1699-1731, resume REK :1673-1677, suspend dead-write
  :1603-1606, remove/UAF :1500-1554. FW update:
  `nt36xxx_fw_update.c` — hw-crc download :700-764 (bootloader reset :709),
  legacy eng reset :786, request/validate :342-400. Maps:
  `nt36xxx_mem_map.h` — NT36536 rows :702-707, NT36532_hw_info :638-643,
  hw regs :108-112.
- DTS: touch node `kaanapali-oneplus-iceland.dts:1282-1302`; panel
  :1056-1099 (reset-gpios :1077). Panel driver:
  `panel-oneplus-iceland-nt36536.c` — reset :315-323, prepare :325-346,
  display-on :209/:213, prepare_prev_first :490, compatible :512-514.
  Core: `drm_panel.c` — add_follower immediate callbacks :589-622, enable
  followers :243-283, of_drm_find_panel :480-499.
- Sibling patches (old-session scratchpad, read-only):
  `mzakamin-review/iceland-linux/patches/0002-iceland/` 0009/0010/0036/0037/
  0174/**0180** (+ panel 0007/0100/0103/0108/0214). Arch runtime model:
  `research/repos/phonewave/devices/iceland/rootfs/usr/local/sbin/pad4-hardware-init`.
- Ours: blacklist `packaging/ubuntu-iceland-device/usr/lib/modprobe.d/iceland.conf:1-4`;
  diag spi19-off `scripts/make-diag-bootimg.sh:189-193`; firmware pipeline
  `configs/firmware/iceland.toml:165-171`; C2 gate `docs/bringup-plan.md:59-69`;
  v17 record `docs/porting-log.md:509-514, 663-664`.

## 9. Outcome (2026-11-01) — ladder complete

T0–T3: root cause (probe eng-reset on live panel) fixed by 0007/0008;
the real wall was bonded-DSI command-sync orientation, fixed by 0010
(with 0009 porch correction along the way). T4: 30-min soak clean,
full 10-slot multitouch at the coordinate extremes, 60 Hz reports,
fw 0x15 / PID 0x5F9A. T5 (as flown): the RAM rehearsal turned out
never to have exercised udev (manual modprobe in the journal;
blacklist comment postdated the boot) — the flashed boots became the
true test: auto-load at t≈2.06s/2.08s, zero manual modprobes, 2/2.
The §4 boot-time-dormant quirk self-resolved via 0007's deferral:
probe at t≈2s predates panel enable, so the download rides the
panel-enable path and the engine starts live. T6: ship bundle
(7fa88c2e…) flashed to boot_b, partition sha verified, taps = 689 IRQ
edges, 0.2.16 retired the blacklist (tombstones remain in
iceland.conf). Pen reports as NVTCapacitivePen; BTN_STYLUS caps
(mzak 0036/0037 adaptation) remain the next touch-adjacent item,
then coordinate-orientation validation under a desktop.
