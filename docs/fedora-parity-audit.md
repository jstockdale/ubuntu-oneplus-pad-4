# Fedora parity audit: the NT36536 touch path, their stack vs ours

2026-11-01, C2 session two support document. Read-only audit; nothing was
built, no device touched. Companion to docs/touch-plan.md and
docs/porting-log.md (:989-1016, "the INT line is the war").

> **Outcome 2026-11-01 and status 2026-11-03.** Ranked delta 2 was the wall: with 0009 (delta 1) flown and eliminated — correct timing, fresh download, engine still dead — the one-variable flight that reverted perpetua's 5892773b169d and moved the panel's command context from dsi[0] to dsi[1] lit the engine on the first panel cycle (IRQ pulsing, 10-slot multitouch at the coordinate extremes), promoted as permanent 0010 (porting-log "TOUCH WORKS: the bonded-DSI orientation was the wall"). C2 closed that night (T6 flashed, coldplug 2/2, 0.2.16 retired the blacklist; iceland.conf is tombstones only); the level-low test module went with it. Delta 7's cosmetics landed on 2026-11-02 as 0037 (their 0036 adapted to our touchscreen_parse_properties probe), 0038 (x-mm/y-mm in the controller frame) and 0039, and the pen then grew its own ladder (0040–0042, 0063 — touch-plan.md status note). Deltas 3–6 and 8–9 were never flown and stay parity backlog for a kernel refresh; flashed boots have run the apps SMMU and the stock vendor_boot cmdline (no ignore_unused crutches) since 2026-11-01 with the panel up 20/20 boots, so §1.4's "required before ever enabling the apps SMMU" and §7-4's "we still need the crutches" are overtaken, not confirmed — the SID 0x800 handoff faults are the known-benign cosmetics. The "provenance gap" closed: the Fedora branch iceland-7.3-rc7-next (q90z) was fetched on 2026-11-01 (media-misc-plan.md) and the queue is cloned under /srv/ubuntu-iceland/ref/ (sensors-plan.md corrections). The pin moved to b7d639cfb282 on 2026-11-03; every "our tree" citation is against 7c98a10e6bb7.

**Question**: touch works on the Fedora (mzakamin) OnePlus Pad 4 port and on
the phonewave port; on ours the IC never drives INT (gpio158 parked low
through sustained touch, 2.4 kHz level-low storm with zero touch data in 43k
reads — porting-log :1000-1005). Firmware, DT node, pins, bias, reset, DSI
init tables, and the driver fix pair are already eliminated (porting-log
:1006-1011). What else differs, anywhere in the two stacks?

---

## 0. Verdict up front — the ranked remaining deltas

Full analysis in §§1-6; every item recapped with actions in §7. The short
version:

1. **144 Hz front porch (already ported as our 0009, flight pending).** The
   only *IC-visible byte/timing* difference left on the main path. Their fix
   (0103) matched stock's per-link porch table; fbcon runs the 144 Hz mode.
   A TDDI's touch scan is scheduled inside the video blanking the firmware
   expects; display tolerates hfp 68, the scan scheduler may not. [V]
