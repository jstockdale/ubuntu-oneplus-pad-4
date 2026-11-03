# Media & misc plan: VPU, haptics, GNSS, suspend scoping, cameras

Date: 2026-11-01 (research session; no device contact, no flights flown).
Scope: the five remaining minor subsystems after C2/C3 — video decode/encode
(iris VPU), haptics, GNSS/location, suspend (s2idle) scoping, and cameras —
ordered by effort-to-payoff for a tablet daily-driver. Two of the five turn
out to be hardware-absent paper closures (haptics, GNSS); one is a config
+ cherry-pick exercise with the firmware already on the tablet (VPU); one is
a real but fully-mapped campaign (suspend = C6); one is the only genuinely
new porting work left (cameras).

All "ours" file:line references are against the pristine clone
`/srv/ubuntu-iceland/linux-perpetua` at `7c98a10e6bb7` (perpetua/v7.3) and
the build config `/srv/ubuntu-iceland/build/linux-iceland/.config`, unless
noted. **[V]** = read from the named file during this session; **[I]** =
inferred, not observed.

## Reference stacks used (provenance)

- **Fedora port (mzakamin)** — clone at
  `<scratch>/mzakamin-review/`
  (referenced below as `FED/`):
  - `FED/iceland-linux` — `main` = queue **q89g** (v7.3-rc7 base, the first
    install image; patches on disk in `patches/0001-infiniti/` (132) +
    `patches/0002-iceland/` (294)). The current branch
    `iceland-7.3-rc7-next` was **fetched tonight** to `FETCH_HEAD`
    (`1006a29d2170`, queue **q90z**, base linux-next `next-20261020`,
    release `7.3.0-next-20261020-iceland-00572`); its extra series
    `patches/0003-glitchfix/`…`patches/0027-q90z/` are cited via
    `git cat-file FETCH_HEAD:…` — they are not checked out. [V]
  - `FED/iceland-mainline` @ `a7aab9f` (fetched tonight, == origin/main):
    `docs/FEATURES.md` (the 110-feature "what works" list, 27 Oct),
    `docs/guide/02-HARDWARE.md`, `docs/reference/pad4-hardware-boot-partitions.md`
    (their measured hardware survey), packaging for libcamera/iris-vaapi/
    iceland-device. [V]
  - `FED/iceland-firmware` @ `6fdbbe3` (11.A.38-6), MANIFEST.tsv. [V]
- **denialwm/perpetua** — our own pinned tree (above) + `devices/iceland/`
  fragments; **phonewave** iceland runtime at
  `…/29772f33…/scratchpad/research/repos/phonewave/devices/iceland/`. [V]
- **Stock, our own unit** (11.A.38, `OPD2514_16.0.10.501_GLO`):
  `/srv/ubuntu-iceland/stock/vendor-extracted/` (vendor.img, EROFS) and the
  decoded factory DTBO at
  `<scratch>/dtb-work/dtbo_dtbs/00.dts`
  (regenerable per wifi-plan.md appendix A). [V]

Fedora runtime proof points quoted below come from `FED/iceland-mainline/
docs/FEATURES.md` (their tablet, same model, same 11.A.38 firmware
generation as ours — wifi-plan §1.3 established the OTA match).

---

## Safety rails (verbatim, non-negotiable)

- Never `fastboot set_active`; never write vbmeta / dtbo / vendor_boot /
  GPT; no EDL.
- One variable per flight. Kernel changes fly as `fastboot boot` RAM boots
  before anything is flashed. Diagnostic kernels build no modules.
- **Module-subsystem corollary** (all five subsystems here are `=m`):
  media/suspend flights use **release-config RAM boots** (bundle kernel +
  DTB) with the matching modules staged on the rootfs first — the C3
  lesson "make-diag builds Image+dtbs only; module patches need
  make modules + rootfs install" applies to every rung below. Never
  evaluate PM behaviour (suspend, runtime PM, votes) under the diag
  cmdline: `pd/clk_ignore_unused` masks exactly what we are measuring,
  and the S1J saga proved diag-env PM results mislead.
- Suspend testing is never attempted on a flashed-only path without the
  recovery story documented first (§4.0): wake failure → long power-press
  forced reboot → flashed slot-B Ubuntu boots on its own. RAM-booted
  kernels are RAM-resident across s2idle (no reboot involved), so s2idle
  flights on RAM boots risk nothing persistent.

---

## 0. Verdict and ordering (effort-to-payoff)

