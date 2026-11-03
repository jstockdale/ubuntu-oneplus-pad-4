# Sensors/IMU bring-up plan (C4/C5 feeder): the sensor hub route to GNOME auto-rotation

> **Corrections from the 2026-11-02 readiness review** (checked against the
> pinned tree, the live tablet, the Debian/Ubuntu archives and the Fedora
> port's current tree, now cloned under /srv/ubuntu-iceland/ref/):
> - Patch numbering is stale: the series is 0001–0028 plus the VPU set
>   0029–0036; the non-secure-domain DT fix (G1) and the hall node (G8)
>   take the next free numbers after that.
> - S0/S2 baseline is wrong: `qrtr-lookup` on the flashed system ALREADY
>   lists QMI service 400 "Snapdragon Sensor Core service" (node 5) with no
>   hexagonrpcd ever run, so "SSC absent until attached" is false and
>   "qrtr-lookup now lists SSC" cannot be the S2 pass signal; use
>   hexagonrpcd's file-request stream and, in S4, `ssccli` output.
> - S0 step 3 cannot harvest socinfo from the tablet: mainline
>   /sys/devices/soc0 has only family, machine, revision, serial_number,
>   soc_id (661, 2.0). hw_platform/platform_subtype/platform_subtype_id/
>   platform_version come from Fedora's generic socinfo set (hw_platform =
>   "MTP"; three values still to fetch).
> - Archive facts: Debian sid libssc is 0.4.4-2 (binaries libssc2,
>   libssc-bin, libssc-dev); hexagonrpc is 0.4.0-2 in sid and 0.5.0-1 in
>   experimental (rebase G3 on the 0.5.0-1 packaging, not Ubuntu's 0.4.0
>   source); iio-sensor-proxy 3.9-1 confirmed. Ubuntu 26.04 ships none of
>   the needed pieces (iio-sensor-proxy 3.8-1 without SSC; libssc absent).
> - The archive hexagonrpcd 0.4.0 ships hexagonrpcd.service (+ -suspend/
>   -resume), not hexagonrpcd-adsp-sensorspd.service; the plan's unit names
>   hold only for the 0.5.0-based package we build.
> - G9 "0170+0194 as one no-map patch" is contradicted by the porting log
>   (0194 conflicts and presupposes a linux-next fastrpc change); if a
>   remote heap is ever needed it is 0170 alone. The tablet logs "no
>   reserved DMA memory for FASTRPC" for adsp and cdsp today.
> - Fedora's packaging README now says hexagonrpcd runs as root and the hub
>   writes below its registry directory, contradicting its User=fastrpc
>   drop-in; treat "read-only registry is the proven steady state" as
>   unverified. Their iio-sensor-proxy delta is now 0001/0002 only.
> - Secure-node attach (open question 2) is reconfirmed in code at the pin
>   (fastrpc.c is_session_rejected only rejects a non-secure fd on a secure
>   channel; INIT_ATTACH_SNS has no secure gate) but is untested on the
>   device. Perpetua's head b7d639cfb282 touches none of fastrpc.c,
>   qcom_pd_mapper.c, the adsp fastrpc node or a lid/hall node.
> - The per-unit registry (352 files) is calibration data: never in the
>   repo, never in a published overlay. Idle datum for S4: ipcc_0 ≈ 1.3
>   interrupts/s.

Written 2026-11-01 from source research only — no device contact, no tree
edits. Kernel of record: perpetua pin `7c98a10e6bb7` (pristine
`/srv/ubuntu-iceland/linux-perpetua`, worktree
`/srv/ubuntu-iceland/build/linux-src-iceland` + our patches 0001–0010; the
DTS/dtsi lines cited below are identical in both — the fastrpc/adsp region
was diffed today). Build config: `/srv/ubuntu-iceland/build/linux-iceland/.config`.

Status quo: `/sys/bus/iio` on the tablet is empty; the ADSP runs (battery
telemetry via pmic_glink battmgr), cdsp runs, soccp attached; display/GPU/
touch/WiFi/BT work. GNOME (C5) wants an iio-sensor-proxy-visible
accelerometer for rotation. This plan takes sensors from "zero devices" to
GNOME auto-rotation, one variable per flight.

Legend: **[V]** verified in a tree/image/config we hold (cited file:line);
**[S]** verified in a sibling port's tree/docs; **[I]** inferred;
**[W]** web/archive fact (packages.ubuntu.com / sources.debian.org, checked
2026-11-01).

## Safety rails (non-negotiable, inherited + sensors-specific)

- **RAM boots for every kernel change; nothing flashed for sensor testing.**
  Never `fastboot set_active`, never write vbmeta/dtbo/vendor_boot/GPT, no
  EDL (standing rails).
- **No sensor flights on diagnostic kernels.** Diag kernels build no
  modules, and this whole stack is modules (`fastrpc.ko`, `qrtr*.ko`,
  `qcom_pd_mapper.ko` — §1.4). Sensors fly only on release-kernel RAM boots
  or the flashed system. (Also the WLAN-era rule: never test
  power-sequencing-adjacent behavior on diag cmdlines.)
- **persist and the factory capture stay read-only artifacts.** Everything
  this plan needs from `factory/fcap/part-persist.img` was read with
  `debugfs` (no mount). If a mount is ever preferred: read-only loop in a
  scratch dir (`mount -o ro,loop`), never the tablet's live persist
  partition, never a write anywhere into `fcap/`.
- **The ADSP is shared infrastructure.** battmgr (working battery UI) and
  the C4 audio plan live on the same remoteproc. A sensors-PD experiment
  that triggers an ADSP SSR takes both down until restart. Watch
  `dmesg -w` for `remoteproc` fatal lines in every flight; one SSR = stop
  and analyze, don't iterate.
- **Never poke the sensor GPIOs from userspace** (TLMM 81 IMU IRQ, 98 hall,
  201 ALS IRQ — §1.1): the hub firmware owns them. And never dump
  whole-TLMM pinctrl/gpio debugfs (XPU read-reset hazard, standing rail).
- **One variable per flight. One serial listener.** Kernel patches land in
  `kernel/patches/` only when they ship (0011+); flight-only patches never
  stay behind (wifi-plan §4.0 precedent).

---

## 1. Findings

### 1.1 Sensor inventory (the real chips, with evidence)