2. **Bonded-DSI command-sync orientation is opposite.** Our tree carries the
   perpetua cherry-pick `5892773b169d` "drm/msm/dsi: change sync mode to
   sync on DSI0 rather than DSI1"; our panel driver sends all DCS on
   `dsi[0]`. Fedora **deliberately dropped that commit** (their
   docs/PORT-LOG.md item 18: "DROP … test item, fallback = restore this
   commit") and their panel driver sends all DCS on `dsi[1]` with upstream
   dsi_manager semantics ("Sync on DSI1 for dual dsi",
   panel-novatek-nt36536.c:74-75). Every broadcast command to the paired
   TDDI ICs — the whole init sequence — is triggered from the opposite DSI
   controller on the two stacks. [V code, I impact]
3. **Our panel never sends the DCS compression-mode command.** Their
   prepare does `mipi_dsi_compression_mode_multi(dsi_ctx, true)` + 28 ms
   settle after the init sequence (theirs novatek_prepare :127-132); ours
   sends PPS inside init and nothing else. Stock (qcom downstream
   dsi_panel) sends PPS *and* compression mode. Display decodes DSC anyway
   (vendor init table), but it is a real missing byte in the panel
   dialogue. [V code, I impact]
4. **Display-infrastructure parity cluster we lack** (MDSS INT2 GDSC in DT +
   multi-PD attach, kaanapali-mdss SMMU client, MDP RCG no-init-park, splash
   keep/reset-wait): masked during flights by our diag bootargs
   (`pd_ignore_unused` + initcall_blacklist), mandatory for flashed-boot
   parity, lower probability for the touch symptom because our scanout is
   proven live (Weston on DSI-1, porting-log :803-837). [V]
5. **DPU dual-DSI/DSC robustness cluster** (quad-pipe/3D-merge, CTL fixes,
   inefficiency factor, vid-CTL hw reset) and the **dynamic-refresh trio**
   (0303-0305): timing-stability and runtime-robustness deltas, unlikely to
   gate first engine start. [V present/absent; I impact]

Eliminated **by this audit** (new, with proof): the touch driver's
`GPIOD_OUT_LOW` vs `GPIOD_IN` difference (§1.1), spi-geni/GPI driver deltas
(§1.3), pinctrl/TLMM including `intr_target_width` (§2.2), geni-se,
interconnect, drm_panel core, DT spi19/touch/panel/DSI-host nodes, panel
modes/DSC/flags/reset (§4).

---

## Method and provenance

- **Their stack** (read-only on disk):
  `<scratch>/mzakamin-review/iceland-linux/`
  — kernel.pin: base v7.3-rc7 (`24a19b953e2a`) + patches/0001-infiniti (132)
  + patches/0002-iceland (294) = queue state **q89g**
  (7.3.0-rc7-iceland-00426). Sibling repos: `mzakamin-review/iceland-mainline`
  (userspace packaging), `iceland-firmware`; third port at
  `…/scratchpad/research/repos/phonewave`.
- **Our stack**: denialwm/linux-perpetua at `7c98a10e6bb7`
  (branch perpetua/v7.3; v7.3 final `c03c1a14507d` is an ancestor; 385
  perpetua commits above v7.3, 289 upstream commits rc7→v7.3) + our patches
  0001-0009 (kernel/patches/). Build config read from
  `/srv/ubuntu-iceland/build/linux-iceland/.config` (read-only).
- **Reconstruction**: both *final file states* were composed in a scratch git
  repo: their side = rc7 contents of the touch-adjacent file set + all 426
  patches applied in series order with `git apply --include=` filters
  (**0 failures**, so the reconstruction is exact for those files); our side
  = pin contents + our 0001/0003/0005/0007/0008/0009 (0002/0004/0006 touch
  files outside the set). Every "identical"/"differs" claim below is a diff
  of those two composed states, i.e. content-level, not subject-matching.
- **Provenance gap [V]**: the Fedora tablet *today* runs q90-era kernels
  (q90g…q90p per `iceland-mainline/packaging/iceland-device/files/iceland-cmdline`,
  items 5-9: the 20-22 Oct "glitch hunt" added `msm.dpu_dsc_once`,
  `msm.dpu_vfp_inplace/window`, `msm.dsi_slave_pll_restore=0`,
  `msm.dsi_phy_muxes_first`, `msm.dpu_vid_slave_late_cleanup`,
  `msm.dpu_scanout_frame_vtotal`, `panel_novatek_nt36536.stock_power_timing`,
  `.bl_after_video`, idle-refresh 30 Hz defaults). **That source is not on
  disk here** (queue snapshot ends at q89g/0306 — since 2026-11-01 the q90z branch is fetched, media-misc-plan.md, and the queue is cloned under /srv/ubuntu-iceland/ref/, sensors-plan.md corrections). Their *touch* milestone
  predates all of it — 0174/0180 are 3 Oct, q89b-era — so q89g is the valid
  parity target for "touch engine starts"; the q90 set documents that their
  dual-DSI *display* path kept having glitches long after touch worked.

---

## 1. Their patch queue vs our tree

Subject-matching their 426 patches against our 674 rc7..pin commits gives
only 60 exact matches — misleading, because the perpetua lineage absorbed the
same map220v work squashed/reworded. The content-level composition (above) is
authoritative for the touch-adjacent set. Full categorized disposition table:
§1.5. Touch-adjacent analysis:

### 1.1 Touch driver (drivers/input/touchscreen/nt36536/)

Patches: 0009 (add driver), 0036 (pen tablet caps), 0174 (deferral not an
error), 0180 (enabled/disabling hooks).

- `nt36xxx_fw_update.c` and `nt36xxx_mem_map.h` are **byte-identical**
  between their final and ours [V] — the whole download/REK/verify path is
  shared code (consistent with the healthy SPI dialogue).
- 0180 ≡ our 0008 (same hunks) [V]. 0174's substance (quiet deferral) is in
  our 0007's `dev_err_probe` [V]. 0036 is reporting-only (BTN_STYLUS/2,
  axis resolution from `touchscreen-x-mm`) — cosmetic for the engine [V].
- **Probe-order deviation (ours, deliberate)**: our 0007 moves
  `nvt_eng_reset()` *after* the `panel_on` gate; theirs still resets before
  the gate (their probe defers up to 3×/boot and the panel prepare repairs
  it — touch-plan.md :205, :297-309). On a lit panel (our flights) both
  orders execute the same ops. Keep ours. [V]