| # | Subsystem | Verdict | Effort | Payoff |
|---|---|---|---|---|
| 1 | **VPU (iris)** | adopt ~10 Fedora/QC patches + 2 DT hunks; firmware already on the tablet since Phase A | S | high (video is the tablet's job) |
| 2 | **Haptics** | **close as N/A — no vibrator motor fitted**; stock DT has the PMIH010x haptics block `status = "disabled"` | zero | closes a line item |
| 3 | **GNSS** | **close as N/A — no GNSS hardware on this board**; optional geoclue Wi-Fi positioning in userspace | zero kernel; XS userspace | city-level location only |
| 4 | **Suspend (s2idle)** | real campaign (C6) but fully de-risked: Fedora ships s2idle **as the default sleep** with 0.35 %/h overnight drain; their fix list is enumerable, file by file | M (one campaign, ~8 patches + DT fixes + userspace ordering) | highest single dailyability win |
| 5 | **Cameras** | the one real port: new sensor driver (SmartSens SC1320CS/SC820CS, Fedora-authored, not upstream) + board DT + libcamera soft-ISP userspace | L | medium (Snapshot-grade, fixed-focus-grade) |

**Prior check** (the brief's prior: VPU+haptics cheap, GNSS medium, suspend
its own campaign, camera last): broadly confirmed, with two overturns —
- **GNSS is not "medium", it is N/A.** The brief's premise "the WCN7860
  combo chip also carries GNSS" does not hold on this board: SM8850**P**
  has no modem, the stock vendor image ships **no** `android.hardware.gnss`
  HAL at all, the downstream DT has zero GNSS nodes, and the Fedora
  hardware survey records "no modem/GNSS/NFC **[measured]**" (§3).
  Whatever GNSS silicon the WCN786x family may offer is unprovisioned
  here: no firmware, no HAL, no DT, no driver in any of the three sibling
  ports. There is nothing to port.
- **Haptics is even cheaper than "cheap": zero.** No motor is fitted
  (§2). Our hardware-status.md rows "Vibration ❓" and "Suspend ❓ works
  per Nura wiki" should be updated from this document's evidence when
  hardware-status is next touched (not done here).

Recommended sequencing against the roadmap: **VPU now** (slots before/with
C5 — hardware video is a desktop prereq for a tablet), haptics+GNSS are
paper closures bundled with this document, **suspend stays C6** exactly as
bringup-plan.md has it, **camera after C6** (it is the only item that can
absorb unbounded time and it blocks nothing else).

---

## 1. VPU — iris video decode/encode

### 1.1 Current evidence (ours)

- Driver: `CONFIG_VIDEO_QCOM_IRIS=m` already set (also `VENUS=m`, harmless)
  **[V .config]**. But the pinned tree's iris driver has **no kaanapali
  support**: the of_match table ends at sm8750/x1p42100
  (`drivers/media/platform/qcom/iris/iris_probe.c:360-388`), there is no
  `iris_platform_kaanapali.h`, and `git log c03c1a14507d..7c98a10e6bb7 --
  drivers/media/platform/qcom/iris` is empty — perpetua never touched
  iris. **[V]**
- DT: `kaanapali.dtsi` carries the prerequisites — `videocc:
  clock-controller@20f0000` (`qcom,kaanapali-videocc`, :2775) and the
  `video_mem: video@9a600000` carve-out (:476) — but **no iris node**.
  `CONFIG_CLK_KAANAPALI_VIDEOCC=y`. **[V]**
- Firmware: `vpu40_2v.mbn` has been staged at
  `/lib/firmware/qcom/kaanapali/iceland/` on the tablet **since Phase A**
  (docs/firmware-manifest.md:35-37), sourced from our own stock
  extraction. sha256 `69d4e2154ca1704a751922d2b6e4680539c995d1e85dcf07ab349a009a411abc`
  (2486984 B) — **byte-identical to the Fedora firmware repo's copy**
  (`FED/iceland-firmware MANIFEST.tsv`, path
  `updates/qcom/kaanapali/iceland/vpu40_2v.mbn`, same hash, their own
  independent extraction from vendor_a). Double-corroborated. **[V]**
- No `/dev/video*` exists today (nothing binds).

### 1.2 What Fedora does (file-level)

Platform support, from Qualcomm's in-flight upstream series carried via
infiniti (`FED/iceland-linux/patches/0001-infiniti/`):

- `0031-media-dt-bindings-qcom-kaanapali-iris-…` — binding,
  `qcom,kaanapali-iris` (Vikash Garodia, @oss.qualcomm.com).
- `0033-media-iris-Add-platform-data-for-kaanapali` — adds
  `iris_platform_kaanapali.h` + `kaanapali_data` to
  `iris_platform_vpu3x.c`; firmware descriptor
  `iris_vpu40_p2_gen2_desc` with `.fwname = "qcom/vpu/vpu40_p2.mbn"` and
  `vpu_ops = &iris_vpu4x_ops` (iris4 / VPU4x generation). **[V]**
- `0032` (AV1 decode buffer sizes), `0034` (iris4 H265 line buffer),
  `0037` (VPSS line buffer w/h order), `0038` (VPU4x encoder line buffer),
  `0069-0071` (MVP NoC low-power release, hierarchical-B only on
  kaanapali, decoder picture-state quirk). (0036 bus_info fix is already
  upstream in their next-20261020 base — it has dropped out of the
  FETCH_HEAD series.) **[V]**
- `0035-arm64-dts-qcom-kaanapali-Add-iris-video-node` — dtsi node
  `iris: video-codec@2000000`, power-domains from videocc
  (`VIDEO_CC_MVS0C_GDSC` …), `memory-region = <&video_mem>`, `iommus =
  <&apps_smmu 0x1940 …>`, OPP table (authors Jingyi Wang/Vikash Garodia;
  Victor Fuentes rebased). **[V]**

Board enable (`FED/iceland-linux/patches/0002-iceland/`):

- `0062-…-enable-the-video-codec` — the whole board delta is six lines:

  ```
  &iris {
      firmware-name = "qcom/kaanapali/iceland/vpu40_2v.mbn";
      status = "okay";
  };
  ```

  i.e. they override the platform fwname with the **stock blob under its
  stock name** — exactly the file we already ship. The upstream iris
  driver honours `firmware-name` (our tree:
  `iris_firmware.c:85 of_property_read_string_index(... "firmware-name" ...)`).
  **[V both]**

Hardening carried on top (adopt with, or right after, first light):

- q89-era, in `patches/0002-iceland/`: `0157` (iova from restrict region)
  + `0158` (skip bit-depth validation on capture) — Vishnu Reddy
  (@oss.qualcomm.com); `0159` (NULL hfi_sys_ops guard) + `0160` (fail
  firmware boot on invalid uc_region) — **Dmitry Baryshkov**; `0246-0250`
  (AHB bridge reset before HW mode, power-off ordering, core lock on
  instance scan, session-limit rejection, instance refcounting) — mzak;
  `0292` (SMPTE 170M colorimetry mapping — carried but deliberately not
  sent upstream; needs an Assisted-by line per kernel policy). **[V]**
- q90-era (FETCH_HEAD only): `0002-iceland/0362` (don't wait for threaded
  IRQ handler in …), `0365-0367` (timestamp metadata OOB read, runtime-PM
  refcount on failure, disable system-error work on removal), `0385`
  (decoder OPB line buffer sizing), `patches/0027-q90z/0002` (wait for
  VPU NoC low power during power-off), q90l "EOS only for the drain's
  last buffer" (a seek no longer ends an FFmpeg stream), q90n capture
  buffer pools + VSP clock fixes. **[V listings/README]**

Proof it works on this tablet (FEATURES.md:69-70): H.264, HEVC to 4K,
VP9 (incl. 10-bit) and AV1 decode **bit-exact against Android reference
vectors**; H.264/HEVC encode (PSNR ≈ 50 dB); GNOME player 1080p H.264 at
3 % CPU; GNOME screen recording through the V4L2 encoder. Userspace:
plain GStreamer V4L2 (stateful) works as shipped by the distro; VA-API is
an optional extra via `FED/iceland-mainline/packaging/iris-vaapi/`
(CFM880/iris-vaapi a.k.a. vpu-vaapi, `LIBVA_DRIVER_NAME=iris`, needs the
q90 module param `qcom_iris.decode_order_output=1` and a
`/dev/dma_heap/system` udev rule). Known open on their side: "camera into
the hardware encoder (the pipeline does not negotiate)"
(MAINLINE-STATE.md:50-51). **[V]**

### 1.3 Upstream state of the art

The kaanapali iris series is Qualcomm-authored and in review, not merged:
v2 "media: iris: add support for video codecs on Qcom kaanapali platform"
(Oct–Nov 2025), the vpu4 prep series v3, and the binding at v3 (Mar 2026)
drew a Nacked-by (Krzysztof Kozlowski) over an `iommu-map` dt-schema
dependency — and the patches are still carried in Fedora's queue on a
linux-next `next-20261020` base, which is the cleanest proof they are not
upstream yet. Expect them in 7.5+ in some form; adopt now, rebase later.
(Search trail: lkml mirrors of the v2/v3 threads; camss/iris both follow
the same "carried until merged" pattern.) **[V queue; I timing]**

### 1.4 Gap analysis

| Piece | Ours | Action |
|---|---|---|
| iris kaanapali platform code | absent | pick infiniti 0031-0034, 0037-0038 (+0069-0071) |
| dtsi iris node | absent (videocc + video_mem present) | pick infiniti 0035 |
| board enable + firmware-name | absent | pick iceland 0062 (6 lines) |
| firmware | **already on tablet**, hash == Fedora's | none |
| config | `VIDEO_QCOM_IRIS=m` already | none (keep =m) |
| hardening set | absent | second pass: 0157-0160, 0246-0250; q90 picks on next refresh |

### 1.5 Ladder

- **VP0 — queue the patch set.** Import as our `kernel/patches/0011…`:
  infiniti 0031/0032/0033/0034/0035/0037/0038 + iceland 0062, adjusting
  only context. Build release bundle; `make modules` for iris; stage
  modules on the rootfs. Gate: clean build; `modinfo qcom-iris` shows
  kaanapali alias.
- **VP1 — RAM-boot first light.** Release-config RAM boot of the new
  bundle. `modprobe qcom_iris` (or coldplug). Gate: iris probes; dmesg
  shows `vpu40_2v.mbn` loaded and the PAS/TZ auth **succeeding**;
  `/dev/video0` + `/dev/video1` (dec/enc) appear; `v4l2-ctl
  --list-formats-out`/`--list-formats` lists H264/HEVC/VP9/AV1 on the
  decoder.
- **VP2 — decode proof.** `gst-launch-1.0 filesrc ! parsebin !
  v4l2slh264dec?` — no: iris is **stateful**; use
  `v4l2h264dec`/`v4l2vp9dec` (gstreamer1.0-plugins-good). Gate: a 1080p
  H.264 and a VP9 clip decode to raw frames (filesink checksum run twice,
  identical), then on-screen in GNOME's player with CPU well under
  software-decode levels. Fedora's benchmark: 3 % vs 47 % CPU.
- **VP3 — encode proof.** `v4l2h264enc` 30 frames, decode back, eyeball +
  PSNR. Gate: GNOME screen recording works.
- **VP4 — hardening + bank.** Add 0157-0160/0246-0250 (one bundle, they
  are driver-internal), soak with seek/stop/start loops (their q90l EOS
  fix is the known seek bug — adopt when we refresh to a q90-era base or
  cherry-pick early if ffmpeg seeks misbehave). Record firmware hash in
  firmware-manifest.md's shipped table (move it out of "remoteproc" into
  its own VPU entry with the sha — it is currently listed hash-less).