The live sensor list of our unit, from persist (written by the hub on
2026-10-30, read via debugfs from `factory/fcap/part-persist.img`,
`/sensors/sensors_list.txt`) **[V]**: accel, gyro, mag, rgb, proximity,
ambient_light, hall, plus hub-virtual sensors (gyro_cal, mag_cal, gravity,
rotv, game_rv, geomag_rv, device_orient, pedometer, oplus_* …).

The chips, from the per-unit sensor registry in persist
(`/sensors/registry/registry`, **352 files** — same count as the registry
Fedora publishes) cross-checked against the ODM partition's sensor configs
(stock `odm.img` EROFS, `/etc/sensor/config/`, 11 JSONs + `json_list`,
extracted to scratchpad with `fsck.erofs --nid`) **[V]**:

| Function | Chip | Bus as the hub sees it (ODM registry JSON) | Rails | IRQ pin | Per-unit cal in persist |
|---|---|---|---|---|---|
| Accel + gyro (+IMU temp, motion detect) | Bosch **BMI3x0** (`bmi3x0_0`; BMI320/BMI323 family) | **SPI**, hub `bus_instance 3`, ≤6 MHz, CS 0 (`kaanapali_mtp_bmi3x0_0.json`: bus_type 1, max_bus_speed_khz 6000) | vdd L1B, vddio L18B | 81 (DRI for accel/gyro/md) | `bmi3x0_0_platform.{accel,gyro}.fac_cal.{bias,corr_mat}`, `temp.fac_cal`, `bmi3x0_0_crt_state.crt_{gain,offset}` |
| Magnetometer | AKM **AK09919** (`ak0991x_0`) | **I2C**, hub `bus_instance 1`, addr 0x0E @400 kHz (I3C addr 0x1E configured) | vddio L1B | polled (`is_dri 0`) | `ak0991x_0_platform.mag.fac_cal{,_2}.{bias,corr_mat}`, `.orient`, `.placement` |
| ALS + proximity + CCT/RGB | Sensortek **STK36C01** (`alsps_hw_stk36c01`) | **I2C**, hub `bus_instance 2`, addr 0x48 @400 kHz | vdd L2B, vddio L1B | 201 | `alsps_platform.{als,prox,cct}.fac_cal`, `alsps_hw_stk36c01.dynamic_cali.*` |
| Hall (folio/keyboard cover) | Rohm **BU52053NVX** (`bu52053nvx_0`) | GPIO only, no bus | vddio L1B | **98** (= TLMM 98, also AP-readable — §1.6) | config only |
| Rear flicker/RGB | behind the camera AON path (`devinfo.rgb_rear` → `flicker_platform.ch_scale.fac_cal`) | — | — | — | out of desktop scope |
| SAR | **not fitted**: the generic vendor config carries `kaanapali_sx932x_0.json`, but iceland's ODM `json_list` has no SAR entry and persist has only `default_sensors.sar` attributes | — | — | — | — |

Bus-enum interpretation (bus_type 0=I2C / 1=SPI; `bus_instance` = the hub's
own serial-engine index) is **[I]**, corroborated by the speeds/addresses
(6 MHz = SPI; 0x0E is AK0991x's I2C address; 0x48 is STK3x's) and by the
`irq_is_chip_pin 1` + Fedora's confirmation that hall "IRQ 98" is main-TLMM
GPIO 98 (§1.6). Kaanapali's TLMM has 218 pins (`kaanapali.dtsi:5023`), so
81/98/201 are all TLMM numbers. The registry JSON schema is Qualcomm's SEE
(Sensor Execution Environment) registry format; `sns_reg_config` **[V]**
(`vendor-extracted/etc/sensors/sns_reg_config`) wires it together: config
input from `json.lst` + `/odm/etc/sensor/config`, output registry at
`/mnt/vendor/persist/sensors/registry/registry`.

Naming note: the ODM files are called `kaanapali_mtp_*` but are OnePlus'
own (the chips differ from Qualcomm's MTP reference set — vendor's generic
`etc/sensors/config` (95 files) describes lsm6dsv/mmc56x3x/tmd3765 MTP/QRD
boards that iceland does not use). The ODM `json_list` is the selector that
matters **[V]**.

### 1.2 Architectural verdict: everything hangs off the ADSP sensor hub (SSC)

**No motion/light sensor is on an AP-owned bus. The route is the Qualcomm
sensor stack over FastRPC + QRTR/QMI with the sensor registry — not
mainline IIO drivers.** Proof chain, all **[V]**:

1. **The DTS has no sensor on any AP bus.** Every enabled AP I2C/SPI host
   in `kaanapali-oneplus-iceland.dts` is accounted for: `&i2c0` :908 and
   `&i2c22` :945 carry the six TFA9865 speaker amps; `&i2c3` :981 the
   WCD9395 USBSS mux; `&i2c14` :1009 / `&i2c15` :1021 the KTZ8869
   backlights; `&spi19` :1278 the NT36536 touch. Zero IMU/ALS/mag nodes;
   grep for imu/accel/magn/als/sns/ssc across the DTS matches nothing else.
2. **The ADSP image is the combined ADSP+SLPI ("sensor low-power island")
   image.** The reserved region is literally named `adspslpi`:
   iceland deletes and re-places it (`/delete-node/ &adspslpi_mem` :21,
   `adspslpi_mem: adspslpi@a1400000`, 80 MiB, :223), and
   `remoteproc_adsp` (`qcom,kaanapali-adsp-pas`/`qcom,sm8550-adsp-pas`,
   `kaanapali.dtsi:3194-3222`) maps it with `q6_adsp_dtb_mem`. There is no
   separate SLPI remoteproc on this SoC generation.
3. **The DT already wires the FastRPC path to that hub**: the adsp
   glink-edge has `fastrpc { qcom,glink-channels = "fastrpcglink-apps-dsp";
   label = "adsp"; }` with compute-cb@3–7 (`kaanapali.dtsi:3243-3296`).
4. **Stock drives exactly this stack**: `vendor-extracted/etc/init/
   vendor.sensors.sscrpcd.rc` runs `sscrpcd sensorspd adsp` (the Android
   sensors-PD FastRPC file-server daemon); the sensor HAL is
   `sensors.qsh.so` behind the multihal (`etc/sensors/hals.conf`); the DSP
   partition (`stock/current/dsp.img`, ext4) carries the hub's dynamic
   modules in `/adsp`: `fastrpc_shell_0`, `libsns_*_skel.so`,
   `sns_tppe.so`.
5. **The per-unit truth lives in persist**, where only a hub writes it:
   the 352-file SEE registry incl. factory calibration (§1.1) under
   `/sensors/registry/registry`, `sns_reg_version` = `version=2`.
