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
- Touch: novatek/novatek_nt36536_fw.bin (DTS names it) — C2.
- Audio: LPASS topology + UCM2 profiles — C4.

## Rules

Never stage a blob without recording sha256 + source here first.
Prefer our own stock extraction; third-party copies only with
published-hash corroboration from at least two independent sources
(the AQE/vendor-pair standard).
