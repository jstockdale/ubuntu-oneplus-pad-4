# WLAN bring-up plan: the pwrseq_qcom_wcn hard reset

Date: 2026-11-01 (research overnight, flights tomorrow).
Problem: `modprobe pwrseq_qcom_wcn` hard-resets the SoC at driver *bind* time,
confirmed twice in the module bisect; every radio depends on it
(pcie0 host init defers on the pwrctrl consumer, which defers on this
provider). Module currently blacklisted in `/usr/lib/modprobe.d/iceland.conf`.

All file:line references are against the worktree
`/srv/ubuntu-iceland/build/linux-src-iceland` at HEAD `7c98a10e6bb7`
(perpetua/v7.3) unless noted. Everything marked **[verified]** was read from
the named file tonight; **[inferred]** is reasoned, not observed.

---

## Safety rails (verbatim, non-negotiable)

- **RAM boots only** — every flight is `fastboot boot` of a diag image.
- **Nothing flashed.**
- **No vbmeta / dtbo / vendor_boot / set_active writes ever.**
- **Single variable per flight.**

Additions that follow from tonight's research:

- Never `cat /sys/kernel/debug/pinctrl/f100000.pinctrl/pins` (or the gpio
  debugfs equivalents) on the tablet: that reads **every** TLMM pin, and on
  firmware with TrustZone-owned pins a read of a protected register is itself
  a reset (classic Qualcomm XPU behaviour; see the 2021 LKML thread by Petr
  Vorel, gpio-reserved-ranges discussion,
  patchwork.kernel.org/comment/24102479). Use only the targeted `devmem`
  reads listed in Flight 0.
- A reset during a flight is *expected* and recoverable: the RAM-booted diag
  kernel vanishes, the flashed slot-B Ubuntu boots on its own, pwrseq stays
  blacklisted there. Nothing persistent is at risk. (One serial listener
  only, per the runbook.)

---

## 1. Findings summary

### 1.1 What loading the module actually does, in order **[verified]**

