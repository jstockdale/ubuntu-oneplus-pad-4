# Firmware manifest: what we ship, byte for byte

Every proprietary blob staged on the tablet or banked in the rootfs
overlay, with its sha256 and the full provenance chain. Verified
2026-11-01 on the device (serial 2fe096b5, stock 11.A.38 lineage,
package OnePlus_OPD2514_OP657AL1_16_BP2A.250605.015). Local sources:
`/srv/ubuntu-iceland/stock/vendor-extracted/` (our own vendor.img,
EROFS, extracted with fsck.erofs) and the Fedora port's firmware repo
clone (mzakamin iceland-firmware, MANIFEST.tsv-verified).

## GPU (Adreno 840 / gen80200) — the set that works

| file | sha256 | size | source | provenance |
|---|---|---|---|---|
| qcom/gen80200_sqe.fw | e2d4e74282f50e40788b83b9ba4a5f5894c7975ed356c03a0161372d78f12932 | 119156 | iceland-firmware vendor533 pair | SQE 0x094; byte-identical in SuperTurtleDev, map220v, Lenovo TB323FU ZUI 18.0.12.104 stock vendor |
| qcom/gen80200_gmu.bin | 06f4484fa06f91638aa4ae2412051bcddffdad69a7e2f83849c72412e6daa44d | 112030 | iceland-firmware vendor533 pair | GMU v5.3.33 (kernel prints it at load); same triple corroboration |
| qcom/gen80200_aqe.fw | ed7916ca84e663d63fa94b0d40cc8c222e362e6cff860c539a8cca30d3721b68 | 25880 | OUR stock vendor.img /firmware | byte-identical to SuperTurtleDev's copy (their compare TSV) |
| qcom/kaanapali/iceland/gen80200_zap.mbn | d185bfc9a819394537775a9facd49a6136f1fc66b848ea3de4e4e04ce9053db0 | 12088 | rootfs overlay (Phase A) | three-way match: overlay = our stock vendor.img = tablet |

All four live in `out/rootfs-overlay/lib/firmware/` and on the tablet.
The kernel's catalog (a6xx_catalog.c) requires ALL listed files —
adreno_load_fw aborts on any missing one — so SQE+GMU+AQE+zap is the
minimum set.

## The pair we deliberately do NOT use

Stock 11.A.38's own GPU pair (gen80200_sqe.fw 1f1c7bae…, SQE 0x103;
gen80200_gmu.bin 7e2f9381…, GMU v5.3.39) sits in
stock/vendor-extracted/firmware/. Per the Fedora port's testing it
RESETS THE TABLET EARLY IN BOOT unless GPU preemption is disabled.
Never stage it without that switch. Kept for reference only.

## Remoteproc / platform (shipped since Phase A, on tablet)

/lib/firmware/qcom/kaanapali/iceland/: adsp.mbn + adsp_dtb.mbn (ADSP
boots; battmgr/pd-mapper/audio-PD alive), cdsp.mbn + cdsp_dtb.mbn,
vpu40_2v.mbn, adspr.jsn. Sourced from our stock extraction in Phase A.

## Still owed (tracked in bringup-plan)

- WCN786x WLAN firmware + board files (ath12k) — blocked behind the
  pwrseq_qcom_wcn pin hunt (C3).
- BT: ship stock blob under the kernel's requested gngbtfw20.mbn name.
- Audio: LPASS topology + UCM2 profiles — C4.

## Rules

Never stage a blob without recording sha256 + source here first.
Prefer our own stock extraction; third-party copies only with
published-hash corroboration from at least two independent sources
(the AQE/vendor-pair standard).

## Bluetooth (WCN7860 BT = "Brahma", staged 2026-11-01)

Source: OUR unit's captured bluetooth_a partition
(factory/fcap/part-bluetooth_a.img, vfat, image/ dir) — 26 brh* files
staged verbatim to /lib/firmware/qca/ and banked in the overlay.
Key hashes:
- brhbtfw20.mbn bd2532555b88982cb9d0c24dfbe9224b57ae9e9d6c1c3d9b2b95af565334e5dd
- brhbtnv20.bin 3b5e9f7ccb2999e811a4c34e4d3272c85a9f1645c4df6e14338c67de135b5b9d
Loads verified on-device: BTFW.BRAHMA.2.0.1-00204, "QCA setup on UART
is completed", bluez controller registered. Kernel patch 0006 renames
the btqca WCN7860 request strings gng→brh to match stock (the infiniti
0084 lineage uses brh; the chip's own firmware label says BRAHMA).
Note: BT MAC currently a derived default; per-unit address lives in
persist (excluded data) — wire later like the Fedora installer does.

## Touch (NT36536 TDDI, verified staged 2026-11-01, C2 T0)

novatek/novatek_nt36536_fw.bin —
5e9d96517199ce11d44db90436e5835fed7982031102f52a74b7230ad64d83e2
(258048 B). Source: OUR odm.img /firmware/tp/25926/FW_NT36536_HUAXING.img
("FwUp!" container, 80-byte header + 128-byte trailer stripped —
transform recorded in configs/firmware/iceland.toml:165). Byte-identical
to the Fedora repo copy and the phonewave port's pinned hash (triple
corroboration). Already in out/rootfs-overlay and on the tablet; no
per-unit calibration exists for this part (persist checked).

## Audio (AudioReach topology, built 2026-11-01, C4 A0)

qcom/kaanapali/OnePlus-Pad4-tplg.bin —
f9bfb173aa8791527b218220b2c774b1b96feea94b0e58308ac9338bb13d0cb1
(39040 B). BUILT, not extracted: linux-msm/audioreach-topology @
993a17dcb672357998a463a73f120064d6c74f4f (BSD-3-Clause, Linaro — the
same project linux-firmware ships sibling *-tplg.bin builds from) +
the Pad 4 overlay from mzakamin-hub/iceland-mainline @ a7aab9f
(audio/topology/, vendored verbatim in configs/audio/topology/ with
LICENSE). Rebuild: scripts/build-audio-topology.sh (bit-reproducible;
VOL_CTRL_MAX=2056 = -12 dB bring-up cap — the 8192 stock-ceiling raise
is rung A7 of docs/audio-plan.md, only after the PipeWire limiter
chain is default). Reference build at 8192: sha d8f4b5f3e304cd2b7162
ba37d49aeba91e216d5008736936944ebc3a2da3e325 (not shipped; phonewave's
prebuilt 11b78ff1… provenance still open, audio-plan Q1). Loads as
card "OnePlus-Pad4" via q6apm topology request (qcom/<driver>/<model>
path, topology.c:1422).

Update 2026-11-02 (A7): the SHIPPED OnePlus-Pad4-tplg.bin is now the
stock-ceiling build, VOL_CTRL_MAX=8192 —
d8f4b5f3e304cd2b7162ba37d49aeba91e216d5008736936944ebc3a2da3e325
(39040 B; scripts/build-audio-topology.sh default). The -12 dB
bring-up build (2056, f9bfb173…) is retained as the reference the
ladder was flown on. Rail: 8192 only with the PipeWire speaker-
protection chain (device pkg 0.2.18+, swh-plugins) as the default sink.
