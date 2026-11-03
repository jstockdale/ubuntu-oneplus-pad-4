# Upstreaming

Status of everything this port carries that belongs somewhere else. The rule
(kernel/patches/README): a local patch is a loan, and this file is the ledger.

Status on 2026-11-03: nothing has been opened anywhere yet — no pull request
and no issue — because every channel below needs the port maintainer's
GitHub account (`gh` is not on the build host). The series accounted for
here is 62 patch files, 0001–0063 less the retired 0020, on Perpetua pin
`b7d639cfb282` (kernel #45, flashed to boot_b on 2026-11-03).

| What | Where it belongs | Status |
|---|---|---|
| 0028 q6apm WRITE_DONE payload-size consistency change (one hunk — the READ_DONE half is upstream) | denialwm/linux-perpetua, branch perpetua/v7.3 | **READ_DONE half merged upstream independently on 2026-11-02** (9ba37ef1db70, same `offsetofend` approach) and **dropped from 0028 at the pin bump of 2026-11-03** (pin b7d639cfb282, kernel #45 flashed the same day); the WRITE_DONE half is still carried and prepared as an optional consistency patch on branch `q6apm-write-done-payload-size` (one commit on b7d639cfb282) — no PR or issue has been opened anywhere yet, see below |
| 0002 watchdog: stop the bootloader-armed dog | denialwm/linux-perpetua | to prepare |
| 0004–0007, 0010 (WCN7860 supplies/roles/floor, btqca names, nt36536 probe gate, DSI sync orientation) | denialwm/linux-perpetua | to prepare — these were sequenced after the 0028 pull request, but the READ_DONE fix landed upstream on its own (9ba37ef1db70) and the WRITE_DONE remainder is optional, so the only gate left is the first PR itself: nothing has been opened yet (the port maintainer's GitHub account is needed; `gh` is not on the build host). 0005 touches the board dts and is BSD-3-Clause |
| 0011–0019, 0021–0024 (TDM speaker chain; 0020 retired at the 2026-11-03 pin bump — Perpetua's TFA9865 driver now puts the two middle amplifiers in stock's playing state by itself, registers 5f:00e0 and 76:d700 read back on #45, and the number is not reused), 0003/0008/0009 | mzak's Fedora iceland queue → Perpetua | theirs to submit; we carry with attribution |
| 0025/0026 (GPR callback order, GPR intent size) | infiniti-mainline → Perpetua | theirs |
| 0001 drop `panic=0` from bootargs | nowhere — Ubuntu-specific | permanent: initramfs-tools reads `panic=`; stays local with its reason in the header (board dts, BSD-3-Clause) |
| 0027 revert of Perpetua aad249d15433 ("lpass-tx-macro: compose capture mutes") | denialwm/linux-perpetua | carried; the revert restores upstream v7.3 behaviour on this codec — the compose-capture-mutes path left the tx-macro chain unpowered (A5, confirmed on kernel #37: CLK_EN 0x24 where it had been 0x14, DAPM capture path on; flashed 2026-11-02). Not on the candidate list yet: the exit condition is a regression report to the Denial project with the A5 evidence rather than a patch, not opened |
| 0029, 0030, 0032–0036 Qualcomm's kaanapali iris (VPU) series — platform data, dtsi video node, VPU4x buffer-size fixes, bus_info prefix | Qualcomm (linux-media) → mainline; carried here via infiniti-mainline and the Fedora iceland queue → Perpetua | theirs (Vikash Garodia, Jingyi Wang, Wangao Wang, Vishnu Reddy, oss.qualcomm.com — sign-offs kept); imported 2026-11-02 for VP0 (kernel #41), flashed with #42 on 2026-11-02; drop when Perpetua carries the iris support (none at b7d639cfb282) |
| 0031 board enable for the iris codec (firmware-name vpu40_2v.mbn, status okay; board dts, BSD-3-Clause) | denialwm/linux-perpetua | ours; to be offered together with the series once Perpetua takes the iris support; re-diffed for the pin bump (replayed 2026-11-02, pin moved 2026-11-03) — now just the &iris block, the head having moved the CPU thermal overrides into a shared include |
| 0043–0045 infiniti-mainline iris fixes 0069–0071 (release the MVP NoC low-power request on vpu4x, hierarchical-B only on kaanapali, no picture state on decoder input) | infiniti-mainline → mainline/Perpetua | theirs (Victor Fuentes); imported 2026-11-02 as part of the 13-patch fix set after the first VP2 firmware system error, flashed with #42; drop when Perpetua carries them |
| 0046–0055 Fedora iceland iris fixes 0157–0160, 0246–0250, 0292 (iova restrict region, capture bit-depth validation, hfi_sys_ops guard, uc_region boot failure, AHB bridge reset, power-off ordering, core lock, open limit, instance refcount, SMPTE 170M signalling) | mzak's Fedora iceland queue / linux-media → Perpetua | theirs (Vishnu Reddy, Dmitry Baryshkov, mzak; Bryan O'Donoghue's sign-offs kept); 0055 is the VUI colour fix the encode round-trip needed (VP3, #42); imported 2026-11-02, flashed with #42; drop as Perpetua picks them up |
| 0037, 0039–0042, 0063 nt36536 pen series (tablet capabilities — Fedora 0036 adapted; pen through touchscreen_report_pos; the controller's pen scanning on, 0x7F/0x10; OPP handshake plumbing, `pen_uplink`/`pen_downlink`; `pen_input` injection; vendor 0x0603 / product 0x6536 and the pen's parent device) | denialwm/linux-perpetua (drivers/input/touchscreen/nt36536) | to prepare — 0037 is mzak's with our adaptation, the rest ours; flown on #43/#44 as module swaps and in the series since #45 (0063 was renumbered from 0043 on 2026-11-03 because 0043 was already the first infiniti iris fix, was compiled into #45's module by hand and is in the series for the next build); the handshake itself is userspace (iceland-pen) and not a kernel submission |
| 0038 touchscreen-x-mm/y-mm in the controller's frame (193/274; board dts, BSD-3-Clause) | denialwm/linux-perpetua | ours; to be offered with the pen series |
| 0056–0062 pen charger (Maxic MT5806) with its prerequisites — PMH0101 level-shifter binding and regulators, pmic_glink hBoost client, MT5806 binding and driver, board DT, post-start IRQ wait for s2idle | mzak's Fedora iceland queue → Perpetua (binding and driver → mainline) | theirs (Fedora 0084/0085/0090–0093/0179; adapted: the hBoost client keyed on our compatible, 0058 re-diffed next to Xiaomi's match data and corrected on 2026-11-03 to the board's renamed compatible, which #45 had missed — pen charging dead there until build #46 and 0061 next to the head's SuperVOOC nodes at the pin bump); flown on #44 (2026-11-03, PASS — level shifters present, charger bound, the pen charges at ≈ 8 V on the magnet edge) and in the series since; the Fedora port's to submit, we carry with attribution; drop as Perpetua picks them up |
| Userspace audio (UCM2, PipeWire chain) | alsa-ucm-conf / the Fedora iceland port | after the headphone profile exists |
| PipeWire alsa-udev emits a second card object for an AudioReach card's compress node (`comprC0`), and the two contend for the ReserveDevice1 name — the loser is switched to profile off | pipewire (spa/plugins/alsa/alsa-udev.c) | to report with the 2026-11-02 debug log; our workaround is a WirePlumber rule (0.2.23) |
| WirePlumber: a card that completes during its first pass over ALSA (card complete at 8.23 s, WirePlumber's pass at 8.25 s, on every boot of #45) is never re-read for UCM, so its HiFi profile never attaches and the session has no sink — only "off" and "pro-audio" are offered | wireplumber (ALSA monitor / ACP) | to report once a minimal reproduction exists (the ordering is reproducible on this pin but not yet reduced to a test case); our workaround is the iceland-audio-check guard that restarts WirePlumber once and logs it (0.2.29), scoped to the owner's session, uid 1000–59999, in 0.2.30 |
| libwacom identifies a tablet from the udev PRODUCT property and accepts only bus 0/3/5/0x18 (`get_bus_vid_pid()`, libwacom.c), so the Pad 4's SPI-attached NT36536 (bus 0x1c) is rejected even with 0063's vendor 0x0603 / product 0x6536 | libwacom (2.18) | to propose that the SPI bus be accepted — draft in "Asks to other projects" below; our workaround is 74-iceland-pen.rules presenting the two input devices as I2C for matching only (PRODUCT=18/603/6536/0, ID_BUS=i2c) plus /etc/libwacom/oneplus-pad4.tablet (DeviceMatch=i2c|0603|6536), shipped in 0.2.29; GNOME's Graphics Tablets panel lists "OnePlus Pad 4" since 2026-11-03 |

## 0028 — ASoC: qcom: q6apm: validate READ/WRITE_DONE payloads by the fields used

Timeline. On 2026-11-02 at head `5c1eafa7b755` the bug was still present
upstream (`sound/soc/qcom/qdsp6/q6apm.c` lines 633 `sizeof(*done)` and 662
`sizeof(*rd_done)`), and this submission was prepared. Hours later the
branch gained `9ba37ef1db70` ("ASoC: qcom: q6apm: accept short read-done
responses", Doctor Logix, 2026-11-02): the READ_DONE check now reads
`offsetofend(typeof(*rd_done), buf_addr_msw)` with the comment "Kaanapali's
DSP sends 56 bytes, short of the metadata fields at the end" — the same fix
as 0028's READ_DONE hunk. The microphone regression is therefore fixed
upstream independently, and 0028's READ_DONE hunk was dropped at the pin
bump of 2026-11-03 (rung P: the pin moved from `7c98a10e6bb7` to
`b7d639cfb282`, which carries `9ba37ef1db70`; the series was replayed with
`git am -3` on 2026-11-02 and 0028 is now the WRITE_DONE hunk alone — one
file, one line; kernel #45 runs the upstream READ_DONE fix).

What upstream does not have is 0028's WRITE_DONE hunk (line 633 still asks
for the whole 32-byte struct). On the OnePlus Pad 4 the DSP sends the full
32 bytes for WRITE_DONE, so no failure has been observed from it; the hunk
is consistency, not a fix. It is prepared as a one-line patch should the
Denial project want it:

Prepared branch: `q6apm-write-done-payload-size` in the local Perpetua clone
(`/srv/ubuntu-iceland/linux-perpetua`, worktree
`/srv/ubuntu-iceland/build/perpetua-0028-upstream`), one commit on top of
`origin/perpetua/v7.3` @ `b7d639cfb282`, titled "ASoC: qcom: q6apm: validate
WRITE_DONE by the fields used, like READ_DONE", signed off. The repository
has issues enabled and had never had a pull request as of this date.

How to open it (the port maintainer's GitHub account is needed; `gh` is not
installed on the build host):

1. Fork `denialwm/linux-perpetua` on GitHub (web UI, one click).
2. `git -C /srv/ubuntu-iceland/linux-perpetua push git@github.com:<you>/linux-perpetua.git q6apm-write-done-payload-size`
3. Open the PR from that branch against `perpetua/v7.3`; the commit message
   is the PR body.

Status (2026-11-03): not opened — no pull request and no issue exist
anywhere yet; the branch waits on the port maintainer's GitHub account.

The original, fuller submission text for the READ_DONE fix is kept below
for the record (it is also the evidence trail for the bug):

### Original PR title (superseded by 9ba37ef1db70)

    ASoC: qcom: q6apm: validate READ/WRITE_DONE payloads by the fields used

### Original PR body

Perpetua commit 7c8cc30d7fc4 ("ASoC: qcom: hostless modem voice through
q6apm") added payload-size checks to `graph_callback()` that reject a
`DATA_CMD_RSP_RD/WR_SH_MEM_EP_DATA_BUFFER_DONE_V2` whose payload is smaller
than the full kernel struct. The structs carry trailing optional metadata
words (`md_*`) that the ADSP firmware on at least the OnePlus Pad 4
(iceland) does not send: every READ_DONE arrives with a 56-byte payload
against `sizeof(struct data_cmd_rsp_rd_sh_mem_ep_data_buffer_done_v2)` = 60,
so every capture completion is silently dropped. The stream reaches RUNNING,
the DSP fills and reports every buffer, but `snd_pcm_period_elapsed()` is
never called, `hw_ptr` stays at 0 and the read fails with EIO. The WRITE_DONE
path has the same over-strict check (32-byte struct with an `md_*` tail).

This is the "capture starts but no data arrives" entry in phonewave's
FEATURES.md for iceland, aston and nx809j. Upstream v7.3 has no size check
there (it requires only `ar_graph`) and reads just the leading fields, which
is why the Fedora iceland port (which does not carry 7c8cc30d7fc4) captures
fine.

Evidence (OnePlus Pad 4, perpetua/v7.3 @ 7c98a10e6bb7 + the iceland audio
queue): kprobe on `graph_callback` during `arecord -D hw:0,2` — 16/16
packets opcode 0x05001005, tokens 0–7, `payload_size` 56, handler returned
before `event_handler`. With this patch: 36/36 READ_DONE → `event_handler` →
`snd_pcm_period_elapsed`, `hw_ptr` advancing, real microphone audio; the
WCD headphone path's WRITE_DONE (payload 32) is accepted as well. Flashed and
in daily use since 2026-11-02.

The fix keeps the NULL-payload and bounds intent but only requires the bytes
the handler dereferences: `buf_addr_msw` for READ_DONE and `status` for
WRITE_DONE, via `offsetofend()`. An equivalent fix was made independently for
the nx809j in Reixo0/linux fcabe5fd25c7 ("accept read-done replies without
metadata").

Signed-off-by: John Stockdale <jstockdale@gmail.com>

### Issue text (superseded with the PR body above — the READ_DONE fix is upstream, and the linked patch file has carried only the WRITE_DONE hunk since the 2026-11-03 pin bump)

Title: q6apm: READ_DONE/WRITE_DONE payload-size checks from 7c8cc30d7fc4 drop
every capture completion on iceland (mic capture dead, hw_ptr frozen)

Body: the PR body above, plus "Patch attached / available at
github.com/jstockdale/ubuntu-oneplus-pad-4/blob/main/kernel/patches/0028-q6apm-accept-dsp-read-write-done-payload-size.patch".

## Asks to other projects

### mzakamin-hub/iceland-mainline — please state a license

Their repository declares no license. We carry, with attribution, their
Pad 4 topology overlay (under the Linaro BSD-3-Clause headers it keeps),
their UCM2 profile (adapted) and their adaptation of tb323fu-linux's
PipeWire chain. Their kernel patches are GPL-2.0 like any kernel change
and carry their sign-off, so those are fine. Draft issue text:

> Title: Could you add a LICENSE to iceland-mainline?
>
> Hi mzak — the Ubuntu port of the Pad 4
> (github.com/jstockdale/ubuntu-oneplus-pad-4) adapts a few of your
> userspace files (the AudioReach topology overlay, the UCM2 profile and
> your version of the tb323fu PipeWire speaker chain), with attribution in
> every file. Your repository has no LICENSE file, so strictly those
> pieces are "all rights reserved" and nobody can redistribute them. Would
> you consider adding one? BSD-3-Clause would match the Linaro topology
> sources you build on, MIT would match tb323fu-linux, and either is
> compatible with how the Ubuntu port (BSD-3-Clause) and Fedora packaging
> use them. Thank you for the port — the TDM speaker chain and the touch
> fixes saved weeks.

Status: not yet sent (the port maintainer's GitHub account is needed).
Note (2026-11-02 review): several of their files do carry SPDX headers
(iceland-bdaddr, iceland-provision, iceland-thermal: GPL-2.0-or-later);
anything adopted from those keeps that license per file — the request is
about the repository default and the header-less userspace files.

### libwacom — please accept the SPI bus

libwacom (2.18 on Ubuntu 26.04) identifies a tablet from the udev PRODUCT
property and accepts only bus 0, 3 (USB), 5 (Bluetooth) and 0x18 (I2C) in
`get_bus_vid_pid()` (libwacom.c). The Pad 4's Novatek NT36536 is an SPI
device (bus 0x1c), so even with 0063's vendor 0x0603 / product 0x6536 and a
parent device for the pen it was "a tablet but not supported by libwacom"
and GNOME's Graphics Tablets panel said "No tablet detected". We work
around it with 74-iceland-pen.rules, which presents the two input devices
as I2C for matching only (PRODUCT=18/603/6536/0, ID_BUS=i2c), and
/etc/libwacom/oneplus-pad4.tablet (DeviceMatch=i2c|0603|6536, integrated
display, @generic-no-eraser styli); `libwacom-list-local-devices` answers
"OnePlus Pad 4" and the panel went live on 2026-11-03 (device package
0.2.29). Draft issue text:

> Title: Accept SPI-attached tablets (BUS_SPI, 0x1c) in get_bus_vid_pid()
>
> Hi — integrated tablets on recent Qualcomm devices hang off SPI: the
> OnePlus Pad 4's Novatek NT36536 (vendor 0x0603 / product 0x6536) reports
> a pen with pressure, tilt and a barrel button over a 274×194 mm surface,
> and libinput already treats it as a tablet. libwacom only accepts bus
> 0/3/5/0x18 when it reads PRODUCT, so the device is rejected whatever the
> tablet file says. Would you accept an `spi` DeviceMatch bus (BUS_SPI =
> 0x1c) next to `i2c`? We can send the patch together with the Pad 4's
> tablet file; until then we masquerade the devices as I2C with a udev
> rule, which is what the matching needs anyway.

Status: not yet sent (the port maintainer's GitHub account is needed); the
tablet file and the udev rule ship in ubuntu-iceland-device 0.2.29.