The DT node (`arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts:349-407`,
unchanged since map220v's original commit `11e47b85171c` "SM8850: Add device
tree for OnePlus Pad 4"):

```
wcn7860-pmu {                                  # dts:349
    compatible = "qcom,wcn7860-pmu";           # dts:350
    pinctrl-names = "default";                 # dts:352
    pinctrl-0 = <&wlan_en>, <&bt_default>;     # dts:353
    wlan-enable-gpios = <&tlmm 16 ...>;        # dts:355
    bt-enable-gpios = <&pmh0104_j_e1_gpios 5>; # dts:356
    vddio=l2g, vddio1p2=l3g, vddaon=s1j,
    vdddig=s2j, vddrfa1p2=s7f, vddrfa1p8=s8f   # dts:358-363
    clocks = <&rpmhcc RPMH_RF_CLK1>;           # dts:365
    regulators { ldo0..ldo9 }                  # dts:367+
};
```

Sequence at `modprobe pwrseq_qcom_wcn` (all providers are built-in —
`CONFIG_PINCTRL_KAANAPALI=y`, `CONFIG_PINCTRL_QCOM_SPMI_PMIC=y`,
`CONFIG_REGULATOR_QCOM_RPMH=y`, `CONFIG_QCOM_CLK_RPMH=y` in
`/srv/ubuntu-iceland/build/linux-iceland/.config` — so bind never defers and
proceeds straight into hardware):

0. Module registers the platform driver; driver core matches
   `qcom,wcn7860-pmu` (`drivers/power/sequencing/pwrseq-qcom-wcn.c:582-584`,
   pdata `pwrseq_wcn7860_of_data` at :413, vregs list at :404-411).
1. **Before the probe function runs**, `really_probe()` calls
   `pinctrl_bind_pins(dev)` — `drivers/base/dd.c:684`, inside
   `really_probe()` at dd.c:652. `pinctrl_bind_pins()`
   (`drivers/base/pinctrl.c:23`) does `devm_pinctrl_get()` and
   `pinctrl_select_state(default)` (pinctrl.c:55-58; there is no "init"
   state here). **This writes hardware:**
   - `wlan_en` state (dts:1341-1346): TLMM **GPIO16** CTL register — function
     gpio, drive-strength 8, bias-pull-down. MMIO write at
     0x0F110000 (TLMM base 0x0F100000, `kaanapali.dtsi:5017-5019`; stride
     0x1000/pin, ctl=+0x0, io=+0x4, `drivers/pinctrl/qcom/pinctrl-kaanapali.c:12,33-34`).
   - `bt_default` state (dts:1182-1192): PMIC **pmh0104 "J" (SPMI bus1,
     SID 9, gpio block 0x8800** — `pmh0104-kaanapali.dtsi:39-57`) **gpio5** —
     SPMI writes: function normal, input-disable, output-enable, output-low,
     bias-disable, power-source 1. Peripheral base 0x8C00 (0x8800+4*0x100).
   - Application order = property order: **wlan_en (TLMM) first, then
     bt_default (PMIC)**.
2. Probe body (`pwrseq-qcom-wcn.c:473`):
   a. kzalloc, `device_get_match_data` (:480-489) — no HW.
   b. `devm_regulator_bulk_get` of the six supplies (:491-502) — resolves the
      six RPMh regulators (L2G, L3G, S1J, S2J, S7F, S8F). Software-only:
      no RPMh votes, no SPMI traffic at get time **[verified code path;
      "no HW" is inferred from the regulator core]**.
   c. `has_vddio` is false for wcn7860 (:413-418 has no `.has_vddio`), skip (:504).
   d. `devm_gpiod_get_optional(dev, "bt-enable", GPIOD_OUT_LOW)` (:510) —
      **SPMI writes** to PMIC J gpio5: mode=digital output, value low.
   e. `devm_gpiod_get_optional(dev, "wlan-enable", GPIOD_OUT_LOW)` (:515-516)
      — **MMIO writes** to TLMM16: IO reg OUT=0 (0x0F110004), CTL OE=1.
      **This OUT_LOW is new in v7.3 final**: commit `dbd674ccf30f`
      ("power: sequencing: qcom-wcn: power off WLAN at probe",
      François Roux, 2026-10-04, Cc stable) changed it from `GPIOD_ASIS`
      (which wrote nothing). It landed via `pwrseq-fixes-for-v7.3`
      (merge `7b441fe5a6c6`), i.e. **after v7.3-rc7**.
   f. `devm_clk_get_optional(dev, NULL)` (:527) — rpmhcc RF_CLK1 handle;
      no vote at get time.
   g. `devm_pwrseq_device_register` (:540) — software only.
3. Everything else (regulator enables, clk vote, WLAN_EN/BT_EN high, 50 ms
   pwup delay) happens **later**, at pwrseq power-on driven by consumers
   (`pwrseq_qcom_wcn_targets`, :291-295; wlan unit deps :133-137): the
   pwrctrl device `wifi@0` (`pci17cb,110e`, dts:1156-1157;
   `drivers/pci/pwrctrl/pci-pwrctrl-pwrseq.c:50,91` gets target "wlan") and
   the uart18 `bluetooth` node (dts:1453-1471).

So the complete set of hardware writes at bind is exactly:
**TLMM16 config write (pinctrl) → PMIC-J gpio5 config writes (pinctrl) →
PMIC-J gpio5 output-low write (gpiod) → TLMM16 out=0/OE=1 write (gpiod)**.
The reset is caused by one of these four writes (or, far less likely, by a
software-side get). The flight matrix separates them.

### 1.2 What the sibling ports do about iceland WLAN

**mzakamin / Fedora port — WLAN works on a Pad 4.** Clone at
`/tmp/claude-1000/-home-jstockdale-projects-arch-oneplus-pad-4/29772f33-9e3d-45de-9bdd-4279cde4b0f0/scratchpad/mzakamin-review/iceland-linux/`:

- Base = **v7.3-rc7** (`kernel.pin`: UPSTREAM_TAG=v7.3-rc7) + the
  infiniti-mainline (OnePlus 15, same SoC) series + iceland series.
  **rc7 predates `dbd674ccf30f`**, so their pwrseq requests the WLAN GPIO
  **GPIOD_ASIS** — no TLMM16 OE/value write at bind. **[verified]**
- Their WCN7860 pwrseq pdata is a *different* patch:
  `patches/0001-infiniti/0080-power-sequencing-qcom-wcn-Add-support-for-WCN7860.patch`
  (Victor Fuentes, 2026-07-29), vregs = {vddio1p2, vddant, vddaon, vdddig,
  vddrfa1p8, vddrfa1p2, **vddcx**} — no "vddio". Ours (Teguh Sobirin,
  `b7d0e03a2150`) = {vddio, vddio1p2, vddaon, vdddig, vddrfa1p2, vddrfa1p8}.
- Same DT pins as ours (their 0002 patch is map220v's DT; pins never
  changed). **[verified]**
- Proof WLAN runs: `patches/0002-iceland/0040-...-the-PCIe0-W.patch`
  (2026-09-29) fixes the PCIe0 **WAKE# polarity** because "on the OnePlus
  Pad 4 every suspend with Wi-Fi enabled returned within a second" — that is
  s2idle debugging with live Wi-Fi. Their ath12k queue (Q89B 0217-0226 etc.)
  and the BT baud-rate note in `docs/PORT-LOG.md:110` corroborate.
- `patches/0002-iceland/0167-...-fix-the-WCN.patch` (2026-10-02) rewires
  supplies "as the vendor tree of this tablet does": vddaon→L2G, adds
  vddcx→S1J, drops vddio. Note their Wi-Fi already worked on 2026-09-29
  *before* this fix (with dummy-regulator warnings), so the supply map is a
  function/correctness issue, **not** the reset.
- Their config builds the driver in: `configs/distro-neutral.config:
  CONFIG_POWER_SEQUENCING_QCOM_WCN=y` (binds in early boot, not modprobe).

**DocLogix / perpetua (our kernel's upstream).** The tree itself carries
iceland-specific radio work: `3c983bfbad01` "Bluetooth: qca: bring up the
OnePlus Pad 4 WCN7860 Peri subsystem" (2026-10-18, "This is the bring-up the
Pad 4 runs today"), plus the WCN7860 ath12k/pwrseq/pwrctrl/BT support
(`28c1d15fa4fb`, `fe38e1854b72`, `b7d0e03a2150`, `52961164525a`,
`3290330664bc`). For BT to run that far the pwrseq must probe and power BT,
so **pwrseq evidently binds on DocLogix's Pad 4** — but we cannot see
*which kernel build* his tablet actually runs (tip includes `dbd674ccf30f`;
his runtime kernel may predate it). **[verified commits; runtime inferred]**
Kconfig default is `m` (`drivers/power/sequencing/Kconfig:16-18`,
"default m if ARCH_QCOM"); the iceland fragment doesn't override it, though
notably `devices/roadstr/kernel.config:8` forces `=y` for the other
kaanapali device.

**SuperTurtleDev / Ubuntu-EDK2 port.** Clone at
`.../scratchpad/repos/iceland-mainline-kernel/`: their 7.3 series
(`patches/platform-sm8850-7.3/series` items 0007-0013) carries the same
map220v WCN7860 patches and DT; config has
`CONFIG_POWER_SEQUENCING_QCOM_WCN=y`. Their README's build-validation
section (2026-10-27) ends "Hardware runtime behavior still requires testing
on the device" — **no evidence either way** about WLAN on v7.3+OUT_LOW.
**[verified]**

### 1.3 Downstream (stock OPLUS) truth — extracted tonight from OUR unit's images

Source: `/srv/ubuntu-iceland/factory/fcap/part-vendor_boot_a.img` and
`part-dtbo_a.img` (reads only; work done in the session scratchpad).
Our stock OTA is `OPD2514_16.0.10.501_GLO_11.A.38`
(`/srv/ubuntu-iceland/stock/current/PROVENANCE.json`) — **the same 11.A.38
baseline the Fedora port's firmware manifest names** (`iceland-firmware/
MANIFEST.tsv` header). Same device, same firmware generation.

Extraction result (procedure in appendix A; all 8 dtbo entries are iceland
variants "Canoe MTP,iceland[-O][ IN|EU]"; WLAN bits identical across them):

| Signal | Downstream (dtbo entry 00, `qcom,cnss-peach@b0000000` + `cnss_pins` + `wcn786x`) | Our mainline DT | Match |
|---|---|---|---|
| WLAN_EN | `wlan-en-gpio = <&tlmm 0x10>` = **TLMM 16**; active state: func gpio, **bias-pull-up, output-high, drive 16**; sleep state: pull-down, output-low, drive 2 | `&tlmm 16`, pinctrl func gpio, drive 8, pull-down | **pin ✓** (config differs: see §3 fix 4) |
| BT_EN | `qcom,bt-en-gpio = <&pmh0104@9/pinctrl@8800 5>`; `bt_en`: normal, input-disable, output-enable, bias-disable, power-source 1 | `&pmh0104_j_e1_gpios 5`, `bt_default` identical incl. power-source 1, plus output-low | **✓** |
| SW_CTRL | `qcom,sw-ctrl-gpio` = TLMM **18** (func `wcn_sw_ctrl`); BT `qcom,bt-sw-ctrl-gpio` = TLMM 18 | `wcn_sw_ctrl_default` defined (dts:1348) but **not referenced** | ✓ (unused) |
| WLAN SW_CTRL WL_CX | TLMM **19** func `wcn_sw` | `wcn_sw_default` says gpio18 (dts:1354) — wrong pin, unused | cosmetic |
| SOL host/dev | TLMM **204 / 205** | not described | n/a (cnss2-only) |
| BT reset / FMD clk | PMIC J gpio5 / gpio6 (`wcn786x` node) | gpio5 via pwrseq | ✓ |
| WLAN rails | aon=**L2G**, cx=**S1J**, dig=S2J, io12=L3G, rfa1(1.8)=S8F, rfa2(1.2)=S7F, ant-share=**L3K** (one board variant only), wcal-pbs supply | vddio=L2G, vddio1p2=L3G, vddaon=S1J, vdddig=S2J, vddrfa1p2=S7F, vddrfa1p8=S8F | **rail SET identical** (L2G,L3G,S1J,S2J,S7F,S8F); names shuffled; L3K absent |
| PCIe RC | `qcom,wlan-rc-num = 0` (RC0) | pcie0 | ✓ |
| PMU map | `qcom,pmu_vreg_map`: AON_0P9→S2J1, RFA_0P9→S2J1, RFA_1P9→S8F0, RFA_1P3→S7F0, WLMX→S2J1, WLCX→S1J1, BTCX/BTCMX→S2J1, PCIE_0P9/1P2→S7F0 | (driver-internal) | reference |

**Conclusion [verified]: the pins in our DT are the right pins for this
tablet on this firmware.** The "wrong pins inherited from nubia" hypothesis
is dead: nubia NX809J (`kaanapali-nubia-nx809j.dts:390-451`) and iceland use
the same TLMM16/PMIC-J-gpio5 *because the hardware really is wired that way*,
confirmed from OPLUS's own DT off our own captured images. If you re-run the
extraction and get different pins, the matrix collapses to the single
confirmation flight in §4.6 — not expected.

Note also: downstream has **no gpio-reserved-ranges** and Android's cnss2
driver (an HLOS/APPS driver) itself drives TLMM16 and PMIC gpio5 on this
same firmware. Since RAM-booting only replaces the boot image — XBL, TZ,
devcfg, hyp are the stock ones in both worlds — a *static* XPU protection of
these pins for APPS would break stock Android too. A static-XPU explanation
is therefore nearly excluded; only a *dynamic* protection (e.g. Gunyah/TZ
lend active until some handshake) survives as a variant. **[inferred, strong]**

### 1.4 The cross-evidence table

| Stack | pwrseq base | WLAN gpio at bind | Pins/DT | Stock fw | Result |
|---|---|---|---|---|---|
| mzakamin Fedora | v7.3-rc7 (pre-dbd674) | **GPIOD_ASIS** (no write) + same pinctrl | map220v | 11.A.38 | **works** (Wi-Fi + s2idle debug) |
| DocLogix perpetua | v7.3 tip (has dbd674) — runtime unverified | OUT_LOW if tip | map220v | unknown | BT bring-up implies pwrseq binds |
| SuperTurtleDev | v7.3 + map220v | OUT_LOW | map220v | unknown (their fw differs from 11.A.38 per manifest diff column) | untested on device |
| **us** | v7.3 perpetua | **OUT_LOW** | map220v | 11.A.38 | **hard reset at bind, twice** |

Upstream history of exactly this line (for context and for the eventual
report): 2024-08 `a9aaf1ff88a8` switched to ASIS because OUT_LOW broke
already-powered modules; 2024-12 revert attempt (RFT) failed testing
(ath12k ID 0xffff, Stephan Gerhold); 2026-10 `dbd674ccf30f` finally flipped
to OUT_LOW after pwrctrl ordering made it safe *for PCIe reasons*. Nobody
has reported an SoC-level reset from it — ours would be the first, which is
plausible for an OPLUS device with TME-L/connsec integration (the WCN7860
"Peri" subsystem is TMEL-managed per `3c983bfbad01`'s description).

---

## 2. Ranked root-cause hypotheses

**H1 — the `dbd674ccf30f` OUT_LOW write on TLMM16 is the trigger.**
The only bind-time hardware delta between the proven-working stack
(mzakamin, same tablet model, same 11.A.38 firmware, same DT) and ours.
Two candidate mechanisms:
  - H1a: XBL/ABL leaves the WCN powered (or its EN pin driven high); the
    abrupt low pulse on WLAN_EN kills a chip that TZ/TME-L ("connsec")
    still has a session with → secure-world panic → SoC reset.
  - H1b: writing the IO/OE bits specifically (vs the CFG write, which
    mzakamin's pinctrl also performed and survived) trips a *dynamic*
    protection. Same flight signature as H1a; distinguished by the Flight 0
    register decode (was the pin actually driven high before?).
Evidence for: §1.4 table; upstream's own history of this exact line being
device-breaking; mzakamin's identical pinctrl writes surviving on the same
firmware. Evidence against: DocLogix's tree-tip BT bring-up (runtime kernel
unverified). **Probability ~55%.**

**H2 — the PMIC-J gpio5 writes (pinctrl config and/or gpiod output-low).**
Same writes exist in mzakamin's working stack (bt gpiod has been OUT_LOW in
every driver version, `pwrseq-qcom-wcn.c:510`), which argues strongly
against — *unless* their early (=y, boot-time) bind vs our late modprobe
lands in a different PMIC/SPMI arbiter state. **Probability ~15%.**

**H3 — late-vs-early bind environment.** All working references bind at
early boot (=y) or at least during coldplug; our confirmed resets are manual
modprobe on a settled system. If some built-in driver or TZ interaction
re-arms a protection after boot (Gunyah lend, AOSS/QMP state, SPMI arbiter
ownership rewrite), the same write could be fatal only later. Testable for
free (Flight 1 runs on a fresh diag boot with the 29 radio/AV modules still
blacklisted). **Probability ~15%.**

**H4 — regulator handle acquisition (one of the six RPMh supplies).**
`regulator_bulk_get` performs no hardware access for RPMh regulators and all
six rails exist and are managed by the always-booted RPMh; also identical
gets succeed in the working stacks. Kept because it is one `modprobe` away
from exclusion. **Probability ~5%.**

**H5 — rpmhcc RF_CLK1 handle.** Get-only, no vote; same reasoning.
**Probability ~5%.**

**H6 — TLMM16 config write (pinctrl) itself.** mzakamin's port applies the
identical `wlan_en` state on the same firmware and lives; CTL and IO share
the same 4K XPU granule so a protected pin would kill both ports. Only
survives as the dynamic-protection variant of H1b. **Probability ~5%.**

(Dead: wrong pin numbers — §1.3. Dead: static XPU on gpio16/gpio5 — §1.3
last paragraph.)

---

## 3. Fix candidates, ranked (apply after the matrix identifies the branch)

1. **Local driver patch: request the WLAN enable GPIO `GPIOD_ASIS` again**
   (revert of `dbd674ccf30f`, or better: only for `qcom,wcn7860-pmu`
   pdata via a `power_off_on_probe` flag) — if H1 confirms.
   Mechanics: drop a patch into `kernel/patches/` of this repo (both
   build-mainline-kernel.sh and make-diag-bootimg.sh apply that dir to the
   worktree — `scripts/make-diag-bootimg.sh:80-87`).
   Risk: the exact failure dbd674 fixes (Surface Pro 11: ~10 deferred host
   inits power-cycle the PHY while the chip stays up; link never trains).
   On iceland the pwrseq module is loaded *before* pci_pwrctrl_pwrseq in our
   flights, so the deferral storm shouldn't occur; verify gate 2 anyway.
   **Upstreamability: good as a report, medium as a patch.** Upstream has
   flip-flopped twice on this line; a reproducible "OUT_LOW at probe
   hard-resets the SoC on OPLUS iceland (WCN7860)" report to Bartosz
   Golaszewski / linux-pm with our bisect is exactly the missing regression
   evidence. Likely upstream shape: per-compatible opt-out or a DT property
   (e.g. honouring an existing `wlan-enable` state), not a blanket revert.
2. **DT supply-name correction to the downstream map** (vddaon→L2G,
   vddcx→S1J + driver pdata gaining "vddcx"; drop "vddio") — **not a reset
   fix** (rail *set* is identical today, §1.3), but required for honest
   bindings and for per-rail voltages/loads later; adopt the Fedora pair
   (their infiniti 0080 pdata + their 0167 DT patch) wholesale to stay
   aligned with a tested stack. **Upstreamability: high** (bindings +
   board DT + pdata change; coordinate with Teguh/map220v who own the
   in-flight wcn7860 series).
3. **pinctrl state trim** — if F3 lands on one specific state: drop or
   correct that state (e.g. drop `bt_default` and let gpiod do the PMIC
   config, or drop `wlan_en` and let gpiod mux the pin). A node property
   change in our board DT; **upstreamability high** once explained.
4. **wlan_en state content fix** (cosmetic unless F3-TLMM implicates it):
   downstream "active" is pull-up/drive-16, sleep is pull-down/drive-2; ours
   is a single pull-down/drive-8 state. Consider matching downstream sleep
   config exactly for the default state. **Upstreamability: trivial.**
5. **gpio-reserved-ranges** — only if the Flight 0 *read* of TLMM16 resets
   (dynamic read-protection): add `<16 1>` (and whatever else proves hot) to
   `&tlmm gpio-reserved-ranges` (dts:1338-1339, currently `<36 4>`) to make
   the kernel refuse all access; WLAN would then need the chip-left-on
   strategy (no EN control) — a last resort, document-and-escalate.
   **Upstreamability: high if genuinely protected, but it conflicts with
   downstream evidence; expect not to need it.**
6. **modules-load ordering fix** — if H3 confirms (F1 survives on a fresh
   boot): load `pwrseq_qcom_wcn` from `/etc/modules-load.d/` (initramfs
   phase) before the arming module (then bisect which of the 29 arms it),
   or flip to `CONFIG_POWER_SEQUENCING_QCOM_WCN=y` like mzakamin/
   SuperTurtleDev/roadstr. **Upstreamability: n/a (packaging), but flag the
   arming driver upstream.**

---

## 4. Tomorrow's flight matrix

### 4.0 Prep (host, ~20 min)

1. Build the *unmodified* diag image once:
   `scripts/make-diag-bootimg.sh` → `fastboot boot
   $UBUNTU_WORKDIR/out/test-boot-diag.img`. Its bootargs already blacklist
   the whole radio/AV set including `pwrseq_qcom_wcn,pci_pwrctrl_pwrseq,
   ath12k,btqca,hci_uart` (script lines ~115-120), so nothing loads until we
   say so. panic=10 and the USB beacon make deaths visible.
2. Per-flight DT edits go in as **temporary patch files** in
   `kernel/patches/` (the diag script recreates the worktree and `git
   apply`s everything there, then adds its own edits on top — script lines
   73-90). Recipe per flight:

   ```sh
   cd /srv/ubuntu-iceland/build/linux-src-iceland
   git checkout -- arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts
   python3 - <<'EOF'      # per-flight edit, see each flight below
   ...
   EOF
   git diff > ~/projects/ubuntu-oneplus-pad-4/kernel/patches/90-flight.patch
   git checkout -- arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts
   ~/projects/ubuntu-oneplus-pad-4/scripts/make-diag-bootimg.sh
   rm ~/projects/ubuntu-oneplus-pad-4/kernel/patches/90-flight.patch
   ```

   All edit anchors below were verified unique in the DTS tonight (grep -c
   = 1 for each full line). Never leave `90-flight.patch` in place for a
   release build.
3. Access per runbook: `ssh ubuntu@192.168.7.2` over the gadget; ONE serial
   listener on /dev/ttyACM0. Start a serial log capture (`tee`) before every
   modprobe — the last line before a reset is evidence.
4. Flight bookkeeping: for every flight record — edit applied, exact
   commands, survived/reset, time-to-death (instant vs ~5 s), last serial
   line, `dmesg | grep -i 'pwrseq\|wcn\|pinctrl'` when it survives.

Success criterion for "survives": `modprobe pwrseq_qcom_wcn` returns, 20 s
settle passes, and
`readlink /sys/bus/platform/devices/wcn7860-pmu/driver` →
`.../pwrseq-qcom_wcn`.

### 4.1 Flight 0 — zero-change instrumentation reads (same boot as F1)

On the first diag boot, before anything else (busybox devmem; fallback:
`python3 -c` mmap of /dev/mem — CONFIG_DEVMEM=y, STRICT_DEVMEM without
IO_STRICT_DEVMEM allows MMIO **[verified .config]**):

```sh
# method check on a pin the kernel already writes every boot (pcie0 perst):
busybox devmem 0x0F166000; busybox devmem 0x0F166004    # gpio102 CTL, IO
# sw_ctrl: an INPUT from the WCN; IO bit0 = is the chip alive and driving it?
busybox devmem 0x0F112000; busybox devmem 0x0F112004    # gpio18
# the suspect itself — may reset if dynamically read-protected (accepted):
busybox devmem 0x0F110000; busybox devmem 0x0F110004    # gpio16 CTL, IO
```

Decode (pinctrl-msm layout): CTL bits[1:0] pull (0 none/1 down/2 keeper/3 up),
bits[5:2] FUNC_SEL (0=GPIO), bits[8:6] drive ((n+1)*2 mA), bit9 OE.
IO bit0 = input level, bit1 = output value.

Branches:
- **gpio16 read resets** → dynamic protection exists even for reads →
  jump to §3 fix 5 track + escalate (compare devcfg/tz_ac_config across
  OxygenOS builds; ask DocLogix/mzakamin for their exact OTA level). Flights
  F2+ still run — a write-level map is still useful — but expectation flips.
- **gpio16 reads OK** → record FUNC_SEL/OE/OUT. `OE=1 && OUT=1` = bootloader
  left WLAN_EN driven high = chip likely live → strong H1a. `OE=0` = chip
  parked → H1a weakens, H1b/H2 gain. gpio18 IO bit0 high also indicates a
  live WCN (SW_CTRL driven).

### 4.2 Flight 1 — baseline reproduce + stage trace (no DT change)

Same boot. Turn on the driver-core/pinctrl/gpio trace, then load:

```sh
echo 'file drivers/base/dd.c +p'        > /sys/kernel/debug/dynamic_debug/control
echo 'file drivers/base/pinctrl.c +p'   > /sys/kernel/debug/dynamic_debug/control
echo 'file drivers/pinctrl/* +p'        > /sys/kernel/debug/dynamic_debug/control
echo 'file drivers/gpio/* +p'           > /sys/kernel/debug/dynamic_debug/control
echo 8 > /proc/sys/kernel/printk
modprobe pwrseq_qcom_wcn; sleep 20
```

- **Resets (expected)** → baseline reproduced in the diag environment,
  which *also* proves none of the 29 blacklisted modules is needed to arm
  the trap (H3 mostly dead: this boot loaded pwrseq with the other radio/AV
  modules absent). Read the serial tail: "probing driver pwrseq-qcom_wcn with device
  wcn7860-pmu" then silence → died in pinctrl_bind_pins (F3 series next,
  skip F2); gpio/regulator lines visible after it → died in the probe body
  (F4 series next, skip F2). **Caveat: printk is asynchronous — a missing
  line is a hint, not proof.** If the tail is ambiguous, run F2.
- **Survives (surprise)** → H3 revives: the trap is armed by something the
  diag boot doesn't run. Continue loading the blacklist set one-by-one
  (audio first, then qcom_q6v5_pas, fastrpc...) re-testing nothing — the
  arming module makes the *next boot's* F1 die after it loads. Binary-search
  the 29 across boots (~5 boots). Fix track = §3 fix 6.

### 4.3 Flight 2 — pinctrl vs probe-body split (first DT edit)

Edit (delete both pinctrl lines from the pmu node):

```python
import pathlib
p = pathlib.Path('arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts')
t = p.read_text()
t = t.replace('\t\tpinctrl-names = "default";\n\t\tpinctrl-0 = <&wlan_en>, <&bt_default>;\n\n', '')
assert 'pinctrl-0 = <&wlan_en>' not in t
p.write_text(t)
```

Boot, `modprobe pwrseq_qcom_wcn`, settle 20 s.

- **Survives** → the trigger is the pinctrl "default" application (TLMM16
  cfg and/or PMIC gpio5 cfg) — and *not* the gpiod OUT_LOW writes, which
  still ran. Interesting twist: this outcome means the OUT_LOW write to
  TLMM16 is safe, mostly killing H1 and pointing at H6/H2-config. → F3.
- **Resets** → trigger is in the probe body (gpiod gets / regulator gets /
  clk get). → F4 (keep this edit in place; F4 adds one more delta each).

### 4.4 Flight 3 series — which pinctrl state (only if F2 survived)

F3-TLMM: restore pinctrl, reference **only** `wlan_en`:
edit = same replace but writing
`'\t\tpinctrl-names = "default";\n\t\tpinctrl-0 = <&wlan_en>;\n\n'`.
- Resets → TLMM16 config write is the killer (H6; cross-check F0 decode;
  fix track §3 3/4/5).
- Survives → F3-PMIC: `pinctrl-0 = <&bt_default>;`
  - Resets → PMIC-J gpio5 config write is the killer (H2; the delta vs
    downstream `bt_en` is only our extra `output-low` — try a variant state
    without it; fix track §3 3).
  - Both survive → application *order/combination* mattered (apply both,
    original order: should reset per F2... if it doesn't, the world is
    non-deterministic — re-run F2 before concluding anything).

### 4.5 Flight 4 series — which probe-body get (only if F2 reset)

Each flight keeps the F2 edit (no pinctrl) and adds exactly one deletion.

F4a: also delete `\t\twlan-enable-gpios = <&tlmm 16 GPIO_ACTIVE_HIGH>;\n`.
- **Survives** → the TLMM16 OUT_LOW/OE write was the trigger → **H1
  confirmed** (with F0 decode distinguishing H1a vs H1b). Fix track §3 1.
  Bonus probe on the same boot: `modprobe pci_pwrctrl_pwrseq` and watch
  lspci — with the chip left in its boot state the link may even train.
- Resets → F4b: restore the wlan line, delete
  `\t\tbt-enable-gpios = <&pmh0104_j_e1_gpios 5 GPIO_ACTIVE_HIGH>;\n` instead.
  - Survives → PMIC-J gpio5 OUT_LOW write (H2). Fix track §3 3 + upstream
    report.
  - Resets → F4c: delete **both** gpio lines.
    - Survives → "needs both deleted"?? Re-run F4a and F4b once each first
      (flaky-harness check) before believing a combined trigger.
    - Resets → the trigger is a *get*, not a write: F4d delete the six
      `-supply` lines (anchors: the exact six lines dts:358-363)
      → survives = regulator get path (H4): bisect the six singly,
      suspicion order S1J, S2J (the "J" PMIC also hosts bt gpio), L2G...
      → still resets = F4e delete `\t\tclocks = <&rpmhcc RPMH_RF_CLK1>;\n`
      (H5). If F4e *still* resets with a node that has nothing but
      compatible+regulators left, re-examine assumptions (pwrseq core,
      platform bus) — that result contradicts §1.1 and earns a fresh look
      at the serial trace.

### 4.6 The collapsed matrix (only if re-extraction contradicts §1.3)

If the downstream re-extraction (appendix A) yields pins ≠ {tlmm16,
pmh0104-J gpio5}: single confirmation flight — change
`wlan-enable-gpios`/`wlan_en pins` (and/or bt side) to the downstream
numbers in one edit, boot, modprobe, expect bind + survive; then stop and
redo §1.3 before anything else. Tonight's extraction says this branch will
not be taken.

### 4.7 After the first surviving *full-node* configuration

(i.e. a survival with no properties deleted — via fix §3 1 driver patch or
whatever the matrix selected — not a reduced-DT diagnostic survival):

1. `modprobe pci_pwrctrl_pwrseq` → pcie0 host init un-defers; expect
   `pci 0002:01:00.0 [17cb:110e]` in lspci within seconds.
2. Stage firmware (§5), `modprobe ath12k`.
3. Gates in §6, in order.

---

## 5. Firmware staging (hash-verified, from the Fedora clone)

Source tree (already on disk):
`/tmp/claude-1000/-home-jstockdale-projects-arch-oneplus-pad-4/29772f33-9e3d-45de-9bdd-4279cde4b0f0/scratchpad/mzakamin-review/iceland-firmware/root/usr/lib/firmware/updates/ath12k/WCN7860/hw2.0/`
Manifest: `../../iceland-firmware/MANIFEST.tsv` (extraction provenance:
stock 11.A.38 `modem_a:/image/peach/*` and `odm:/etc/wifi/peach/*` — same
OTA as our unit, §1.3).

Expected SHA256 (from MANIFEST.tsv, de-duplicated — verified tonight against
the files on disk by the manifest's own claim; re-verify at staging time):

| file | sha256 | bytes |
|---|---|---|
| amss.bin | 23811bd6abe91a89ef00057e0a4d2e85ea3d0defcad377334cdef987ec4df820 | 7475264 |
| aux_ucode.bin | 4db9df6fdac982752f71c513f174da7e22307a769a9d49fd336b054919c9451e | 61440 |
| board.bin | 355578ce4162b885c9371e8df7eac20bb4bcd28c8b9d11cf0bdd5114ec6cfe3c | 125396 |
| m3.bin | c1a1295b1808ba204676c03967aea91effc5d85b55a9d269ba858c5e80c92b9c | 290816 |
| qdss.cfg | 4683d8683437a11172723dc5820801aaaf5eb082336875a7664142582cc90cbb | 6245 |
| regdb.bin | 365026525f6a9a1ebf0668b8c61fb1300bfdb2450148e994b9a4ca66257e7e43 | 24278 |

```sh
FW=/tmp/claude-1000/-home-jstockdale-projects-arch-oneplus-pad-4/29772f33-9e3d-45de-9bdd-4279cde4b0f0/scratchpad/mzakamin-review/iceland-firmware
cd "$FW/root/usr/lib/firmware/updates/ath12k/WCN7860/hw2.0"
sha256sum -c - <<'EOF' || { echo "HASH MISMATCH - STOP"; false; }
23811bd6abe91a89ef00057e0a4d2e85ea3d0defcad377334cdef987ec4df820  amss.bin
4db9df6fdac982752f71c513f174da7e22307a769a9d49fd336b054919c9451e  aux_ucode.bin
355578ce4162b885c9371e8df7eac20bb4bcd28c8b9d11cf0bdd5114ec6cfe3c  board.bin
c1a1295b1808ba204676c03967aea91effc5d85b55a9d269ba858c5e80c92b9c  m3.bin
4683d8683437a11172723dc5820801aaaf5eb082336875a7664142582cc90cbb  qdss.cfg
365026525f6a9a1ebf0668b8c61fb1300bfdb2450148e994b9a4ca66257e7e43  regdb.bin
EOF
# (the block above IS the MANIFEST.tsv ath12k set, transcribed 2026-11-01;
#  cross-check against the live manifest if in doubt:
#  awk -F'\t' '$1 ~ /ath12k/ {print $2, $1}' "$FW/MANIFEST.tsv" | sort -u)
# stage to the tablet (path per plan; ath12k also searches updates/ but we
# standardize on the plain path):
scp amss.bin aux_ucode.bin board.bin m3.bin qdss.cfg regdb.bin \
  ubuntu@192.168.7.2:/tmp/ && ssh ubuntu@192.168.7.2 \
  'sudo install -D -m0644 -t /lib/firmware/ath12k/WCN7860/hw2.0 /tmp/{amss.bin,aux_ucode.bin,board.bin,m3.bin,qdss.cfg,regdb.bin} && sync'
```

The requirement is absolute: every byte verified against MANIFEST.tsv before
it lands in /lib/firmware. ath12k prefers
board-2.bin and falls back to board.bin — the manifest set has board.bin,
which is what the Fedora port runs. perpetua already carries the WCN7860
ath12k hw params and the QDSS quirk (`28c1d15fa4fb`, `fe38e1854b72`).

Also bank the set into `out/rootfs-overlay` the same way the GPU firmware
was, once validated — but only after gate 3 passes.

## 6. Validation gates (stop at the first failure, keep the log)

1. **pwrseq probe survives**: modprobe, 20 s settle,
   `/sys/bus/platform/devices/wcn7860-pmu/driver` → pwrseq-qcom_wcn.
2. **PCIe enumerates WCN**: `modprobe pci_pwrctrl_pwrseq`;
   `lspci -nn | grep 17cb:110e`; dmesg shows pcie0 link up
   (if the link flaps or "Device found, but not active" appears, we are in
   dbd674's Surface territory — record and re-read §3 1 risk note).
3. **ath12k binds + firmware loads**: `modprobe ath12k`; dmesg shows
   `ath12k_pci ... chip_id` / firmware `WCN7860/hw2.0/amss.bin` load, no
   QMI timeout; `ip link` gains wlanX. (ath12k_pci supported-id 110e is in
   our tree; QDSS quirk already applied.)
4. **Connect**: `nmcli dev wifi list` sees the lab SSID;
   `nmcli dev wifi connect <ssid> password <pw>`; link-local ping + DNS.
5. **iperf sanity**: `iperf3 -c <host>` both directions ≥ a sane WCN7860
   number (tens of Mbit at worst in this bring-up state; record, don't
   gate hard).
6. **ssh over WLAN with usb0 fallback intact**: open a second ssh via the
   WLAN address while the gadget session stays up; confirm usb0 route still
   metric **1024 by design** (`ip route`), so WLAN (metric <1024) wins when
   up and the gadget path survives when WLAN drops. Reboot once (RAM boot)
   and re-verify blacklist/modprobe sequencing still gives a stable boot.

Suspend/wake (mzakamin 0040: wake-gpios should be ACTIVE_LOW) is **phase
C+1**, not tomorrow — but when s2idle testing starts, apply their 0040 DT
fix first.

---

## Appendix A — downstream DT extraction (documented + trial-run tonight)

Everything below ran tonight read-only against the fcap captures; outputs in
`/tmp/claude-1000/-home-jstockdale-projects-arch-oneplus-pad-4/737a94a9-ba23-47ec-b0b2-3004a998b10e/scratchpad/dtb-work/`
(ephemeral — regenerate at will; takes ~1 min):

```sh
W=~/scratch/dtb-work && mkdir -p $W && cd $W
# 1. vendor_boot (header v4): base SoC DTBs live in its dtb blob
unpack_bootimg --boot_img /srv/ubuntu-iceland/factory/fcap/part-vendor_boot_a.img --out vb_a
# 2. split any multi-DTB blob on the FDT magic (works for dtbo images too):
cat > /tmp/split_dtb.py <<'EOF'
import sys, struct, pathlib
src = pathlib.Path(sys.argv[1]); outdir = pathlib.Path(sys.argv[2]); outdir.mkdir(parents=True, exist_ok=True)
data = src.read_bytes(); i = 0; n = 0
while True:
    j = data.find(b'\xd0\x0d\xfe\xed', i)
    if j < 0: break
    if j + 8 <= len(data):
        total = struct.unpack('>I', data[j+4:j+8])[0]
        if 64 <= total <= len(data) - j:
            (outdir / f'{n:02d}.dtb').write_bytes(data[j:j+total]); n += 1; i = j + total; continue
    i = j + 4
print(f'{n} DTBs extracted to {outdir}')
EOF
python3 -I /tmp/split_dtb.py vb_a/dtb vb_dtbs          # → 14 QC base DTs ("Canoe"/"Alor")
python3 -I /tmp/split_dtb.py /srv/ubuntu-iceland/factory/fcap/part-dtbo_a.img dtbo_dtbs  # → 8 iceland overlays
for f in vb_dtbs/*.dtb dtbo_dtbs/*.dtb; do dtc -I dtb -O dts -o ${f%.dtb}.dts $f 2>/dev/null; done
# 3. what to grep (downstream names differ from mainline):
grep -n -A14 'cnss_pins {' dtbo_dtbs/00.dts            # wlan_en active/sleep, sw_ctrl pins
grep -n -A60 'qcom,cnss-peach@b0000000 {' dtbo_dtbs/00.dts | sed -n '/phandle/,/compatible/p'
#   wlan-en-gpio / qcom,bt-en-gpio / qcom,sw-ctrl-gpio / wlan-host-sol-gpio /
#   vdd-wlan-*-supply / qcom,pmu_vreg_map / qcom,wlan-rc-num
grep -n -B2 -A10 'bt_en {' dtbo_dtbs/00.dts            # PMIC bt_en pinctrl
grep -n 'wcn786x' dtbo_dtbs/00.dts                     # BT node: qcom,bt-reset-gpio etc.
# supply phandles resolve via the __fixups__ / symbol lists at the end of the
# dts (grep 'L2G = \|S1J = ' etc.); GPIO cells read as <phandle pin flags>,
# pin in hex (0x10 = 16). PMIC gpio parent phandle 0xb7 = pmh0104@9/pinctrl@8800.
```

Results (entry 00; entries 01-07 are regional/bin variants, WLAN identical):
summarized in §1.3. The second cnss-peach instance (fragment@73) differs
only in lacking the L3K ant-share supply.

boot.img (`/srv/ubuntu-iceland/stock/current/boot.img`) contains no DTB on
this device (GKI kernel; DTB comes from vendor_boot+dtbo) — vendor_boot_a/b
and dtbo_a are the complete downstream DT source. `part-dtbo_b.img` can be
split identically if cross-checking slots is ever needed.

## Appendix B — handy numbers

- TLMM: base 0x0F100000, 218 pins (`kaanapali.dtsi:5017-5023`), stride
  0x1000. CTL +0x0, IO +0x4. gpio16 → 0x0F110000/0x0F110004;
  gpio18 → 0x0F112000/4; gpio102 (pcie perst, proven-written-safe)
  → 0x0F166000/4; gpio204 (host SOL) → 0x0F1CC000/4.
- PMIC J = pmh0104, SPMI bus1 SID 9, gpio block 0x8800, 8 gpios
  (`pmh0104-kaanapali.dtsi:39-61`); gpio5 peripheral base 0x8C00.
  Do **not** dump SPMI regmap ranges blind; targeted work only.
- Module/bootarg names: `pwrseq_qcom_wcn` (pwrseq-qcom-wcn.ko),
  `pci_pwrctrl_pwrseq`; both in the diag blacklist already.
- Our kernel config: POWER_SEQUENCING=y, POWER_SEQUENCING_QCOM_WCN=m,
  DEVMEM=y, STRICT_DEVMEM=y + IO_STRICT_DEVMEM unset, DEBUG_FS allow-all,
  GPIO_CDEV v2-only.
- perpetua commits of record: DT `11e47b85171c`; pwrseq wcn7860
  `b7d0e03a2150`; pwrctrl 110e `52961164525a`; ath12k `28c1d15fa4fb` +
  `fe38e1854b72`; BT `3290330664bc` + `3c983bfbad01`; **the suspect**
  `dbd674ccf30f` (upstream, Cc stable, "power off WLAN at probe").
- Upstream history links: ASIS fix (patchew.org/linux/
  20240813190751.155035-1-brgl@bgdev.pl), Dec-2024 RFT revert thread
  (lkml "Revert \"power: sequencing: request the WLAN enable GPIO as-is\""),
  XPU-reset lore (patchwork.kernel.org/comment/24102479).

## Appendix C — open questions for the community (fire off in parallel)

1. DocLogix: which exact kernel commit does the daily-driver Pad 4 run, and
   does it include `dbd674ccf30f`? Does pwrseq bind as a module there or
   built-in? (Their answer alone may confirm or kill H1/H3.)
2. mzakamin: exact OxygenOS OTA on their test unit (we're
   OPD2514_16.0.10.501_GLO_11.A.38) and whether they ever tried a
   post-dbd674 kernel.
3. Upstream (after the matrix lands): regression report to Bartosz
   Golaszewski / linux-pm with the bisect, the OPLUS reset signature and the
   flight evidence — whatever branch wins, the report is valuable.