6. **The negative on the running tablet matches**: `/sys/bus/iio` empty
   with display/touch/WiFi all up — nothing is missing a driver; there is
   simply no AP-visible sensor hardware.

Consequence for gates: on this device **no IIO device will ever appear for
these sensors** ("iio_info lists accel_3d" is the wrong gate here). The
equivalents are `ssccli --sensor accelerometer` (libssc, QMI over QRTR) and
`monitor-sensor` (iio-sensor-proxy's SSC backend). iio-sensor-proxy speaks
to the hub directly via libssc; the udev anchor for it is the
`/dev/fastrpc-adsp` misc node, not an iio device (§1.5).

How the stack runs on mainline (the Fedora-proven shape, §1.5):

```
ADSP fw (adsp.mbn+adsp_dtb) ── remoteproc boots; sensors PD waits
        │ FASTRPC_IOCTL_INIT_ATTACH_SNS  (fastrpc.c:2321-2322)
hexagonrpcd -s  ── attaches to the sensors PD and serves it files
        │ apps_std file reads through a virtual "hexagonfs":
        │   /vendor/etc/sensors/config + sns_reg_config, /odm/etc/sensor,
        │   /mnt/vendor/persist/sensors/registry, /sys/devices/soc0,
        │   /usr/lib/qcom/adsp (dsp libs)   (rpcd_builder.c:32-34,112-210)
sensors PD ── parses registry, probes its SPI/I2C buses, publishes
        │ QMI "SSC" service (QMI_SERVICE_SSC) on QRTR
libssc  ── GLib client; qrtr_node_lookup_port(QMI_SERVICE_SSC)
        │ (libssc-client.c:299,365-368); protobuf-encoded SEE requests
iio-sensor-proxy 3.9 (ssc-support) ── drv-ssc-{accel,light,proximity,compass}
        │ net.hadess.SensorProxy on D-Bus
GNOME/mutter ── claims accelerometer in tablet mode → auto-rotation
```

### 1.3 What our tree and build already have [V]

- DT: everything in §1.2(2–3) is in the pinned perpetua tree unmodified;
  our worktree diff shows no deltas in the fastrpc/adsp region (checked
  today). ADSP firmware names `qcom/kaanapali/iceland/adsp.mbn` +
  `adsp_dtb.mbn` (`kaanapali-oneplus-iceland.dts:1257-1259`) — shipped
  since Phase A and running (`docs/firmware-manifest.md:35-37`).
- Config (`build/linux-iceland/.config`): `CONFIG_QCOM_FASTRPC=m` :2176,
  `CONFIG_QRTR=m`/`QRTR_SMD=m` :1635-1636, `CONFIG_QCOM_PD_MAPPER=m`
  :7132, `CONFIG_QCOM_QMI_HELPERS=y` :7156, `CONFIG_QCOM_PDR_HELPERS=y`
  :7154, Q6V5 PAS stack :7055-7058. **No kernel config change needed.**
- Built modules present in `out/kernel-iceland/modules-root/…/7.3.0+/`:
  `fastrpc.ko.zst`, `qrtr.ko.zst`, `qrtr-smd.ko.zst`,
  `qcom_pd_mapper.ko.zst`. Autoload verified by modinfo aliases:
  fastrpc = `of:N*T*Cqcom,kaanapali-fastrpc`; pd_mapper =
  `auxiliary:qcom_common.pd-mapper` (spawned by the PAS driver).
- The in-kernel PD mapper already advertises the sensors PD for this SoC:
  `qcom_pd_mapper.c:394-399` (`kaanapali_domains` includes
  `adsp_sensor_pd` = "msm/adsp/sensor_pd", instance 74, :289-293; matched
  by `qcom,kaanapali` :627). No `adsps.jsn` needed.

**The two DT gaps** (both tiny, both Fedora-proven):

1. `qcom,non-secure-domain` is missing on the adsp fastrpc node
   (`kaanapali.dtsi:3243-3248`; grep across both our trees finds none), so
   the driver creates only `/dev/fastrpc-adsp-secure`
   (`fastrpc.c:2599-2600`: no property → `secure_dsp = true`). hexagonrpcd
   and iio-sensor-proxy's udev anchor expect `/dev/fastrpc-adsp`. One-line
   fix = Fedora patch 0061 (SM8650 upstream does the same). Contingency:
   `fastrpc_init_attach(SENSORS_PD)` has no secure-device gate
   (`fastrpc.c:2318-2322`; `is_session_rejected()` :1433-1442 only guards
   the *non-secure dev on secure channel* combination), so pointing
   `hexagonrpcd -f /dev/fastrpc-adsp-secure` at the secure node is
   expected to work **[I]** — which makes a zero-kernel-change first
   flight possible (§5 S2).
2. (Optional/contingency) the ADSP FastRPC remote heap: Fedora reserves a
   12 MiB region and hands it to the LPASS/ADSP-heap VMs (their 0170,
   later made `no-map` by 0194 after a linux-next fastrpc change started
   assigning the whole range at probe). The kernel otherwise logs "no
   reserved DMA memory for FASTRPC" and static-PD heaps come from the
   generic pool. Fedora added it early; whether the *sensors* PD attach
   needs it on this ADSP build is untested by us (open question §7). Keep
   as a prepared lever, not a first-flight variable; the C4 audio PD work
   will want the same region.

### 1.4 What the stock vendor/ODM/dsp/persist artifacts give us [V]

Everything hexagonrpcd must serve exists in images we already hold,
read-only:

| hexagonfs path (DSP view) | our source | contents |
|---|---|---|
| `/vendor/etc/sensors/config` | `stock/vendor-extracted/etc/sensors/config/` | 95 platform JSONs + `json.lst` |
| `/vendor/etc/sensors/sns_reg_config` | `…/etc/sensors/sns_reg_config` | registry wiring (§1.1) |
| `/odm/etc/sensor` (needs Fedora hexagonrpc patch 0001) | stock `odm.img` → `/etc/sensor/` (`config/` 11 JSONs, `json_list`, `sensor_config.json`, `sensor_type`) | the iceland chip selection (§1.1) |
| `/mnt/vendor/persist/sensors/registry/registry` | `factory/fcap/part-persist.img` → `/sensors/registry/registry` | **our unit's** 352-file registry incl. factory cal |
| `/usr/lib/qcom/adsp` | stock `dsp.img` → `/adsp/` | `fastrpc_shell_0`, `libsns_*_skel.so`, `sns_tppe.so` |
| `/sys/devices/soc0` | values from the running tablet (`soc_id`, `hw_platform`, `platform_subtype{,_id}`, `platform_version`, `revision`, `family`, `machine`) | socinfo files the registry config keys on |
| `/vendor/etc/acdbdata` | audio cal (C4's business; hexagonfs maps it, empty is fine for sensors) | — |

persist, precisely (the user asked): `part-persist.img` is a 128 MiB ext4
image; the factory capture **does include it**. A read-only loop mount
would show `/sensors/` containing `sensors_list.txt` (the live sensor
list), `cam_registry_dump.txt`, `odp/`, and `registry/` with
`sns_reg_version`, `parsed_file_list.csv` and `registry/` = the 352
entries: per-chip trees (`bmi3x0_0*`, `ak0991x_0*`, `alsps_*`,
`bu52053nvx_0*`), `default_sensors.*` attributes, `devinfo.*` pointers to
the cal paths, and oplus_* algorithm state. We read all of it with
`debugfs -R` (no mount, no root). **These `fac_cal` values are this unit's
factory calibration — per-unit data; never publish them** (Fedora's
EXCLUDED.tsv draws the same line: their published registry was declared
generic by their owner; ours stays private to this unit).

### 1.5 What Fedora does, file-level [S]

The Fedora iceland port has this fully working: "all four sensor types
appear at boot … auto-rotate works in tablet mode"
(`iceland-mainline/docs/FEATURES.md:147, :59`). Their stack (repos:
`mzakamin/iceland-linux` patches, `mzakamin-hub/iceland-mainline`
packaging+docs, `mzakamin/iceland-firmware` DSP tree; clones in this
session's scratchpad `repos/`):

**Kernel patches** (`iceland-linux/patches/0002-iceland/`):

| patch | what |
|---|---|
| `0061-…-allow-non-secure-ADSP-FastR.patch` | adds `qcom,non-secure-domain` to the adsp fastrpc node "as on SM8650 … hexagonrpcd needs /dev/fastrpc-adsp to start the sensors protection domain" — our gap #1 verbatim |
| `0170-…-add-the-ADS.patch` | 12 MiB `adsp_rpc_remote_heap_mem` shared-dma-pool + `memory-region`/`qcom,vmids` (LPASS, ADSP_HEAP) on the fastrpc node |
| `0194-…-ADSP-remote.patch` | makes that region `no-map` (CMA pages faulted at stage-2 after a linux-next fastrpc change assigns the range at probe) |
| `0193-misc-fastrpc-fix-double-free…` | upstream cherry-pick (2159430fe260), unprivileged-reachable error-path double free — adopt with 0011 as hygiene |
| `0018` | reserves `adsp_mhi_mem`+`global_sync_mem` (we already carry these regions :193, :230) |
| `0030-…-add-the-lid.patch` + `0115-…-keep-the-ha.patch` + `0116-Input-gpio-keys…` | the hall sensor as an AP lid switch — §1.6 |
| config | only `CONFIG_QCOM_FASTRPC=m` added by their sm8850 fragment (0003) — matches our config state |

**Userspace** (`iceland-mainline/packaging/sensors/README.md` — the whole
recipe):

| package | upstream pin (`docs/sensors/patches/upstream-bases.txt`) | their deltas |
|---|---|---|
| hexagonrpc | github.com/linux-msm/hexagonrpc `598b591` (v0.5.0+19) | `0001-hexagonrpcd-serve-odm-etc-sensor…` (maps `/odm/etc/sensor` → `<root>/odm/sensor`; OnePlus keeps `json_list` there) and `0002-hexagonrpcd-answer-unsupported-calls-and-keep-serving` (the Pad 4's sensors PD calls apps_std **method 36** right after attach; unpatched hexagonrpcd logs "Unsupported method: 36 (1f050100)" and *exits* — once per boot, Restart=always hid it). Both still absent at upstream HEAD `da7a374` (checked: `listener.c:592-596` still breaks the serve loop). |
| libssc | codeberg.org/DylanVanAssche/libssc `54dd13e` (v0.4.4+8) | build with tests/mocking dirs removed; + `libssc-iceland-hall.patch` (hall class for `ssccli --sensor hall`, cover detection extra) |
| iio-sensor-proxy | 3.9 (`0085ddf8`) | built `-Dssc-support=enabled`; + 0001 (poll sensors claimed during discovery), 0002 (hold back HasAccelerometer for a mutter-50 claim bug), 0003 (ALS rate-limit/hysteresis: 10 Hz × ±2 % noise was 100 D-Bus LightLevel changes/10 s), 0004 (claim the hub's **device_orient** on-change sensor instead of streaming 25 Hz accel — iio-sensor-proxy was "the largest user-space waker of an idle desktop", ~17 wakeups/s) |

**Device integration** (`iceland-mainline/docs/sensors/81-iceland-ssc.rules`
and `packaging/iceland-device/files/`):

- udev rule on `SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp"`:
  `IIO_SENSOR_PROXY_TYPE="ssc-light ssc-compass ssc-accel ssc-proximity"`
  (upstream's own rule, `data/80-iio-sensor-proxy.rules:24-25`, only
  enables light+compass and matches `fastrpc-adsp*`), **the mount matrix**
  `ACCEL_MOUNT_MATRIX="0, 1, 0; -1, 0, 0; 0, 0, -1"` (hub reports Android's
  portrait frame; panel is 3392×2400 landscape; measured in the stand),
  and `SYSTEMD_WANTS+="hexagonrpcd-adsp-sensorspd.service
  iio-sensor-proxy.service"` — both services are started by the *node*,
  not by multi-user.target.
- `hexagonrpcd-adsp-sensorspd.service.d/iceland.conf`: `ExecStart=
  /usr/bin/hexagonrpcd -f /dev/fastrpc-adsp -d adsp -s -R
  /usr/share/qcom/kaanapali/OnePlus/iceland`, `User=fastrpc`, full
  sandbox; `ConditionPathIsDirectory=…/sensors/registry`;
  `Before=iio-sensor-proxy.service`. Two operational pearls in its header:
  **"It has to run early: the sensor hub stops asking for its files a few
  minutes after the ADSP has started"**, and hexagonrpcd **refuses every
  write** (`apps_std` open-for-write → AEE_EUNSUPPORTED; "the registry's
  own write attempts end there on every kernel so far" — i.e. a read-only
  registry tree is the proven steady state).
- `-R` note: without `-R`, hexagonrpcd auto-derives
  `/usr/share/qcom/<chipset>/<Vendor>/<device>` from
  `/proc/device-tree` compatible+model (`rpcd.c:376-425` + the guesser) —
  for us `kaanapali/OnePlus/iceland`, same path either way.
- Suspend: the hub streams through s2idle if left alone (~36 wakes/s on
  the sibling SoC — keeps the SoC out of deep idle). Upstream's unit has
  `Conflicts=suspend.target`; Fedora adds
  `iio-sensor-proxy.service.d/iceland-sleep.conf`, a system-sleep hook
  (`iceland-sensors-sleep`) as fallback, a resume unit that restarts both,
  and an event-driven watchdog (`iceland-ssc-watch.service` + timer, armed
  by `OnSuccess=`/`OnFailure=` of the proxy). GNOME reclaims the
  accelerometer when the proxy returns to the bus.
- The DSP file tree is **extracted from the owner's tablet at install
  time** into `/usr/share/qcom/kaanapali/OnePlus/iceland` (private, never
  shipped); the published `iceland-firmware` repo mirrors the layout
  (`root/usr/share/qcom/kaanapali/OnePlus/iceland/{dsp/adsp,odm/sensor,
  sensors/{config,registry,sns_reg.conf},socinfo,acdb}`) with their
  registry as `%config(noreplace)`.
- Known quirks they hit (watch-list for us): a) the dwc3-qcom USB
  controller dropped its interconnect votes at runtime suspend **while
  the hub streamed**, causing short display glitches with auto-rotate on —
  fixed on their 7.4-base kernel q90d ("keep those votes on Kaanapali",
  `docs/MAINLINE-STATE.md:26-28`, `FEATURES.md` Auto-rotate row); our 7.3
  perpetua does not carry that fix. b) mutter claim bug (their
  iio-sensor-proxy 0002). c) the GDM greeter holding the light sensor.
  d) `iio-sensor-proxy` hung at suspend 2/14 before their sleep hooks.
  e) camera I2C level shifters only powered while the hub streams — their
  0086 made them always-on (camera-phase dependency, not ours yet).