- **`GPIOD_OUT_LOW` vs `GPIOD_IN` — eliminated by analysis.** Theirs
  requests the INT gpio `devm_gpiod_get(dev, "irq", GPIOD_OUT_LOW)` (their
  0009, unchanged through q89g); ours was changed to `GPIOD_IN` +
  optional reset-gpio + `touchscreen_parse_properties` by perpetua commit
  `cf1638aad05e` ("Input: nt36536 - Take the reset line and the axes from
  the device tree", 2026-10-27 — for the Lenovo Idea Tab Pro's NT36532).
  Proof of equivalence on this DT: the gpio specifier is
  `<&tlmm 158 0x2002>` on **both** sides; `0x2002 & 0x7f = 0x2 =
  GPIO_SINGLE_ENDED` with `GPIO_LINE_OPEN_SOURCE(=0)` → gpiolib flags the
  desc **open-source**; `gpiod_direction_output(desc, 0)` on an open-source
  line takes the emulation path "not actively driving the line low" →
  `gpiod_direction_input()` (gpiolib.c `gpiod_direction_output_nonotify`,
  pin tree :3200-3207). TLMM has no open-source hardware config, so the pin
  is **never host-driven on either stack**; at `request_threaded_irq`,
  pinctrl-msm's `msm_gpio_irq_reqres` calls `msm_gpio_direction_input()`
  before `gpiochip_lock_as_irq()` on both. Net: electrically and
  functionally identical. The "parked low" line is the IC sinking it
  (pull-up test, porting-log :1000-1001), on both ports' host config. [V]
- Remaining driver deltas are reporting/error-path only (coordinate
  transform in-driver vs `touchscreen_report_pos`; `gpio_free` on error;
  input parent). None can gate the engine. [V]

### 1.2 Panel driver

Different files, same content where it matters. Theirs: Pad 4 added as
`csot,xn251` desc to **upstream** `panel-novatek-nt36536.c` (Pengyu Luo;
their PORT-LOG items 24/24b). Ours: `panel-oneplus-iceland-nt36536.c`
(map220v file; our tree *also* has the upstream driver but it only matches
`csot,pp8807hb1-1`, and `DRM_PANEL_NOVATEK_NT36536` is **not set** in our
.config → no double-bind) [V].

Verified identical between the two finals [V]:
- all five modes (144/120/90/60/30), including 144 Hz hfp=64 **after our
  0009** — their 0103 commit text confirms the 68 was "the sum of the three
  per-link numbers", stock is 32/16/20 per link;
- DSC config (1.1, 848×20 slices ×2, 8 bpc, 8 bpp, block_pred),
  `mode_flags` (VIDEO | CLOCK_NON_CONTINUOUS | LPM | DSC_ALL_SLICES_IN_PKT),
  4 lanes, `prepare_prev_first`, dual-DSI secondary-device registration,
  reset sequence 0(10 ms)→1(5 ms)→0(10 ms), PPS sent during init,
  exit_sleep→120 ms→display_on→10 ms tail.

Differences [V code; impact inferred]:
- **DCS send path**: theirs `to_primary_dsi()` = `dsi[1]` ("Sync on DSI1
  for dual dsi"); ours sends on `dsi[0]` (pairs with §2.1's cherry-pick).
- **`mipi_dsi_compression_mode_multi(true)` + 28 ms**: theirs only
  (novatek_prepare :127-132). Ours never sends DCS 0x07.
- Their disable path (`novatek_off`) has no 10/65 ms sleeps; ours does —
  off-path timing only.
- Supply names vsp/vsn vs avdd/avee — same regulators in both DTs
  (`lcd_vddpos_5p5`/`lcd_vddneg_5p5`), naming only.
- Their 0108 (stock reset sequence) and 0214 (Kconfig deps) are absorbed /
  not applicable on our side. [V]

### 1.3 SPI / geni / GPI

Composed-final diffs are **exactly two patches**, both immaterial to a
running system [V]:
- 0239 `spi: qcom-geni: Add shutdown callback` — reboot-path quiesce only.
- 0240 `dmaengine: qcom: gpi: Fix resource leaks … channel init error path`
  — error paths only (plus 0241 bam_dma, unused by spi19).
`qcom-geni-se.c`, `geni-se.h`: **identical**. spi19 runs GPI DMA on both
(same `dmas` in both dtsi, `QCOM_GPI_DMA=y` both configs). Runtime-PM /
autosuspend code identical. Nothing here can silence a TDDI engine; our SPI
dialogue is observed healthy anyway.

### 1.4 Clk / dispcc, PM, iommu

- `dispcc-kaanapali.c`: one functional delta — their 0075 switches the MDP
  RCG to `clk_rcg2_shared_no_init_park_ops` ("Don't park the MDP RCG at
  init"); ours parks it at clk registration [V]. A boot-time scanout
  stall/glitch vector, masked in our flights by `clk_ignore_unused` diag
  args; adopt for flashed parity.
- `gcc-kaanapali.c`: theirs adds CX-domain tie + FORCE_MEM_CORE_ON for UFS
  (0228/0230) and GDSC retention tweaks (0074, 0274); `gdsc.c` fixes
  0256/0257 (clock-controller active while a GDSC switches). Not on the
  touch path [V presence; I impact].
- `pmdomain/core.c` + cpuidle: their 0195-0199 (genpd wake-CPU support,
  powered-off init) + 0277/0278 (`allow_cluster_off`/`allow_system_off`
  params) + 0237/0238 (don't return disabled idle state) support their
  cluster-PD DT split (their kaanapali.dtsi uses `cluster0_pd/cluster1_pd/
  system_pd`; ours a single `cluster_pd`). Idle-power behavior, not
  engine-start. Our storm experiment proves gpio158 IRQs deliver fine. [V]
- `arm-smmu-qcom.c`: theirs has `{ .compatible = "qcom,kaanapali-mdss" }`
  in the client list (infiniti 0093); **ours does not** [V] — already known
  to us as the reason the apps-SMMU probe kills splash scanout (porting-log
  :470-471; diag boots leave the SMMU alone). Required before ever enabling
  the apps SMMU on a flashed boot. [Overtaken: release boots have run the apps SMMU live since 2026-11-01 (porting-log "Parade fully mapped", "T6 flashed") — the splash handoff leaves ten SID 0x800 faults per boot, known-benign, and the panel comes up 20/20; the client entry stays a parity item.]

### 1.5 Full disposition table (counts; complete list archived)

Content-corrected where it matters (§1.1-1.4, §4); subject-match detail for
all 426 patches is reproducible via the method in this doc's header.

| Category | Their patches | In our tree (content) | Notes |
|---|---|---|---|
| Touch driver | 4 | 2 of 4 equivalent (0009 base, 0180≡0008; 0174≡0007-part; 0036 missing, cosmetic) | §1.1 |
| Panel/backlight | 11 | modes/DSC/reset/porch parity after our 0009; missing: compression-mode send, ktz8869 extras (0024/0102/0168/0293/0294 — bootloader per-IC values, vddio-optional, thermal limit, crash fix) | §1.2 |
| DSI/DPU/MDSS | 28 | we have 2 (0006 compressed-width ≡ `d5f14e652269`, 0206 slave-disable ≡ `3a84264cbfac`) + 0114-equivalent (`7f76b18588dc`); **missing 25** incl. 0100/0101/0102, 0058, 0207/0209-0213 (quad-pipe), 0151, 0303/0304/0305, infiniti 0097-0103 (DSC 1.2 tables, 7nm PLL vco guard, splash keep) | §5 of verdict; dsi-phy iface clk: both trees have an equivalent, implementations differ (theirs adds system-sleep force suspend/resume) |
| GPU (adreno) | 7 | missing (A8x vote fixes) | not touch |
| DP | 6 | ours has DT node, driver fixes missing | not touch |
| SPI/geni/GPI | 5 | missing, all shutdown/error-path | §1.3, eliminated |
| pinctrl/gpio | 0 | — | files identical |
| clk/GDSC | 11 | missing | §1.4 |
| interconnect | 0 | — | file identical |
| PM/genpd/cpuidle | 9 | missing | §1.4 |
| DT (kaanapali*, iceland) | 93 | touch/panel/SPI/DSI nodes at parity (§4); **missing: &mdss INT2 (0022/0027)**, reserved-ranges/drive-strengths (0105/0106 partial), cluster-PD split, cameras/pen/pogo/thermal/battery board content | §4 |
| other (audio, battery, wifi, bt, media, usb, thermal, misc) | ~252 | mostly missing | not touch-adjacent; several already queued elsewhere (ath12k set — porting-log C3 tail) |

---

## 2. The rc7..pin delta in touch-adjacent subsystems (our tree's own side)

`git log 24a19b953e2a..7c98a10e6bb7 -- <paths>` in /srv/ubuntu-iceland/linux-perpetua:

### 2.1 Display (the only populated path)

8 commits total on dsi/dpu1/msm_mdss. Net iceland-relevant *ours-only*
behavior: **one commit** —

- `5892773b169d` "drm/msm/dsi: change sync mode to sync on DSI0 rather than
  DSI1" (map220v cherry-pick of a 2023 Baryshkov patch). Inverts
  `msm_dsi_manager_cmd_xfer{,_trigger}`: broadcast DCS is prepared on DSI1
  and triggered when the caller sends on **DSI0** (upstream/theirs: prepared
  on DSI0, triggered on **DSI1**). Pairs with our panel sending on `dsi[0]`
  — self-consistent, but opposite hardware ordering of the command DMA
  commit/trigger on the two controllers vs the Fedora stack. Their PORT-LOG
  item 18 dropped exactly this commit ("as on Lenovo Y700; test item,
  fallback = restore this commit") and never needed the fallback. [V]

The other 7: DSC-1.2-encoder program + its revert (net 0), cmd-mode DSC link
sizing (`2661514d130f`, video panel → no-op), 10 bpc range_max_qp
(`05ba9e9d212c`, 8 bpc panel → no-op), compressed-width fix
(`d5f14e652269` ≡ their 0006), slave-encoder-disable-first
(`3a84264cbfac` ≡ their 0206), dsi-phy iface clk (`7f76b18588dc` ≈ their
0114). [V]

### 2.2 Everything else: empty, and the intr_target question

- `spi-geni-qcom.c`, `drivers/dma/qcom/`, `drm_panel.c`, `qcom-geni-se.c`,
  `interconnect/qcom/kaanapali.c`, `gcc/dispcc-kaanapali.c`,
  `pinctrl-msm.c`: **zero commits** rc7..pin → at rc7 state, byte-identical
  to their base. [V]
- `pinctrl/qcom`: rc7..pin contains the upstream "Fix intr_target_width"
  cluster (qcs8300 `dcb5df182b37`, maili `912df33f296e`, hawi
  `9d4c3e0c6a53`, nord `68ab4a6a84b9` — each adds `.intr_target_width = 4`
  where the TLMM field is 4 bits). **pinctrl-kaanapali.c sets
  `intr_target_bit = 8`, `intr_target_kpss_val = 3` and no
  `intr_target_width`** → default 3-bit mask. If kaanapali's field is 4 bits
  wide (likely, as its contemporaries), an RMW can't clear a stale 4th bit.
  **Not our blocker**: (a) the file is identical in the Fedora tree and
  their touch IRQ works; (b) our level-low storm proves gpio158 interrupts
  reach the APSS (porting-log :1002-1005). Flag upstream later. [V data,
  I on field width]

---

## 3. Kernel config comparison

Theirs = arm64 defconfig + their 0003 `sm8850.config` + configs/
(distro-neutral.config, required.config). Ours =
/srv/ubuntu-iceland/build/linux-iceland/.config. Touch-relevant:

| Option | Theirs | Ours | Verdict |
|---|---|---|---|
| SPI_QCOM_GENI | m (defconfig) | m | parity |
| QCOM_GPI_DMA | y | y | parity (spi19 uses GPI DMA on both) |
| TOUCHSCREEN_NT36536_SPI | m | m | parity |
| Panel driver | DRM_PANEL_NOVATEK_NT36536=y | DRM_PANEL_ONEPLUS_ICELAND_NT36536=y (novatek one not set) | different driver file, §1.2; no double-bind on either |
| BACKLIGHT_KTZ8869_ICELAND | y | y | parity |
| DRM_MSM / DSI / DPU / 7NM PHY | y | y (all) | parity |
| PREEMPT / HZ | PREEMPT=y, HZ=1000 | PREEMPT=y, HZ=1000 | parity |
| PM_AUTOSLEEP / WAKELOCKS | y/y | y/y | parity |
| I2C_QCOM_GENI | y | y | parity |
| PINCTRL_KAANAPALI, CLK_KAANAPALI_*, INTERCONNECT_QCOM_KAANAPALI | y | y | parity |
| GPIO_SHARED_PROXY | **y** (their comment: as =m the shared-HWEN backlight defers with no reason printed) | **m** | works for us (rootfs loads it; display up), but =y is the proven-robust choice for initramfs display bring-up |
| FW_DEVLINK_SYNC_STATE_TIMEOUT | **y** (releases held boot votes after the deferred-probe timeout) | **not set** (providers hold boot votes while any consumer is unbound) | ours is the *safer* direction for touch; difference documented, no action |

No geni-SE runtime-PM/autosuspend config divergence exists (driver-internal,
identical code). Nothing in the config space can explain the dead engine. [V]

---

## 4. The composed final DT, node by node

Method: their final `kaanapali-oneplus-iceland.dts`/`kaanapali.dtsi` = 0002
base + every later patch, applied in order (clean). Ours = pin + 0001/0003/
0005 (board file; 0009 touches the panel driver, not DT).

**Identical (byte-level, both files)** [V]:
- `&spi19` controller node (clocks, interconnects, **GPI dmas**, pinctrl) —
  dtsi — and `qupv3_4` wrapper, `gpi_dma4`.
- `&spi19` board node: `spi-max-frequency = <12000000>`,
  `irq-gpios = <&tlmm 158 0x2002>`, **`novatek,pen-support` present on
  both**, `panel = <&display_panel>`, same `firmware-name`. Only reporting
  props differ: ours `touchscreen-size-x/y = 24000/33920` +
  `inverted-x` + `swapped-x-y` (which our driver *requires*,
  cf1638aad05e); theirs `touchscreen-x-mm/y-mm = 274/193` (which their
  0036 driver reads). Equivalent intent, matched to each side's driver.
- `&mdss_dsi0` / `&mdss_dsi1` board nodes: **`qcom,dual-dsi-mode` +
  `qcom,sync-dual-dsi` on both hosts, `qcom,master-dsi` on dsi0**, same
  vdda/vdds supplies, same DSI1-slave clock reparenting to
  `mdss_dsi0_phy` PLLs, `data-lanes <0 1 2 3>` both ports.
- Panel node: same pinctrl sets (sde_dsi, **sde_te (mdp_vsync fn)**,
  fte_mout_1p2/min_1p8/sout_1p2/sin_1p8 — the paired master/slave TE loop
  between the two TDDI ICs — sde_disp0_rst 1p2/1p8), same
  `reset-gpios = <&tlmm 171 GPIO_ACTIVE_LOW>`, same backlight phandle, same
  ports graph. All ten sde_*/fte_* pinctrl states byte-identical.
- dtsi display stack: `mdss_mdp`, dsi hosts, **both DSI PHYs**, `dispcc`
  node — identical.
- `aliases` (serial0/1; theirs adds serial2 for the pogo UART).

**Different** [V]:
- Panel `compatible`: ours `"oneplus,iceland-nt36536","novatek,nt36536"`,
  theirs `"csot,xn251","novatek,nt36536"` — binds each side's driver; the
  fallback matches nothing extra on either side.
- Supply names (vsp/vsn vs avdd/avee) — same regulators.
- **`&mdss` power-domains**: theirs overrides to
  `<&dispcc DISP_CC_MDSS_CORE_GDSC>, <&dispcc DISP_CC_MDSS_CORE_INT2_GDSC>`
  with the comment "With INT2 off the DPU stops scanning out even though
  the KMS reports the panel on" (their 0022/0027), plus driver patch 0026
  attaching all PDs (`devm_pm_domain_attach_list`, PD_FLAG_DEV_LINK_ON —
  msm_mdss.c). Ours: CORE_GDSC only (dtsi default), single-PD attach. The
  INT2 GDSC exists in our dispcc driver but nothing references it →
  swept off by genpd/sync_state on a non-diag boot. Our scripts already
  know ("dispcc's sync_state drops the INT2 GDSC whatever pd_ignore_unused
  says" — scripts/make-diag-bootimg.sh :127); diag flights blacklist
  `of_platform_sync_state_init` so flights were *not* running with INT2
  down, and our Weston sessions prove scanout. Mandatory for flashed
  parity; weak as the touch explanation.
- `gpio-reserved-ranges`: ours `<36 4>`; theirs `<36 8>, <74 1>, <119 2>,
  <144 4>` (their 0105). None cover gpio158 or the spi19/panel pins — not
  touch; adopt to avoid faulting secure pins via gpio dumps.
- Theirs-only board content (not touch): cameras, pen charger, pogo
  keyboard + UART17, battery/thermal/BCL description, DisplayPort enable,
  RTC offset cells, ADSP/CDSP extras, cluster-PD split in dtsi (+ SCMI,
  iris, rpmh-stats, cpucp-mbox, LLCC bwmon).
- TLMM dtsi deltas: camera mclk/cci naming+bias only. Nothing near 158.

**Conclusion §4**: the DT touch+SPI+panel+DSI topology is at parity to the
byte, including the dual-DSI sync flags and TE/FTE wiring, except the &mdss
INT2 power-domain line. The earlier "DT pins/node eliminated" verdict
(porting-log :1006-1011) is *confirmed* and extended to the DSI hosts and
the full composed files. [V]

---

## 5. Boot and userspace sequencing

**Theirs** (iceland-linux/packaging + iceland-mainline/packaging):
- `90-iceland-dracut.conf`: **initramfs carries the display *and touch*
  stack**: `add_drivers+=" msm panel-novatek-nt36536 ktz8869_iceland
  nt36536_ts "` plus `novatek_nt36536_fw.bin` in `install_items` —
  "troikoss lesson: firmware the early drivers need must be inside the
  initramfs". Touch coldplugs from initramfs udev every boot; the panel
  gate (+0174's quiet deferral, up to 3 retries) orders it; **no blacklist
  anywhere in their packaging** (touch-plan :222 confirmed).
- `iceland-cmdline` (kernel-install plugin, rewrites boot entries): through
  v0.18 every entry carried **`clk_ignore_unused pd_ignore_unused
  regulator_ignore_unused`** — i.e. the Fedora port spent its whole
  bring-up era with the unused-sweep off, then removed the crutches only
  after the 2-3 Oct rehearsals passed without them (by which point INT2,
  multi-PD attach, splash keep, etc. were patched in). Today's entries are
  mostly module-param defaults of q90 kernels (see Provenance gap).
- No touch-related modprobe.d or udev rules beyond dracut; GPU firmware
  path selection (`GPU_FW` in `/etc/iceland/boot.conf`) is the
  userspace-sequencing precedent, not touch.
- DTB handling: kernel-install drops the DTB on the ESP for U-Boot
  (90-iceland-dtb.install); U-Boot applies ABL memory fixups.

**Ours**:
- Release boots: stock vendor_boot cmdline, no ignore_unused flags
  (scripts/build-boot-bundle.sh :10); `nt36536_ts` blacklisted on the
  rootfs (packaging/ubuntu-iceland-device/usr/lib/modprobe.d/iceland.conf)
  until the C2 gate (passed 2026-11-01; 0.2.16 left tombstones only).
- Diag/flight RAM boots (scripts/make-diag-bootimg.sh :104-127):
  `clk_ignore_unused pd_ignore_unused` +
  `initcall_blacklist=clk_disable_unused,genpd_power_off_unused,
  regulator_init_complete,of_platform_sync_state_init` + `fw_devlink=off`
  + a long `modprobe.blacklist` (incl. `spi_geni_qcom` and implicitly
  gated touch) — flights then modprobe by name. **So all flight-time
  observations were made with the PM environment maximally permissive**;
  the INT2/unused-sweep class cannot have been the flight-time cause.
- Takeaway delta: they bring touch up *early* (initramfs, before first
  modeset → driver follows the panel through its first enable); we bring
  it up *late* (after fbcon/Weston enabled the panel → driver relies on
  `drm_panel_add_follower`'s synthesized `panel_enabled` callback —
  verified present in our tree, drm_panel.c :611-616, and verified firing:
  the download ran at enabled-time in T1' (porting-log :996-999)). Ordering
  is therefore sound on both; no userspace timing fix is indicated beyond
  what touch-plan §T5/T6 already plans. [V]

---

## 6. The phonewave port (third datapoint)

`research/repos/phonewave/devices/iceland/` — an Arch-chroot port on the
**denialwm lineage** (service `pad4-denial.service`; kernels
`7.3.0-rc7-devices9-iceland` / `7.3.0-rc7-devices14-iceland` pinned in
`rootfs/usr/local/libexec/pad4-kernel-release`). Those branches are not in
our clone (only perpetua/v7.3), so patch-level inspection is not possible
here [V absence]; being rc7-era denialwm, they almost certainly carry the
map220v DSI0-sync commit and the *original* (pre-`cf1638aad05e`,
OUT_LOW-era) touch driver [I].

`pad4-hardware-init` (systemd oneshot, After=systemd-udev-trigger,
Before=pad4-denial.service, timeout 45 s):
1. asserts the exact kernel release + sha256 of early modules;
2. sha256-verifies firmware incl. `novatek/novatek_nt36536_fw.bin`
   `5e9d9651…` — **the same bytes as ours and Fedora's**
   (docs/firmware-manifest.md :70-77, "triple corroboration");
3. `pad4-display-init`: `modprobe gpio-shared-proxy`, `modprobe qrtr`,
   pokes `pmic-glink` to probe, then waits (≤5 s) for `/dev/dri/card0` +
   `/dev/fb0` and prints the DSI-1 status — **display fully up first**;
4. `modprobe spi-geni-qcom` (held out of coldplug), then
   `modprobe nt36536_ts`;
5. **asserts `NVTCapacitiveTouchScreen` exists in
   /proc/bus/input/devices** — the unit fails otherwise, so working touch
   registration is enforced, every boot.

Readings: (a) a perpetua-family kernel *can* run this touch stack — the
DSI0-sync orientation and the vendor probe order did not stop the devicesN
kernels [I, kernel content not inspectable]; (b) their sequencing (display →
SPI → touch, all post-udev) is exactly our flight ladder's shape, and their
`TimeoutStartSec=45` + input-device assert is a good pattern for our T6
device package. Caveat: `device.toml` lists `refresh_hz = [60, 120]` and a
1904×3040 resolution — if that reflects their panel mode reality rather
than sloppy metadata, the devicesN kernels may never have driven the panel
at 144 Hz, which would make phonewave *consistent with* the
144 Hz-porch hypothesis rather than against it [I — worth one question to
the phonewave author, or a mode-list read if a devicesN tree ever lands
here].

---

## 7. The most likely remaining deltas, ranked — with next actions

Flight rules honored: RAM boots, one variable per flight, no rmmod of
nt36536_ts, blacklist stays until the C2 gate (touch-plan :19-35). The
rootfs still carries the LEVEL-LOW TEST module — restore the edge build
before any of this (porting-log :1015-1016). [Overtaken 2026-11-01: the C2 gate passed, the blacklist is retired and the flashed #33+ kernels carry the edge build.]

1. **144 Hz front porch 68→64 — our 0009, bundle already building.** [Flown 2026-11-01: eliminated as the cause, kept as stock-correct.]
   [V difference existed; fix staged] The only stock-timing mismatch the
   TDDI saw during every failed flight, on the mode fbcon runs. Their 0103
   is in q89b, i.e. present for their entire touch-working history.
   *Action*: fly the queued T-flight unchanged (builtin panel → kernel+
   bundle rebuild, RAM boot; already in motion). If touch events appear,
   stop; the rest of this list becomes parity backlog.
2. **Bonded-DSI command-sync orientation (ours DSI0, theirs DSI1).** [This was the wall — flown exactly as described and promoted as permanent 0010 on 2026-11-01.]
   [V opposite; I impact] Our ours-only display commit (`5892773b169d`);
   Fedora dropped it deliberately and runs the upstream orientation their
   touch has always used; the broadcast path carries every DCS the paired
   TDDI ICs get. Display tolerates both; the master/slave touch pairing
   (FTE loop) may not. *Action if 1 fails*: one flight = revert
   `5892773b169d` **and** flip our panel's command context from `dsi[0]`
   to `dsi[1]` (both changes are the *same* variable: "Fedora sync
   orientation"; shipping one without the other would no-op the init
   writes). Builtin drm/msm + panel → kernel image rebuild, RAM boot.
3. **Send DCS compression-mode after init, as stock and Fedora do.**
   [V missing; I impact] One `mipi_dsi_compression_mode_multi(&dsi_ctx,
   true)` + 28 ms in `nt36536_prepare` after the init sequence (mirror
   novatek_prepare :127-132). Builtin panel → kernel image rebuild. Cheap
   to combine with the 0009 *rebuild* but that would violate
   one-variable — fly after 2, or before 2 if the DSI census (porting-log
   C3 queue) shows stock sending 0x07.
4. **Display-infrastructure parity cluster (adopt as a batch for the next
   kernel refresh, not as a touch flight)**: &mdss INT2 GDSC DT line
   (their 0022/0027) + `msm_mdss` multi-PD attach (0026) +
   `qcom,kaanapali-mdss` SMMU client (infiniti 0093) + MDP RCG
   no-init-park (infiniti 0075) + splash keep/reset-wait (infiniti 0103,
   iceland 0060) + ktz8869 fixes (0024/0102/0294). [V all absent] These are
   why Fedora could drop `clk/pd/regulator_ignore_unused`; we still need
   the crutches. DT+builtin mix → kernel rebuild; flashed-boot gate, not
   RAM-flight material. Low probability for the INT symptom (scanout was
   live in flights) but required for release parity.
5. **DPU dual-DSI/DSC robustness set**: 0100/0101/0102 (stale CTL
   bindings/vid hw-reset/vblank refcount), 0058 (CTL_START in cleanup),
   0207/0209/0210/0211/0212/0213 (bandwidth from state, legacy-CTL flush,
   **quad-pipe + 3D merge for DSC+dual-DSI**, `CRTC_QUAD_MIXERS 4`), 0035
   (`clk_inefficiency_factor` 105→100), 0151 (GAMMA LUT). [V absent;
   I impact] Candidate mechanism: marginal 2-LM timing at 144 Hz jitters
   the stream enough that the TDDI scan scheduler won't lock, without
   visible artifacts. Only if 1-3 all fail: adopt as one "DPU topology"
   flight (kernel rebuild), expect visible underrun improvement as the
   tell. Their q90 glitch-hunt params show this area stayed hot for them
   well past touch bring-up.
6. **Dynamic refresh trio 0303/0304/0305** (vtotal-on-the-fly, vsync
   period, idle refresh): runtime robustness (REK-timeout class our 0008
   already mitigates); adopt with the next queue refresh, default-off
   (`msm.dpu_idle_refresh_ms=0`) exactly as theirs. Not an engine-start
   candidate. [V]
7. **Driver/DT cosmetics for the C2 exit** [their 0036 landed as 0037 + 0038/0039 on 2026-11-02; the assert unit was not needed — touch auto-loads on every boot]: their 0036 (BTN_STYLUS,
   `touchscreen-x-mm` resolution — module-only) once events flow;
   phonewave-style systemd assert unit for T6; keep our 0007 ordering.
8. **Config knobs**: set `GPIO_SHARED_PROXY=y` at the next kernel refresh
   (initramfs-display robustness; theirs documents the =m failure mode);
   leave `FW_DEVLINK_SYNC_STATE_TIMEOUT` as-is until the parity cluster
   (4) lands. [V]
9. **Upstream flag, no local action**: kaanapali pinctrl lacks
   `intr_target_width = 4` in *both* trees while the fix cluster patched
   four sibling SoCs; our IRQ delivery is proven, so purely a correctness
   note for the next upstream sync. [V]
10. **Watch the provenance gap** [moot: 2 was the wall, and the q90 queue has since been fetched — see §Method]: if 1-5 all fail, the remaining
    explanation space is the q90-era Fedora work we cannot read here
    (`stock_power_timing`, `bl_after_video`, the glitch-fix set). The
    recorded param names alone say where they went: panel power-on timing
    and backlight-after-video ordering. Fetch a q90 queue (new
    mzakamin-review drop) before inventing our own fixes there. [V gap]

### What this audit eliminates (so nobody re-burns a flight on it)

- irq-gpio request mode OUT_LOW vs IN (proof chain §1.1);
- SPI/geni/GPI driver or config differences (§1.3, §3);
- pinctrl/TLMM content incl. intr_target (§2.2) — and the storm already
  proved delivery;
- DT differences in spi19/touch/panel/DSI-host nodes incl.
  `novatek,pen-support`, dual-DSI flags, TE/FTE pin states (§4);
- panel modes/DSC/mode-flags/lanes/reset/PPS (§1.2);
- drm_panel core / follower semantics (identical; synthesized
  `panel_enabled` verified at :611-616 and observed working);
- genpd/cpuidle and FW_DEVLINK for the *flight-time* symptom (diag args
  held everything on, §5);
- firmware bytes (triple-corroborated hash, §6).