- **VP5 (optional, later)** — VA-API for Chromium: package iris-vaapi the
  way `FED/iceland-mainline/packaging/iris-vaapi/README.md` documents
  (driver name, env.d, dma_heap rule, decode_order_output). Ubuntu's
  chromium is a snap — defer until the desktop phase decides the browser
  story.

### 1.6 Risks

- **TZ/PAS auth of the video MDT under our boot chain** — low: same blob,
  same name, same partition lineage as Fedora's working setup; our ADSP/
  CDSP already authenticate the same way. If auth fails, the error is
  explicit in dmesg (`PAS auth failed`) — stop and compare secure-world
  state, don't iterate blind. **[I, low]**
- **SMMU faults at first start** (iommus 0x1940): our apps-SMMU handoff
  quirks (splash-window faults, SID 0x800 cosmetics) are display-side;
  iris attaches late and cleanly on Fedora's identical SoC. Watch for
  `arm-smmu … SID 0x19xx` lines at VP1; any hit = stop, it would be new
  information about our SMMU state, not an iris bug. **[I]**
- **videocc sync_state / unused-GDSC sweep**: on release boots nothing
  references videocc until iris loads; genpd may park MVS GDSCs off —
  that is the designed state, iris powers them on demand. Only the diag
  cmdline would mask a real ordering bug; hence release-config flights.
- 0292 colorimetry is **not upstreamable as-is** (their owner's note) —
  carry it last, drop it the moment colours look right without it under
  Ubuntu's GStreamer (Fedora needed it for SD BT.601).

### 1.7 Open questions

1. Does Ubuntu 26.04's GStreamer pick the stateful V4L2 decoders by rank
   without a tweak (Fedora needed only their normal packages)? Decide at
   VP2; a `GST_PLUGIN_FEATURE_RANK` override is the known lever.
2. Adopt the q90 iris set wholesale at the next queue refresh, or only
   the five fixes listed? Default: wholesale at refresh — they are all
   iris-internal and their tablet soaks them daily.

---

## 2. Haptics — close as not-fitted

### 2.1 Evidence (triple-sourced, two of them ours)

1. **Stock DT, our own capture**: the iceland DTBO describes the PMIH010x
   HV-haptics block and **disables it** —
   `dtb-work/dtbo_dtbs/00.dts:1556-1577`: `qcom,hv-haptics@f000 {
   compatible = "qcom,hv-haptics"; … status = "disabled"; }` (full
   effect library present but the node off — OPLUS shares one PMIC
   overlay across boards and gates per device). **[V]**
2. **Fedora measured on the device**:
   `FED/iceland-mainline/docs/reference/pad4-hardware-boot-partitions.md:395`
   — "**Vibrator**: none fitted (stock has none; `qcom_hv_haptics` loads
   unbound) [measured]"; 02-HARDWARE.md:100 lists haptics under
   "**absent**"; FEATURES data ships "Haptics, modem, NFC, fingerprint —
   Not on this tablet". Their kernel config keeps
   `CONFIG_INPUT_QCOM_SPMI_HAPTICS` **off** even though the infiniti
   series carries the driver (patches 0012/0068, Fenglin Wu
   @oss.qualcomm.com — needed for the OnePlus 15 phone, not this board).
   **[V]**
3. **phonewave**: `devices/iceland/device.toml:16` — "No haptics actuator
   is described in the device tree yet." (They never found one either.)
   **[V]**