### 1.6 The hall sensor is dual-path (hub *and* AP GPIO) [S][V]

BU52053NVX output is wired to **TLMM 98** and is plain digital: Fedora
reads it as a `gpio-keys` **SW_LID** switch on the AP (their 0030), fixes
its supply (0115: L1B `regulator-always-on` — on stock the *hub* holds
L1B while the sensor runs; a Linux that only reads the GPIO must hold the
rail itself or the level bounces in s2idle CX collapse), and carries a
generic gpio-keys wakeup fix (0116) for the PDC edge-latch-on-CX-exit
that ended every cover-open sleep after ~0.5 s. Our DTS has a `gpio-keys`
node (volume-down only, `kaanapali-oneplus-iceland.dts:111-125`) to extend.
This is the only sensor with a plain-IIO/evdev-style AP path, and it's
independent of the whole SSC stack — a separate mini-ladder (§5 H1).

### 1.7 Other reference implementations

- **phonewave/denialwm (Arch sibling)**: **no sensor handling at all** —
  `devices/iceland/` has wifi/audio/GPU-thermal/touch units, zero
  hexagonrpc/libssc/iio mentions (clone checked today) **[S]**. perpetua
  itself carries no iceland sensor DT beyond what §1.3 lists.
- **x1e80100-class laptops**: their sensors (where fitted) are
  ACPI/AP-attached and plain IIO — but the pattern "AP-attached IIO sensor
  in a qcom DTS" is otherwise almost entirely a budget-SoC phenomenon
  (msm8916/8939/8953 boards dominate the grep for bosch,/st,/kionix,/
  memsic, compatibles in our tree) **[V]**.