Our side today: `CONFIG_INPUT_QCOM_SPMI_HAPTICS is not set`,
`CONFIG_INPUT_PM8XXX_VIBRATOR=m` (legacy, binds nothing here),
no haptics node in our DTS. **[V .config, DTS grep]**

### 2.2 Plan

**Nothing to build.** Do not add a DT node; do not enable the SPMI
haptics driver. One bookkeeping action when hardware-status.md is next
edited: Vibration row ❓ → "none fitted — stock DT disables
qcom,hv-haptics; confirmed by Fedora's on-device measurement". GNOME on a
motor-less tablet simply never fires feedback; no quirk needed.

Residual 1-command curiosity (free during any later ssh session, no
flight): confirm no `input` device with FF capability exists and that
nothing logs about haptics. Expected: silence.

---

## 3. GNSS / location — close as no-receiver; optional Wi-Fi geolocation

### 3.1 Evidence

- **SoC**: SM8850**P** — the modem-less bin; every port drops the modem
  node (perpetua `00c29a6471e7` "Drop the modem node"; Fedora PORT-LOG
  follow-up "Drop the modem remoteproc — SM8850P has no modem"). Qualcomm
  SoC GNSS engines live in the modem subsystem; no MPSS, no SoC GNSS.
  **[V commits; I architecture]**
- **Stock vendor image (our unit)**: `etc/vintf/manifest/` contains **no
  `android.hardware.gnss` HAL fragment** (full listing checked; a
  content grep for "gnss" across `etc/vintf/` matches nothing). There is
  no `/vendor/etc/gps.conf` or `izat.conf`. The generic QC location
  pieces that do exist are gated off: `etc/init/lowi-server.rc` carries
  OPLUS's "`#ifdef OPLUS_FEATURE_GPS` … add for diable automatic process
  start → `disabled`" (lowi = Wi-Fi scan positioning helper), and
  `bin/edgnss-daemon` / `libloc_*.so` are the stock location-framework
  libraries that idle without a GNSS HAL. **A stock Android with no GNSS
  HAL has no GNSS fix capability, full stop.** **[V]**
- **Downstream DT**: zero `gnss`/`gps` nodes in the decoded iceland DTBO
  and vendor_boot DTBs. The `wcn786x`/cnss nodes describe Wi-Fi + BT
  only (wifi-plan §1.3 table). **[V]**
- **Fedora survey**: `pad4-hardware-boot-partitions.md:40` — "WCN7860
  hw2.0 'peach': Wi-Fi 7 on PCIe0 (ath12k), BT on GENI UART; **no
  modem/GNSS/NFC** [measured]"; 02-HARDWARE.md:58 "Modem / GNSS —
  **absent** on SM8850P". Their 110-feature list has no location feature
  at all, and their packaging presets **ModemManager off**
  (features-data.py, iceland-device 0.28-9). **[V]**
- Mainline context (for the record): `drivers/gnss/` only serves
  serial/USB receivers (SiRF/u-blox/MTK); Qualcomm SoC GNSS on mainline
  phones is done in userspace over QRTR/QMI_LOC against the **modem** DSP
  (ModemManager ≥1.18 + geoclue) — a path that requires hardware this
  board does not have. Our config has `CONFIG_GNSS=m` with every receiver
  driver off; leave it. **[V config; I ecosystem]**

The brief's premise ("the WCN7860 combo chip also carries GNSS") is
therefore **overturned for this board**: whether or not the WCN786x die
family has GNSS blocks, iceland ships no GNSS firmware, no HAL, no DT
description, no antenna provisioning we can see, and no port has found
any. There is no enablement path and nothing to debug against.

### 3.2 Plan (userspace only, optional, XS)

- **GN0 — paper closure.** hardware-status note (when next edited): GNSS
  → "no receiver on this board (SM8850P, no modem; no GNSS HAL in stock
  vendor; Fedora measured absent)".
- **GN1 — Wi-Fi geolocation for GNOME (optional, zero kernel).** Install/
  confirm `geoclue-2.0` with its Wi-Fi source pointed at beaconDB
  (`wifi-url=https://api.beacondb.net/v2/geolocate` in
  `/etc/geoclue/geoclue.conf` — Ubuntu 26.04's geoclue defaults still
  point at the retired MLS endpoint unless the archive has moved; verify
  at install time). Gate: GNOME Maps/Weather get a city-block-level fix
  with Wi-Fi up. Privacy note for the runbook: this sends AP BSSIDs to
  the configured service; document the off switch. **[I — endpoint to be
  verified when the rung runs]**
- Residual curiosity (free, later): `qrtr-lookup` on the tablet should
  show no LOC service (QMI service 16) on any node — one command over
  ssh, confirms the ADSP firmware carries no location PD either.

No ranked risks; there is no hardware to break.

---

## 4. Suspend (s2idle) — scoping for the C6 campaign

Deliberately still untested on our side. This section is the charter:
what Fedora proved reachable, the exact deltas between their tree and
ours, and the first flights. It stays a **scoping** document — C6 runs it.

### 4.1 What the same tablet demonstrably reaches (Fedora, FEATURES.md:128-140)

- s2idle is their **default sleep** (device pkg 0.28-29
  `mem_sleep_default=s2idle` on every boot entry; since q90p also a
  Kconfig default via their own `PM: suspend: add a build-time
  suspend-to-idle default` → `CONFIG_PM_SLEEP_DEFAULT_S2IDLE=y`, mzak,
  `FETCH_HEAD:patches/0017-q90p/0004`). systemd side:
  `sleep-iceland.conf: MemorySleepMode=s2idle` with the comment "SM8850P
  supports suspend-to-idle only (PSCI OS-initiated idle down to AOSS
  sleep)". **[V]**
- Overnight: 8 h 34 min asleep at ≈0.22 W ≈ **0.35 %/h**; "SoC reaches CX
  and DDR collapse 95-98 % of the time" (measured via qcom_stats — we
  already build `CONFIG_QCOM_STATS=m`). Display wake 16/16; Wi-Fi powers
  off in sleep, back ~2 s after wake; wakes by power key, RTC alarm, lid,
  pogo keyboard, charger plug/unplug. On-charger the battery guard keeps
  it awake by design. **[V]**
- Ceiling: the deepest state (AOSS sleep) is **out of reach even on
  stock** — the SPSS secure processor is offline on this product
  (02-HARDWARE.md:57). CX+DDR collapse is the realistic target; do not
  chase AOSS. **[V]**

### 4.2 Their fix inventory vs our tree (the adoption checklist)

DT bugs we demonstrably share (both one-liners, both verified in our DTS):