- **The one modern exception is instructive**: `sm8550-oneplus-aston.dts`
  :382-408 (upstream, in our tree) **bit-bangs SPI over the TLMM pins of
  the hub's own bus** (`spi-gpio`, tlmm 192-195, "Bit-banged bus on the
  LPI pins") and binds the plain IIO `bosch,bmi260` driver — Route B
  below. It works because that port never attaches the sensors PD, so
  nothing else drives the bus.
- **postmarketOS lineage**: hexagonrpc/libssc/iio-sensor-proxy-ssc *is*
  the pmOS SDM845-era stack (Dylan Van Assche; pmaports carry hexagonrpcd
  for e.g. SHIFT6mq, xiaomi-beryllium, FP4) — mainlined far enough that
  **Debian packages all three** (DebianOnMobile team) **[W]**:
  - Ubuntu 26.04 "resolute": `hexagonrpcd 0.4.0-1` (universe) — but
    v0.4.0 predates the v0.5.0 interp4/`>31 methods` rework the Pad-4's
    method-36 call needs, and both Fedora patches; `iio-sensor-proxy
    3.8-1` — **3.8 has no SSC backend**; **no libssc at all**.
  - Debian sid/forky: `iio-sensor-proxy 3.9-1` with
    `-Dssc-support=enabled` **on arm64** (d/rules), `libssc` 0.4.2-2
    (binary `libssc2`; deps libqmi-glib5, libqrtr-glib0, protobuf-c),
    `hexagonrpc` source 0.3.2-2.
  So the Ubuntu story is: backport Debian's `iio-sensor-proxy 3.9-1` and
  `libssc 0.4.2-2`, and rebuild `hexagonrpc` at the Fedora pin + 2
  patches (Debian's packaging, newer orig). All three are small
  meson/glib builds.

---

## 2. Route decision

**Route A — the sensor hub (SSC) over FastRPC/QRTR. Chosen.** It is the
architecture the hardware ships (§1.2), the only route with gyro + mag +
ALS + proximity + factory calibration + the low-power `device_orient`
sensor, and it is *proven end-to-end on this exact tablet* by Fedora with
published patches, units and pins (§1.5). Kernel cost: one DT line
(+ two optional hygiene/contingency patches). Userspace cost: three small
packages, two of them straight Debian backports.

**Route B — AP bit-bang IIO (aston-style), fallback only.** `spi-gpio`
over the IMU's pins + mainline `bmi323_spi` driver would give accel/gyro
with zero DSP involvement. Rejected as primary because: the BMI3x0's SPI
pins on iceland are unknown (they live in the hub's devcfg/adsp_dtb, not
in any HLOS DT we hold — discovery would mean schematics or probing),
it covers one chip only (no ALS for auto-brightness, no mag), it abandons
factory cal, and it **conflicts with Route A by design** (two masters on
one bus; the aston port never starts the sensors PD). Revisit only if
Route A hits a wall the Fedora port didn't (that would be surprising —
same SoC, same board, same firmware generation).