1. **PCIe0 WAKE# polarity** — ours:
   `kaanapali-oneplus-iceland.dts:1153 wake-gpios = <&tlmm 104
   GPIO_ACTIVE_HIGH>` **[V]**. Their `0002-iceland/0040`: active-low
   (open-drain, pulled up) — with ACTIVE_HIGH "every suspend with Wi-Fi
   enabled returned within a second, pm_wakeup_irq = 0000:00:00.0:wakeup".
   This is the fix wifi-plan §6 already queued for "phase C+1"; it is the
   first patch of C6.
2. **Default wakeup sources that must not wake a tablet** — their
   `0002-iceland/0301`: the dtsi USB controller `wakeup-source`
   (ours: kaanapali.dtsi:4813) made any attached USB2 hub abort s2idle
   instantly in host mode, and the WCN7860 root port's WAKE# GPIO is a
   wakeup source with no Wake-on-WLAN configured. They strip both in DT
   (previously a udev rule). Note the interaction with our USB **gadget**
   use-case in §4.4 before copying 0301 verbatim.

Kernel patches, by block (all paths `FED/iceland-linux/patches/…`,
FETCH_HEAD for q90 series):

- **PCIe/Wi-Fi**: `0002-iceland/0113` "PCI: qcom: Do not advertise a
  hot-plug slot without a hot-plug driver" — without it the root port
  refuses D3, "kept a DDR [vote]" and the link+clocks up through suspend.
  `0260` ath12k "don't wake the device over MHI from the …". Expected
  residual (their words, 02-HARDWARE.md:59): "**Timeout waiting for L2
  entry** at every suspend — without WoWLAN ath12k's suspend resets the
  WLAN SoC, which never answers PME_Turn_Off; the controller logs the
  timeout and continues, and ath12k reloads firmware on resume." I.e. the
  scary line is benign and Wi-Fi-across-sleep = full fw reload (~2 s).
  Stock keeps WLAN fw alive instead; WoWLAN is nobody's rung yet. **[V]**
- **DSP/remoteproc**: `0002-iceland/0352` (FETCH_HEAD) "soc: qcom: notify
  the DSPs before system sleep" — ports the downstream
  `qcom,smp2p-sleepstate` notifier (clears the AP-awake SMP2P bit on
  PM_SUSPEND_PREPARE, keeps the inbound IRQ as a wake source; protocol
  from MiCode, CONFIG_QCOM_SMP2P_SLEEPSTATE). Our tree has **neither the
  driver nor the DT node** (grep empty) **[V]** — and our ADSP hosts
  battery + (future) sensors. Companions: `0348` fastrpc freeze waiters,
  `0389/0390` remoteproc attach robustness, `0176` "qcom_battmgr: OPLUS —
  the host can suspend" (SOCCP/pmic_glink side), ucsi_glink quiet across
  sleep (q90q FROMLIST + q90s) and `0233/0234` ucsi resume retries.
- **UFS**: our DT runs **legacy single-queue** (no `msi-parent` on
  ufshc@…, no MCQ — kaanapali.dtsi:2626 area **[V]**), so the MCQ-specific
  suspend hazard does not bite until we adopt their `0171` (MCQ enable,
  9 queues, 2.3 GB/s). When we do, the known-queued fix the brief asked
  about is `FETCH_HEAD:patches/0015-q90n/0002-scsi-ufs-qcom-Reprogram-ESI-
  after-a-host-controller-reset.patch` (Joonhoe Kim, `Fixes: 519b6274a777`
  — after an error-handler reset, completions silently fall back to the
  legacy IRQ while `mcq_esi_enabled` stays set; check its landing on
  linux-scsi at adoption, the area was churning upstream through Oct 2026
  with the related MSI-descriptor rework and an SM8750 ESI null-deref
  fix). Also in their queue: q90b `0018-0024` UFS core race fixes, q90r
  `0012/0013` link-recovery + `is_sys_suspended` (Samsung, double
  link-recovery during resume), q90t timeout/rpm-error propagation.
  **[V queue; I upstream status]**
- **cpuidle/genpd**: their base splits CPU PM domains
  (cluster0/cluster1/system) with psci patches 0195-0199, 0237/0238
  ("do not return a disabled idle state", menu+teo), 0277/0278
  (`allow_cluster_off`/`allow_system_off`); ours is the single-cluster_pd
  dtsi (kaanapali.dtsi:266-346) **[V]**. Their CX/DDR-collapse numbers
  were achieved on the split+fixes stack; parity here is likely required
  for the drain target, not for "suspend works at all". TEO governor:
  theirs built (`CONFIG_CPU_IDLE_GOV_TEO=y`) and default since q90p; ours
  not built **[V]** — cheap config add when C6 starts.
- **Display/GPU/misc across sleep** (adopt on symptom, not up front):
  qmp-combo/qmp-usb PM callbacks (q90q 0002/0003), geni UART "clear
  pending IRQs while suspended" (q90d 0002), `0243` geni PM-domain-list
  double free, `0187` codec resume in plug detect, dwc3 latency-vote pair
  `0063/0065` (we may already want these for USB stability independent of
  sleep), `0276` eUSB2 wake-line arming for host mode, q90w2 `0001`
  `snps,resume-hs-terminations` DT.

Userspace ordering lesson (their hardest-won): sensors must stop
**before** the sleep transaction reaches the DSP file server —
`iio-sensor-proxy-iceland-sleep.conf` + hexagonrpcd
`Conflicts=suspend.target` (iceland-device 0.28-21…-26). Our sensors
aren't up yet; inherit the pattern when they are. GNOME policy: suspend
6 min after last input on battery (0.28-27), power key = sleep on
battery / blank on charger. **[V]**

### 4.3 Gap summary

Suspend on our tree today would fail or regress in these known ways, in
order: instant wake from WAKE# polarity (certain, dts:1153) → USB/PCIe
wakeup-source aborts (certain in host mode / likely) → PCIe port held in
D0 keeping a DDR vote (0113) → ADSP never told about sleep
(sleepstate — consequences range from none to fatal-on-resume; Fedora saw
an ADSP fatal in a related gap on another device) → cosmetic L2-entry
timeout (keep) → drain above target until cpuidle-domain parity. Display
wake robustness rides on the C1/display parity cluster already tracked in
fedora-parity-audit §7.4 (INT2 GDSC, splash keep, etc.) — C6 should start
only after that cluster lands, which bringup-plan already sequences
(C5 → C6).

### 4.4 Our two gadget-specific open questions (the brief's)

- **USB gadget console across s2idle**: no reference stack answers this —
  Fedora/phonewave don't use a gadget console. Expect the ACM/ECM session
  to drop at suspend entry (dwc3 device-mode suspend) and re-enumerate on
  resume; our T+60 USB-bounce hardening and the "access script recreates
  the gadget" lore are the recovery pattern. The flight plan treats the
  gadget as a **canary, not the lifeline**: every suspend flight runs
  with Wi-Fi ssh as primary access + serial ACM logging with timestamps,
  and scores the gadget's behaviour (survives / re-enumerates / needs
  bounce) as data. If 0301 is adopted verbatim (USB wakeup-source
  removed), confirm charger-plug wake still comes via pmic_glink (it
  does on Fedora — "wake by charger" is PMIC-side) and that losing
  USB-wake doesn't strand a gadget-only bench setup.
- **Wi-Fi across s2idle**: answered by Fedora — powered off at suspend,
  full firmware reload on resume, ~2 s to reassociation, L2-timeout line
  benign. Adopt the same expectation; WoWLAN is out of scope for C6.

### 4.5 First flights (C6 preamble — do not run before C5)

- **S0 — recovery story on paper + rails.** Document in the runbook:
  wake failure ⇒ hold power ≥10 s ⇒ hard reset ⇒ flashed slot-B boots
  (qbootctl re-marks; zero blacklists as of 0.2.16); if boot_b were ever
  wedged: `fastboot flash boot_b factory/fcap/part-boot_b.img` — never
  set_active. Serial survival matrix columns prepared: ACM alive during
  sleep? after wake? after bounce? **No suspend before S0 is merged.**
- **S1 — DT pair + first s2idle, RAM boot.** One bundle: 0040-equivalent
  (WAKE# ACTIVE_LOW) + 0301-equivalent (minus any hunk we need for
  gadget-wake, per §4.4). Release-config RAM boot, Wi-Fi up, GNOME not
  yet required: `rtcwake -m mem -s 60` from ssh (mem==s2idle via
  `mem_sleep_default=s2idle` on the cmdline for the flight; config
  default later). Gate: enters sleep (pm_suspend returns only at the RTC
  alarm, not instantly — check `pm_wakeup_irq` empty), resumes with
  display back, ssh back ≤ ~10 s, dmesg triaged (L2 timeout allowed).
  One variable: if it wakes instantly, the wakeup-irq line names the
  culprit — that is the matrix, not a failure.
- **S2 — sleepstate + PCIe D3 + battmgr.** Add 0352 (+DT node), 0113,
  0176 as one "remote-side quiesce" bundle (they are independent of S1's
  DT pair and of each other's subsystems, but flying them together is
  acceptable because S1 established the baseline; bisect within only on
  regression). Gate: 10× S1 loop clean; `qcom_stats` (debugfs
  `/sys/kernel/debug/qcom_stats/`) shows CX/DDR sleep counters
  **incrementing** across a 5-min sleep.
- **S3 — drain measurement.** 30-min and overnight unplugged sleeps on
  the flashed system (only after S2 is 10/10 on RAM boots). Benchmark:
  Fedora 0.35 %/h. Within 2×: ship it and iterate later; worse: the
  cpuidle-domain parity block (0195-0199/0237-0238/0277-0278 + TEO)
  becomes its own rung.
- **S4 — wake-source matrix.** Power key, RTC, charger plug, (when
  present) pogo events. Score gadget behaviour per §4.4.
- **S5 — policy.** `MemorySleepMode=s2idle` in systemd sleep.conf.d +
  GNOME timers per Fedora's values; battery-guard interaction postponed
  until our guard exists.

### 4.6 Risks

- A wedged resume on a **flashed** boot is the only scenario that
  touches persistent state, and it recovers by forced reboot (S0). RAM
  flights cannot strand us. The residual risk is time, not hardware.
- The sleepstate notifier is protocol-ported from MiCode and "still needs
  device validation" even in their tree **[V patch header]** — keep it in
  its own bundle (S2) so a resume oops bisects instantly.
- Our display stack still carries the one-shot dsi0_phy_pll WARN and
  smmu handoff cosmetics; across hundreds of suspend cycles, "one-shot"
  classes can recur. Log triage rules from the known-benign list apply.

---

## 5. Cameras — the real port

### 5.1 Hardware truth (stock capture + Fedora survey, they agree)

| Piece | Fact | Source |
|---|---|---|
| Rear | SmartSens **SC1320CS**, 13 MP, 4-lane D-PHY on **CSIPHY4**, link 662.4 MHz, chip-id 0xc658, i2c addr **0x36** | FED 0073 patch (+ their r/e); dtbo fixups fragment@97 **[V]** |
| Front | SmartSens **SC820CS**, 8 MP, 4-lane D-PHY on **CSIPHY5**, link 330 MHz, chip-id 0xd154, addr **0x10** | same **[V]** |
| AF | DW9800K-register-map VCM @ **0x0c** (stock "icelandmain_actuator"), vaf = L16B | same **[V]** |
| EEPROMs | rear+front cam EEPROMs (at24-class) on the same bus | dtbo `qcom,eeprom0/1`; FED 0129-0131 **[V]** |
| Bus | **GENI i2c9** (not CCI!) @ 400 kHz | FED 0073 `&i2c9` **[V]** |
| MCLKs | **RPMH DIV_CLK1** routed out of **PMK8850 GPIOs 1/2 (func2)** — PMIC-pad clocks, not TLMM cam_mclk | FED 0073 `&pmk8850_gpios` **[V]** |
| Resets | PMH0110_**G** GPIOs 13 (front) / 14 (rear), active-low; stock asks power-source 2 on LV_VIN2 pads which cannot be set — source 0 as booted is correct | FED 0073 comment **[V]** |
| Rails | dovdd **L2F** 1.8 (shared I2C pull-ups!), dvdd L1F 1.2, avdd L14B 2.8, vaf L16B 2.8; CSIPHY4 vdda = L3D/L1D, CSIPHY5 = L3I/L1D | FED 0073; matches dtbo `__fixups__` L14B/L16B/L1F/L2F exactly **[V]** |
| Flash | PMH0101 flash LED, two dies (torch works on Fedora) | FED 0031 "enable the rear flash LED"; survey :39 **[V]** |

The "OEM change for Camera" comments in our board DTS (:564, :585, :718)
mark exactly these rails (L14B/L16B/L2F) — map220v kept the regulators,
never the consumers. **[V]**

### 5.2 What Fedora runs (file-level) and what it achieves