---

## 3. Gap analysis (us today → Route A shipped)

| # | Gap | Size | Where it lands |
|---|---|---|---|
| G1 | DT: `qcom,non-secure-domain` on adsp fastrpc | 1 line (≙ Fedora 0061) | `kernel/patches/0011-…` (S3 flight; S2 works around it via the secure node) |
| G2 | DSP file tree `/usr/share/qcom/kaanapali/OnePlus/iceland` | host assembly script from held artifacts (§1.4), ~tens of MB | overlay / device package; registry part stays unit-private |
| G3 | hexagonrpcd at `598b591` + Fedora patches 0001/0002 | rebuild of the Ubuntu source package with new orig + 2 patches | local deb `hexagonrpc 0.5.0+git598b591-0iceland1` (> 0.4.0-1) |
| G4 | libssc | backport Debian sid `libssc 0.4.2-2` (build-deps all in 26.04: libqmi-glib-dev, libqrtr-glib-dev, protobuf-c) | local deb |
| G5 | iio-sensor-proxy 3.9 with SSC | backport Debian sid `3.9-1` (arm64 enables ssc; build against G4) | local deb `3.9-1~iceland1` (wins over archive 3.8-1) |
| G6 | udev rule + unit drop-in + mount matrix | adopt Fedora's `81-iceland-ssc.rules` + `hexagonrpcd…iceland.conf` nearly verbatim (systemd paths, same matrix) | `ubuntu-iceland-device` |
| G7 | suspend/resume + watchdog hygiene | Fedora's sleep hook / resume unit / ssc-watch pattern, trimmed to what our s2idle phase (C6) needs | `ubuntu-iceland-device`, after S6 |
| G8 | hall/lid switch (independent) | DT node + L1B always-on (≙ Fedora 0030+0115); 0116 only when C6 touches s2idle | `kernel/patches/0012-…` (H1) |
| G9 | contingency: ADSP FastRPC remote heap (≙ Fedora 0170+0194, as one no-map patch) | ~20 lines DT | prepared patch, flown only on evidence; shared interest with C4 audio |
| G10 | QoL patches: Fedora iio-sensor-proxy 0001–0004, libssc hall | cherry-picks | after S6, evidence-driven |