Kernel:
- Sensor driver: `0002-iceland/0175` — **new** `media: i2c: sc1320cs`
  driver covering both SC1320CS and SC820CS (`CONFIG_VIDEO_SC1320CS=m`),
  mzak-authored, **not upstream anywhere**; `0299` powers the lens-focus
  actuator only while the rear sensor streams (shared-rail choreography).
- Board DT: `0073` (the 197-line hunk summarized above; VCM initially
  `status = "disabled"` because it cannot probe before a sensor powers
  the shared pull-up rail), then `0191` (rotation: the 90/270 values from
  Android's portrait baseline re-expressed as **0/0** for our landscape
  panel — adopt the final values, the commit text is the proof), `0300`
  (`dongwoon,default-position = <450>`, stock's start DAC — "sharp from
  arm's length to across a table"), `0131` (EEPROM nodes), `0031` (flash
  LED enable).
- VCM driver: dw9719 family. Their fix chain `0087/0088` (I/O supply),
  `0296/0298/0306` (reach/hold position on resume and while streaming),
  q90 `0392` (configure the DW9800K only once it responds). Upstream's
  own "DW9800K update" was **rejected by their testing** (chip-ID 0xfe
  mismatch — MAINLINE-STATE "held" list); our tree's dw9719 already has
  the `dongwoon,dw9800k` compatible (`dw9719.c:478,487` **[V]**) but is a
  different revision — verify which init sequence ours implements at
  CAM3.
- camss: platform support is the same Qualcomm "Add Kaanapali support"
  lineage both trees carry (see §5.3); their iceland-side fixes:
  `0128` (quiet deferred CSIPHY lookup), `0181` (TPG media-entity
  function), `0263` (hold the bandwidth vote while TITAN_TOP …) — to be
  reconciled with our `26d70b82c3ae` "camss: drop interconnect votes with
  TITAN_TOP" which attacks the same vote lifetime from the other side
  **[V both; I same-intent]**; q90z `0011` "keep L2F on (the camera I2C
  pull-up supply)" — the shared-rail gotcha again, this time against
  regulator auto-disable.
- Config: `CONFIG_VIDEO_SC1320CS=m`, `CONFIG_EEPROM_AT24=m`, and the F02
  lesson: **`CONFIG_DMABUF_HEAPS_CMA` turned OFF** — "CMA dma-heap too
  small for full-size soft-ISP buffers … libcamera then uses the system
  heap" (distro-neutral.config comment). Ours currently has it **on**
  (=y) with `CMA_SIZE_MBYTES=32` **[V]**; their q90z also raised CMA to
  128 MB for other consumers (and SWIOTLB dynamic 2 MB) — not a camera
  requirement once the CMA heap is off.

Userspace: libcamera **simple pipeline + soft ISP** (no Qualcomm ISP/PIX
path), Fedora's stock libcamera 0.7.1-2 (the 0.7.1-2 IPA-signing fix
matters: the soft IPA runs in-process; with 0.7.1-1 they saw a 1-in-40
WirePlumber stop race). Tuning only via the simple-IPA YAML (black level,
colour). Achieved (FEATURES:149-150, features-data r158): both cameras in
GNOME Snapshot, 40/40 open/close cycles clean, orientation correct, rear
lens held at 450 while streaming and unpowered 2.5 s after; **no
autofocus** (upstream simple pipeline has none). Open on their side:
camera→HW-encoder pipeline doesn't negotiate. **[V]**

### 5.3 camss platform state (ours vs theirs vs upstream)

- Upstream: "media: qcom: camss: Add Kaanapali support" is a
  Qualcomm-authored series at **v15 (Jul 2026), RDI-only**, csid/vfe
  files renamed with a `-gen4` suffix at v14; **not merged** as of
  next-20261020 (Fedora still carries it: FETCH_HEAD
  `0001-infiniti/0047-0054`). **[V queue; web: lkml v15 cover]**
- Ours (perpetua) already carries an earlier revision of the same work
  **plus** the nx809j extensions: `camss.c` has
  `csiphy_res_kaanapali/csid_res_kaanapali/vfe_res_kaanapali/icc_res_kaanapali`
  (:45/:90/:166/:309), files named `camss-csid-1080.c`/`camss-vfe-1080.c`
  (pre-rename revision), CSIPHY v2.4.0 two-phase, TPG v2.4.0,
  data-lanes-start-at-1, PHY-API devices, C-PHY link passing, plus the
  sensor set for nx809j (ov50e40/ov02f10/ov16a1q/ov50d40/imx890/s5k3p9,
  dw9785). The dtsi has the full `camss: isp@9253000`
  (`qcom,kaanapali-camss`, :3808) with csiphy0-5 ports and cci0-2 nodes.
  `CONFIG_VIDEO_QCOM_CAMSS=m`, `CLK_KAANAPALI_CAMCC=y`,
  `RPMH_DIV_CLK1` present in our clk-rpmh kaanapali table (:915). **[V]**
- Net: the SoC layer is in both trees (different revisions of one
  series); **iceland needs only the leaf layer** — sensor driver, board
  DT, VCM/EEPROM/flash — all of which exist as Fedora patches against a
  near-identical base. iceland uses no CCI and no C-PHY, i.e. the
  simpler half of the infrastructure.

### 5.4 Gap analysis

| Piece | Ours | Action |
|---|---|---|
| camss kaanapali SoC support | present (older rev) | none now; reconcile rev drift at next rebase |
| SmartSens SC1320CS/SC820CS driver | absent | port FED 0175 + 0299 |
| Board DT (camss/csiphy/i2c9/sensors/VCM/pinctrl) | absent | port FED 0073 with 0191's final rotations + 0300 + 0131 |
| dw9719/dw9800k VCM | driver present, rev differs | enable `CONFIG_VIDEO_DW9719=m` (currently off **[V]**); diff init vs their 0392/0298/0306 at CAM3 |
| EEPROM | `CONFIG_EEPROM_AT24` off? (=m per their config; ours unset — matched `EEPROM_AT24` not in our grep → check at CAM0) | set =m; optional for streaming |
| Flash LED | dtsi/driver TBD (leds-qcom-flash class) | port FED 0031 when sensors stream |
| Heap config | `DMABUF_HEAPS_CMA=y` (ours) | flip off per F02, libcamera → system heap |
| camss fixes | 0128/0181 absent; vote-lifetime fix differs | carry 0128/0181; reconcile 0263 vs `26d70b82c3ae` |
| libcamera | Ubuntu 26.04 version unknown vs their 0.7.1-2 | check soft-ISP/IPA state at CAM4; may need their packaging deltas (`FED/iceland-mainline/packaging/libcamera/`) |

### 5.5 Ladder

- **CAM0 — config + driver port, no DT.** Port 0175 (+0299) as our
  `kernel/patches/00xx`; `VIDEO_SC1320CS=m`, `VIDEO_DW9719=m`,
  `EEPROM_AT24=m`, `DMABUF_HEAPS_CMA` off. Gate: build; modinfo shows
  both compatibles.
- **CAM1 — board DT, sensors only.** Port 0073 with: VCM left
  `disabled` (their own first-light shape), rotations from 0191 (0/0),
  no flash yet. Release-config RAM boot + modules staged. Gate: i2c9
  probes; both sensors **identify** (dmesg chip-id 0xc658 / 0xd154 —
  their driver logs it); camss V4L2 async notifier completes;
  `media-ctl -p` shows the full graph (csiphy4/5 → csid → vfe RDI).
  Watch: the first PMK8850-gpio func2 MCLK activation and PMH0110_G
  resets are SPMI writes of the same class the WLAN saga taught us to
  respect — they are **Fedora-proven safe on this firmware**, but the
  flight log keeps the serial tail anyway.
- **CAM2 — first frames.** `libcamera` CLI: `cam -c1 --capture=5
  --file`; then `qcam`. Gate: non-black DNG/raw frames from both
  sensors; exposure reacts. (If Ubuntu's libcamera lacks the soft-ISP
  fixes, build their 0.7.1-2-equivalent from
  `FED/iceland-mainline/packaging/libcamera/` as a local deb — decide
  here.)
- **CAM3 — focus.** Enable the VCM node + 0300 default-position; port
  their hold/resume fixes if our dw9719 rev lacks them. Gate: K7-style —
  450 held during a 60-frame stream, actuator unpowered ~2.5 s after
  stop, no i2c errors from the shared rail (L2F stays up — adopt q90z
  0011 if the regulator drops).
- **CAM4 — desktop.** GNOME Snapshot (or `gnome-camera`) with
  WirePlumber; 40× open/close soak. Gate: 40/40, orientation matches
  display in both rotations.
- **CAM5 — garnish.** Flash/torch (0031 port, `v4l2-ctl --set-ctrl` or
  GNOME torch tile), EEPROM nodes (0131), simple-IPA YAML tuning pass
  only if colours are visibly off.

### 5.6 Risks

- **The sensor driver is single-source** (one author, one board, not
  upstream): any iceland-vs-theirs silicon/wiring delta debugs against
  us alone. Mitigation: the chip-id gate at CAM1 and their exhaustive
  r158 test records.
- **Shared-rail choreography** (L2F pull-ups feed sensors + VCM + EEPROM):
  three of their late fixes (0299, q90z 0011, 0073's disabled-VCM dance)
  exist because of it; expect this to be where our first odd failure
  lives.
- **camss revision drift** between perpetua's `-1080` files and the v14+
  `-gen4` rename: their iceland camss fixes may need mechanical rebasing;
  at the next upstream rebase prefer whichever revision merged.
- **libcamera soft ISP on Ubuntu 26.04** is the biggest unknown
  (Fedora needed a specific 0.7.1-2 IPA fix); budget a packaging rung.
- Power: streaming cameras keep i2c9/CSIPHY/VFE votes — irrelevant until
  C6; the "actuator powered only while streaming" behaviour is already
  the right default.

### 5.7 Open questions

1. Ubuntu 26.04's libcamera version + whether its simple pipeline ships
   the soft IPA in-process fix (CAM2 decides build-vs-package).
2. Our dw9719 revision vs their 0392/0298/0306 behaviour set — diff at
   CAM3, port the delta if the lens drifts or probe is flaky.
3. Do we want the EEPROM contents (PDAF/calibration) at all while the
   pipeline is soft-ISP? Default no until a tuning pass wants lens
   shading.

---

## Appendix A — handy numbers and names

- iris: node `video-codec@2000000`, compat `qcom,kaanapali-iris`, fw
  (ours, stock name) `qcom/kaanapali/iceland/vpu40_2v.mbn`
  sha256 `69d4e215…a411abc` 2486984 B; platform fwname upstream-to-be
  `qcom/vpu/vpu40_p2.mbn`; VA-API extra: `qcom_iris.decode_order_output=1`.
- Cameras: rear SC1320CS i2c9@0x36 id 0xc658 CSIPHY4 662.4 MHz; front
  SC820CS i2c9@0x10 id 0xd154 CSIPHY5 330 MHz; VCM dw9800k@0x0c,
  default DAC 450; MCLK = RPMH_DIV_CLK1 via pmk8850 gpio2 (rear) / gpio1
  (front) func2; resets pmh0110_g gpio14 (rear) / gpio13 (front)
  active-low; rails L2F/L1F/L14B/L16B; rotations 0/0 (landscape).
- Suspend: `mem_sleep_default=s2idle`; wake bug dts:1153 ACTIVE_HIGH→LOW;
  qcom_stats debugfs for CX/DDR counters; Fedora benchmarks 0.35 %/h,
  resume-to-ssh ~2 s Wi-Fi reload; L2-entry timeout = benign signature.
- Haptics: dtbo `qcom,hv-haptics@f000` `status="disabled"` (00.dts:1556);
  keep `CONFIG_INPUT_QCOM_SPMI_HAPTICS` off.
- GNSS: no `android.hardware.gnss` in vendor VINTF; `lowi-server.rc`
  disabled by `OPLUS_FEATURE_GPS` ifdef; geoclue endpoint to verify at
  GN1 (beaconDB).
- Fedora queue coordinates: main=q89g (`7.3.0-rc7-iceland-00426`);
  `iceland-7.3-rc7-next` FETCH_HEAD `1006a29d2170` = q90z
  (`7.3.0-next-20261020-iceland-00572`), kernel.pin documents every
  intermediate tree hash.

## Appendix B — what this research closes or corrects

- hardware-status.md (when next edited, not in this change): Cameras row
  → "sensor driver + DT exist in Fedora port, camss already in our tree";
  Suspend row → replace "works per Nura wiki" with §4's evidence;
  Vibration row → "none fitted"; add GNSS row → "no receiver".
- The brief's "WCN7860 also carries GNSS" assumption — overturned (§3.1).
- The "camera-adjacent nx809j commits may be reusable" hunch — confirmed
  and sharpened: the SoC layer is already ours; only leaf drivers + DT
  are missing (§5.3).
- wifi-plan §6's "apply 0040 before s2idle testing" — folded in as S1.