Kernel config: **no gap** (§1.3). Firmware: **no gap** (adsp.mbn already
ships; the hub's dynamic libs travel in G2, not in /lib/firmware).

---

## 4. Deliverables to build before the first flight (host-side, no tablet)

1. **`scripts/make-dsp-tree.sh`** (new): assemble G2 into
   `out/dsp-tree/usr/share/qcom/kaanapali/OnePlus/iceland/` —
   `sensors/config` ← vendor-extracted, `sensors/sns_reg.conf` ←
   vendor `sns_reg_config`, `odm/sensor` ← odm.img extraction,
   `dsp/adsp` ← dsp.img `/adsp` (debugfs rdump), `sensors/registry` ←
   persist extraction (**chmod 0600, directory 0750 root:fastrpc** — the
   Fedora tmpfiles policy), `socinfo/` placeholder filled from the tablet
   in S0. Manifest with sha256 per file, like `configs/firmware/`.
   Sources are all read-only inputs; the script never touches them.
2. **Three debs** (G3–G5) in `packaging/` or a local repo dir, built in
   the usual sbuild/chroot flow. Order: libssc → iio-sensor-proxy.
   Pin/hold note: `3.9-1~iceland1` naturally outranks resolute's 3.8-1;
   add the same apt-pin style we use for other held packages if an SRU
   ever ships a 3.9 without ssc.
3. **`kernel/patches/0011-kaanapali-fastrpc-non-secure-domain.patch`**
   (G1, with 0193's double-free pick appended or as 0011b) staged but NOT
   applied to any release build until its flight (S3).

---

## 5. Flight ladder

All flights: release-kernel RAM boot (`fastboot boot` of the current
bundle) or the flashed slot-B system where noted, display up, ssh + one
serial listener, `dmesg -w | tee` running. Record per flight: commands,
journal/dmesg excerpts, ADSP SSR count (must stay 0), battery UI alive.

### S0 — recon on the flashed system (no changes, no reboot)

1. `ls -l /dev/fastrpc*` → expect `fastrpc-adsp-secure` + `fastrpc-cdsp*`
   only (G1 evidence on-device); `lsmod | grep -E 'fastrpc|qrtr|pd_mapper'`.
2. `apt install qrtr-tools` (or build `qrtr-lookup`); `qrtr-lookup` →
   record services. The SSC QMI service must be **absent** (nobody
   attached the sensors PD yet) — that absence is the S2 baseline.
3. Harvest `/sys/devices/soc0/{soc_id,hw_platform,platform_subtype,
   platform_subtype_id,platform_version,revision,family,machine}` into
   the G2 tree's `socinfo/`.
4. Confirm `/sys/bus/iio` still empty; snapshot `/proc/interrupts` IPCC
   lines (idle baseline for the S4 comparison).

**Gate:** recon table written into the porting log; socinfo captured.

### S1 — host builds (no tablet)

§4 items 1–2 done; tree manifest recorded; debs install cleanly in a
26.04 arm64 chroot. **Gate:** `dpkg -c` of the three debs shows the units,
udev rules, `ssccli`, `monitor-sensor`; `hexagonrpcd -h` from the chroot
prints the pinned usage.

### S2 — first attach, zero kernel change (RAM boot or flashed system)

**Change (one):** stage the G2 tree + hexagonrpcd deb; within ~2 minutes
of boot (the early-window rail, §1.5) run, as root, verbosely:
`hexagonrpcd -f /dev/fastrpc-adsp-secure -d adsp -s -R
/usr/share/qcom/kaanapali/OnePlus/iceland`.
**Proves:** INIT_ATTACH_SNS works on this kernel/firmware; the hub asks
for and accepts our file tree; the registry parses.
**Gate:** hexagonrpcd logs the attach ("INIT_ATTACH_SNS") and a stream of
file opens (sns_reg.conf, json_list, kaanapali_mtp_*.json, registry
reads); `qrtr-lookup` now lists the **SSC service**; dmesg shows no adsp
SSR. Expected-and-fine: "Tried to open … for writing" refusals (registry
write-back; §1.5), and — if the method-36 call arrives on a path our
build misses — one clean exit+restart, never a loop.
**If the secure node refuses the attach** (errno from the ioctl): no
debugging on the secure path — S3's DT line is the fix; fly it next.

### S3 — DT flight: `/dev/fastrpc-adsp` (patch 0011)

**Change (one):** 0011 in a RAM-boot bundle. Re-run the S2 procedure on
`/dev/fastrpc-adsp` as user `fastrpc` via the packaged unit + Fedora-style
drop-in (udev `SYSTEMD_WANTS` start).
**Gate:** node exists at boot; unit active within the early window with
no manual step; same S2 success lines; `udevadm info /dev/fastrpc-adsp`
shows our rule's env (matrix + four ssc types).

### S4 — libssc: raw hub streams

**Change (one):** libssc deb. Run `ssccli --sensor accelerometer`, then
`light`, `proximity`, `magnetometer`, `gyroscope`.
**Gate:** accelerometer prints ~9.8 m/s² magnitude that tracks tilting;
light reacts to covering the top-left bezel (STK36C01 position —
verify); proximity NEAR/FAR; record `/proc/interrupts` IPCC delta while
streaming vs idle (Fedora datum: ~89/s vs ~10/s). Stop the stream, rate
returns to baseline.

### S5 — iio-sensor-proxy 3.9 + udev rule

**Change (one):** iio-sensor-proxy deb + `81-iceland-ssc.rules` (Fedora's
matrix verbatim).
**Gate (the task's named gate):** `monitor-sensor` shows
"Accelerometer orientation changed: normal/left-up/right-up/bottom-up"
through a full 4/4 physical rotation, plus live LightLevel lines;
`busctl --system introspect net.hadess.SensorProxy /net/hadess/SensorProxy`
→ `HasAccelerometer true`. If orientations are rotated/mirrored: fix is
the matrix string in OUR rule file — one later flight, not a live edit.

### S6 — GNOME auto-rotation (C5 tie-in)

**Change:** none (GNOME session from the C5 track).
**Gate:** in tablet mode (no pogo/BT keyboard), the desktop follows 4/4
orientations; rotation lock in quick settings freezes it; attaching the
keyboard stops rotation (expected GNOME behavior, Fedora FEATURES.md:59);
detaching resumes. 20-minute soak with auto-rotate on: zero display
glitches/underruns (watching for the dwc3-icc class, §1.5 quirk a), zero
proxy restarts, battery UI still updating (ADSP shared-health check).

### S7 — ship

1. Package G6 into `ubuntu-iceland-device` 0.2.x (udev rule, drop-in,
   tmpfiles `Z` line for the tree, sysusers fragment if our hexagonrpc
   deb doesn't ship one); the G2 tree installs via the overlay flow with
   its manifest; registry directory marked config/no-replace analog
   (dpkg conffile or shipped by a postinst copy — decide at packaging
   time; never in a public artifact).
2. 0011 (+0193) ride the next planned boot_b flash (flash-first rule;
   RAM-boot-gated). Until that flash, the flashed system keeps working
   via S2's secure-node drop-in override — remove the override in the
   same 0.2.x that assumes `/dev/fastrpc-adsp`.
3. Suspend hygiene (G7) before C6 closes: proxy stopped before sleep
   (upstream `Conflicts=suspend.target` already covers hexagonrpcd),
   resume restart unit, optional ssc-watch. Verify 3/3 suspends: stream
   stops (IPCC rate at baseline during sleep), rotation resumes ≤5 s
   after wake.
4. **Gate (ladder exit):** 3/3 cold power-on boots → GNOME rotation works
   with zero manual steps; `hardware-status.md` sensors row → ✅;
   porting-log entry; firmware-manifest section for the DSP tree +
   manifest; Fedora-delta notes into fedora-parity-audit.

### H1 — hall/lid mini-ladder (independent, any time after S0)

**Change (one):** patch 0012 = lid `switch-lid` gpio-keys node on TLMM 98
(+ pinctrl bias-disable) + `regulator-always-on` on L1B (≙ Fedora
0030+0115 — their 0115 rationale is s2idle-specific but the rail
ownership point stands as soon as the hub *isn't* streaming hall). RAM
boot. **Gate:** `evtest` on the gpio-keys device shows SW_LID 0/1 with a
magnet/cover; `loginctl` reports Lid closed/open. Defer 0116 (wakeup
edge-latch fix) to the C6 s2idle ladder where it's testable.

---

## 6. Risks and rails (sensor-specific)

- **The early-window trap**: the sensors PD stops requesting files a few
  minutes after ADSP boot (§1.5). A "late" hexagonrpcd looks like a dead
  hub. Rail: flights start the daemon right after boot; the shipped unit
  starts from udev on node appearance, never from multi-user.target.
- **ADSP SSR blast radius**: a sensors-PD crash can restart the whole
  ADSP → battery UI and (future) audio drop until recovery. Rail: one SSR
  = stop the ladder; never leave a flapping unit (`Restart=always` +
  method-36 exit = at most one restart/boot with the patched build —
  more than that is a finding).
- **Registry writes**: the hub will try to persist dynamic calibration;
  hexagonrpcd refuses writes by design and Fedora ran every kernel so far
  that way. Rail: do NOT "fix" the refusals by making the tree writable —
  that's a deliberate future decision (open question 5), not a flight
  tweak. Our real persist partition is never given to the stack at all.
- **Display glitches while streaming** (dwc3-qcom icc votes at runtime
  suspend; Fedora fixed on their 7.4 base, our 7.3 lacks it). Rail: S6
  soak watches for it; the mitigation flight (one variable) is disabling
  USB runtime PM; the fix is porting their q90d-era dwc3 change —
  evidence first.
- **Suspend wake-storm**: an un-stopped stream ≈36 wakes/s through
  s2idle. Rail: G7 hooks before C6 signs off suspend; `sensors-keep`-style
  escape hatch only in a test boot.
- **Mount matrix is per-model, not per-unit** — adopt Fedora's measured
  matrix, verify in S5; the per-unit part (bias/corr_mat) comes free from
  OUR persist registry in the G2 tree.
- **Unit privacy**: the registry (fac_cal), like the BT address, is unit
  data — keep it out of any published repo/artifact (Fedora's
  EXCLUDED.tsv precedent; our persist stays a read-only capture).
- **Never run Route B experiments** (spi-gpio bit-bang) in a boot where
  the sensors PD has been attached — two masters, one bus.
- **GNOME quirks are not regressions**: no rotation with a keyboard
  attached (tablet-mode logic), greeter possibly holding the light
  sensor, mutter claim-timing bug (Fedora iio 0002 exists if we see it).

## 7. Open questions

1. **Remote heap necessity** (G9): does INIT_ATTACH_SNS / steady-state
   sensor streaming on this ADSP build need the 12 MiB
   `adsp_rpc_remote_heap`? Fedora carries it (0170+0194) but their commit
   text ties it to the DSP's *static process* heap generally. S2/S4
   either proves it unnecessary or produces the error that justifies the
   prepared patch. (C4 audio will revisit regardless.)
2. **Secure-node attach** (S2's premise): code-read says
   `fastrpc_init_attach` has no secure-channel gate
   (`fastrpc.c:2318-2322`, :1433-1442) — confirm on-device; if wrong, S3
   simply moves up one rung.
3. **hexagonrpcd archive 0.4.0-1 viability**: v0.4.0 predates the >31-
   method decode (`78e2a94`) — unknown failure shape on the method-36
   call. We lead with the pinned build, so this only matters if we want
   to drop G3 later; test once out of curiosity, not on the ladder.
4. **GDM/greeter ALS behavior on Ubuntu** (Fedora needed 0.28-18): check
   during C5; adopt their iio 0001/0002 only on symptoms.
5. **Calibration write-back policy**: stay read-only forever (Fedora's
   state), or eventually give the registry a writable copy-on-first-boot
   home so dynamic ALS cal (`alsps_hw_stk36c01.dynamic_cali`) persists?
   Needs a hexagonrpcd write path that upstream doesn't have — park it.
6. **Gyro/mag consumers beyond rotation**: iio-sensor-proxy exposes
   accel/light/prox/compass only; gyroscope reachable via
   `ssccli --sensor gyroscope` (works on Fedora, 24.4 Hz at rest). A
   desktop consumer is out of scope until something needs it.
7. **device_orient power optimization** (Fedora iio 0004, hub-side
   on-change sensor replaces the 25 Hz accel stream): adopt after S7 as a
   measured improvement (their numbers: proxy was the largest userspace
   waker; our battery discipline will want this).
8. **Rear flicker/RGB sensor** (`devinfo.rgb_rear` → camera AON): leave
   to the camera phase; not exposed by any desktop stack today.

## 8. Reference anchors (for the flight notebook)

- **Ours**: DTS `kaanapali-oneplus-iceland.dts` — adspslpi :21,:223,
  adsp fw names :1257-1259, i2c0/i2c22/i2c3/i2c14/i2c15 :908/:945/:981/
  :1009/:1021, spi19 :1278, gpio-keys :111-125. dtsi — remoteproc_adsp
  :3194-3240, fastrpc+cbs :3243-3296, lpass_tlmm :3560-3571, tlmm (218
  pins) :5017-5023. `fastrpc.c` — ioctls :2318-2329, secure flag
  :2599-2600, session gate :1433-1442. `qcom_pd_mapper.c` —
  sensor_pd :289-293, kaanapali :394-399,:626-627. `.config` — :1635,
  :2176, :7055-7058, :7132, :7154, :7156. Modules:
  `out/kernel-iceland/modules-root/lib/modules/7.3.0+/…` (fastrpc, qrtr,
  qrtr-smd, qcom_pd_mapper). Patches dir: `kernel/patches/` (0001–0010
  today; 0011+ are this plan's).
- **Stock artifacts**: `stock/vendor-extracted/etc/sensors/
  {config,sns_reg_config,hals.conf}`, `etc/init/vendor.sensors.sscrpcd.rc`;
  `stock/current/odm.img` → `/etc/sensor/` (extraction in this session's
  scratchpad `odm-sensor/cfg/`); `stock/current/dsp.img` → `/adsp/`;
  `factory/fcap/part-persist.img` → `/sensors/` (debugfs, read-only).
- **Fedora**: `repos/iceland-linux/patches/0002-iceland/` 0061, 0170,
  0193, 0194, 0030, 0115, 0116 (+0018, 0086 context);
  `repos/iceland-mainline/packaging/sensors/{README.md,*.spec,
  60-hexagonrpc.rules,libssc-iceland-hall.patch}`,
  `docs/sensors/81-iceland-ssc.rules`, `docs/sensors/patches/
  {hexagonrpc,iio-sensor-proxy}/000*.patch`, `upstream-bases.txt`;
  `packaging/iceland-device/files/{hexagonrpcd-adsp-sensorspd-iceland.conf,
  iceland-dsp-tree.conf,iceland-sensors-sleep,iceland-ssc-watch.service,
  iio-sensor-proxy-iceland-watch.conf}`; `docs/FEATURES.md` :59,:147;
  `docs/MAINLINE-STATE.md` :26-28; `repos/iceland-firmware/root/usr/share/
  qcom/kaanapali/OnePlus/iceland/` (the tree layout), `README.md` :45-49,
  `EXCLUDED.tsv` :5.
- **Upstreams** (scratchpad clones): hexagonrpc — `rpcd.c:376-425` (flags,
  attach), `rpcd_builder.c:32-34,112-210` (hexagonfs map),
  `listener.c:563-602` (serve loop; exits on unsupported method at HEAD
  `da7a374`); pins: Fedora `598b591` (=v0.5.0+19). libssc —
  `src/libssc-client.c:299,356-368` (QRTR + QMI_SERVICE_SSC discovery),
  `src/libssc-cli.c:171` (ssccli sensors). iio-sensor-proxy 3.9 —
  `meson_options.txt:21-24` (ssc-support), `meson.build:49`
  (libssc>=0.2.1), `src/drv-ssc-*.c`, `data/80-iio-sensor-proxy.rules:
  24-25`, `data/iio-sensor-proxy.service.in` (AF_QIPCRTR already
  allowed). Route-B precedent: `sm8550-oneplus-aston.dts:382-408`.
- **Archives [W]** (checked 2026-11-01): Ubuntu resolute —
  iio-sensor-proxy 3.8-1, hexagonrpcd 0.4.0-1, no libssc. Debian sid —
  iio-sensor-proxy 3.9-1 (`-Dssc-support=enabled` on arm64 per d/rules),
  libssc 0.4.2-2, hexagonrpc 0.3.2-2.
