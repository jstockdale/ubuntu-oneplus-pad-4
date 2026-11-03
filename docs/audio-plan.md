# Audio bring-up plan (C4): the AudioReach topology, TDM speakers, six smart amps

> **Corrections from the 2026-11-02 readiness review:**
> - §2.2's table marks Fedora 0186/0187/0188/0192 (MBHC robustness) as
>   "no (headset phase)": all four are already in the Perpetua pin
>   (a715d03b1e0f, 7f6a6dfa20b1, bdb9dab399d7, e2044466fbae), as is
>   f33c93c8b81f; the headset kernel backlog is Fedora's unpublished q90w2
>   set (MG2_MISC switch register, class-H IQ, codec version after
>   SoundWire attach, bandgap fine adjust), fetched only if a real headset
>   fails to detect.
> - 0059 is marked "partial": lpass-tx-macro writes ADPT_CTRL=0 at decimator
>   POST_PMU (Perpetua f690330c9187) and the live regmap shows DEC0/DEC1 at
>   0x00 — complete. Mic noise floor measured 2026-11-02: 1 s-window median
>   −61.4/−60.7 dBFS (min −63.2/−61.9) vs Fedora's −64 — parity.
> - The wired-headphone "4 periods then EIO" is starvation with no jack
>   detected (common.c ties the HPH DAPM pins to the jack), not a bug; the
>   Pad 4 has no 3.5 mm jack, the path needs a USB-C analog headset. Neither
>   our UCM nor Fedora's public one has a Headphones device; alsa-ucm-conf
>   ships codecs/wcd939x/Headphone*Seq.conf to build one from.
> - Open question 5 (which USB-C analog headset) is still open; it is now
>   the only blocker for the headphone rung.
> - BT: the controller broadcasts the board file's placeholder
>   AD:5A:00:00:00:25; persist has no bluetooth directory on this unit.
>   libspa-0.2-bluetooth is not installed (A2DP/HFP need it).

Date: 2026-11-01 (research night; flights when C4 opens). Companion to
docs/porting-log.md (:981-986, the C4 doorbell) and docs/firmware-manifest.md
("Audio: LPASS topology + UCM2 profiles — C4").

Problem: the audio module stack coldplugs cleanly (the 2026-10-31 parade walked
it end to end, porting-log :640-650), the ADSP is up (battmgr lives on it), the
sound card driver binds — and the card fails to instantiate with **-2** because
q6apm requests a topology file that exists nowhere in our firmware set:
`qcom/kaanapali/OnePlus-Pad4-tplg.bin`. This plan answers where that file comes
from, what else is missing behind it, and how to fly the fix without cooking
six speaker voice coils.

File:line references: ours against `/srv/ubuntu-iceland/linux-perpetua` at
`7c98a10e6bb7` (perpetua/v7.3; identical content in the build worktree) and
`/srv/ubuntu-iceland/build/linux-iceland/.config`; theirs against fresh clones
in the session scratchpad (`scratchpad/repos/`):

- `github.com/mzakamin-hub/iceland-linux` @ `c060e3b` (queue **q90x**, base
  v7.3-rc7 `24a19b953e2a` per kernel.pin)
- `github.com/mzakamin-hub/iceland-mainline` @ `a7aab9f` (userspace; audio/ dir)
- `github.com/mzakamin-hub/iceland-firmware` @ `6fdbbe3` (11.A.38-6)
- `github.com/denialwm/phonewave` @ `b54e378` (Arch runtime on the denialwm
  devicesN kernels — our kernel's own lineage)

Everything marked **[verified]** was read from the named file tonight;
**[inferred]** is reasoned, not observed.

---

## Safety rails (verbatim, non-negotiable)

- **RAM boots only** — every flight is `fastboot boot` of a diag/bundle image.
- **Nothing flashed. No vbmeta / dtbo / vendor_boot / GPT writes. No
  `fastboot set_active`. No EDL. Ever.**
- **Single variable per flight.**
- **Diagnostic kernels build no modules** — the audio stack is entirely `=m`,
  so every kernel rung here is a *bundle* flight: `make modules` + hand-install
  into the running rootfs with a matching release string, DT changes ride the
  RAM-booted image.

Audio-specific rails (hard rules of this plan, §5 has the reasoning):

- **A1. No TFA9865 register is ever written above its stock-container value.**
  The only register sources allowed are our own extracted
  `odm:/firmware/tfa98xx.cnt` (sha256 `9ef2463d…`, Appendix B) and the Fedora
  patches that transcribe it (0046/0104/0290). Nothing hand-tuned upward.
- **A2. Three gain ceilings are in force before anything audible**: topology
  `VOL_CTRL_MAX` at **2056 (-12 dB)** for the whole bring-up, the kernel
  volume clamp (their 0051) in the same bundle, and the UCM pin. The raise to
  8192 (0 dB = stock's own stream ceiling) is the **last** rung, only after the
  PipeWire limiter chain is proven to be the default sink.
- **A3. First sound is one second, -30 dBFS, 440 Hz, speakers only, hand on
  the chassis.** No `speaker-test`, no full-scale content, no music before A7.
- **A4. Stop conditions**: audible distortion or clicks, any amp whose
  MANSTATE won't reach operating, repeated MANSCONF self-clears, any warm
  speaker region. Stop, dump the six regmaps, analyze on the host.
- **A5. Wipe `/var/lib/alsa/asound.state` after every topology change** and
  never leave BE routes enabled unattended — a stale saved state routing a
  front end into a graph the ADSP can't open kills card startup for every
  stream (Fedora's pc-026 S12 lesson, §2.4).
- **A6. The stock ADSP image is never modified**; we fly the same
  `adsp.mbn` we already ship (byte-identical to the Fedora port's, §1.5).

---

## 1. Current evidence on our build

### 1.1 The fail mode **[verified]**

`audioreach_tplg_init()` builds the name from the card:
`"qcom/%s/%s-tplg.bin"` ← `card->driver_name` + `card->name`
(sound/soc/qcom/qdsp6/topology.c:1415-1443; the dev_err at :1431 is the
observed line, `ret` -2 = request_firmware ENOENT). Driver name is
`"kaanapali"` (sc8280xp.c:532-533, matched via `qcom,kaanapali-sndcard` at
:641), card name is the DT `model = "OnePlus-Pad4"` (dts:250) →
**`qcom/kaanapali/OnePlus-Pad4-tplg.bin`**. It is requested by the q6apm
*component* probe (q6apm.c:907), so the card fails before any FE PCM exists:
exactly the porting-log :981-986 symptom. In the AudioReach design the
topology is not calibration garnish — it *defines* the front-end PCMs and the
DSP graphs; no topology, no card.

### 1.2 What the DT declares **[verified]**

`arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts`:

- Sound card (:245-308): `compatible = "qcom,kaanapali-sndcard",
  "qcom,sm8450-sndcard"`, `pinctrl-0 = <&i2s0_default>` (:247; TLMM gpio122+
  `i2s0_*` functions, :1418+), `model = "OnePlus-Pad4"`, audio-routing for
  HPH + AMIC1/AMIC5 + three TX SWR inputs.
- Three BE links: **`primary-i2s-dai-link` on `PRIMARY_MI2S_RX` feeding all
  six amps** (:259-275) — this is the pre-Fedora-0038 state and is wrong, see
  §2.3 —, WCD playback on `RX_CODEC_DMA_RX_0` (:277-291), WCD capture on
  `TX_CODEC_DMA_TX_3` (:293-307).
- **Six Goodix TFA9865 smart amps**, compatible `goodix,tfa9865-iceland`,
  three per bus (i2c0 = left side :913-942, i2c22 = right side :950-978),
  addresses 0x34/0x36/0x37 each, per-amp reset GPIOs (Appendix A), vddio from
  `vreg_l15b_1p8`, `tfa,devindex` 0-5, prefixes TopLeft/BottomLeft/MiddleLeft/
  TopRight/BottomRight/MiddleRight. Note at :916: downstream swapped the TL
  reset between the buses; our DT already carries the corrected wiring.
- **WCD9395** (`wcd939x`, :321-347): reset tlmm161, micbias set, MBHC
  thresholds, rx/tx SoundWire devices (`wcd_rx` codec@0,4 :1304, `wcd_tx`
  codec@0,3 :1324), plus `wcd_usbss` type-C mux for the analog headset path
  (:984-1006).
- ADSP remoteproc enabled with our firmware names (:1257-1262). dtsi:
  GPR node `qcom,intents = <512 20>` (kaanapali.dtsi:3297-3301), ADSP region
  0x4c00000 (:511-513) — both differ from Fedora, §3.

### 1.3 Driver state in our tree **[verified]**

- `sound/soc/codecs/tfa9865.c` (map220v, 587 lines): a **register-table
  bring-up driver**. It identifies the part (TFA9864/9865 N/MN via hidden-key
  unlock), writes fixed "optimal settings", then the per-board iceland tables
  (:103-177) and registers a stereo DAI. **No firmware/container load, no
  calibration, no protection model, no TDM slot programming beyond
  slot-length/sample-size from stream width** (:280-289). The iceland tables
  still program the 2-slot I2S-era frame (`0x20 = 0x0021/0x0001`) — their 0046
  replaces exactly this (§2.3).
- Machine driver `sc8280xp.c`: perpetua already absorbed the infiniti MI2S
  work (`cbe9370819f0` MI2S bclk on kaanapali, `3d56ad997ffe` 32-bit MI2S) and
  has generic TDM hw_params with DT `dai-tdm-slot-*` parsing
  (`a689ee3bad03e`/`8593dc5f052e`; sc8280xp.c:110-151, :306-307). The BE
  fixup still forces 48k/S16/2ch with only an MI2S S32 exception (:230-247) —
  no TDM case.
- `q6apm.c` already sends APM commands from the APM's GPR port
  (`pkt->hdr.src_port = gdev->svc.id`, :33-43, "Some ADSPs answer only the
  port the APM service is registered on") — the infiniti 0111 fix is in.
- audioreach.h knows I2S/CODEC_DMA/DISPLAY_PORT/AUDIO_IF endpoint modules
  (:23-40) — **no classic TDM module**. Default channel maps stop at 4
  channels (audioreach.c:340-354). `q6tdm_ops` has `set_tdm_slot` but no
  `set_channel_map` (q6apm-lpass-dais.c:455-461). q6prm has no TDM bit-clock
  ids (q6prm-clocks.c / q6prm.h).

### 1.4 Kernel config **[verified]** (/srv/ubuntu-iceland/build/linux-iceland/.config)

The config is NOT the gap. Present as `=m`: SND_SOC_QCOM, SND_SOC_QDSP6\*
(APM/PRM/common), SND_SOC_SC8280XP (the machine driver), SND_SOC_TOPOLOGY=y,
SND_SOC_TFA9865, SND_SOC_WCD939X(+\_SDW), SND_SOC_LPASS\_{RX,TX,VA,WSA}\_MACRO,
SOUNDWIRE_QCOM, PINCTRL_SM8650_LPASS_LPI, QRTR; `CONFIG_QCOM_APR=y` (carries
GPR). Matches Fedora's intent (their configs force only
`CONFIG_SND_SOC_TFA9865=m` on top of defaults, iceland-linux
configs/required.config:14). The whole set is in the diag-flight blacklist
(scripts/make-diag-bootimg.sh:123), so flights can hand-load it in order.

### 1.5 Stock artifacts on disk **[verified]**

- ACDB (the values the topology must reproduce):
  `stock/vendor-extracted/etc/acdbdata/canoe_mtp/MTP_acdb_cal.acdb` + `.qwsp`
  (canoe = the kaanapali board family; our dtbo names the board
  "Canoe MTP,iceland").
- Amp container: `odm.img:/firmware/tfa98xx.cnt`, extracted tonight to the
  session scratchpad via `dump.erofs --cat` — 3702 bytes, sha256
  `9ef2463d519688f3fbc85050cceb8c0e04d1e4fd100a455abb329c6223d8da2d`,
  PM3 container, OPPO/TFA, **6 devices, "TFA9865MN1A3_dummy.patch"** — i.e.
  register profiles only, no DSP blob. This is the provenance source for every
  amp register the port writes, and the proof the TFA9865 here is a DSP-less
  part (§5.1).
- Our shipped `adsp.mbn` (sha `781512db…`) is **byte-identical to the Fedora
  port's** (iceland-firmware MANIFEST.tsv, same hash, source
  `modem_a:/image/adsp.mdt` squashed) — their topology ran against exactly our
  ADSP build, so their module-ID/behavior findings transfer 1:1. `adsp_dtb.mbn`
  matches too (`09e35c42…`), on all three ports (phonewave verifies the same
  hash in pad4-audio-init.rs).

---

## 2. What the Fedora port does, file by file

### 2.1 The topology answer **[verified]**

**`OnePlus-Pad4-tplg.bin` is not shipped, not extracted — it is BUILT at
package build time** from BSD-3-Clause sources:

> iceland-device.spec:437-440 — "the Pad 4 AudioReach topology: upstream m4 +
> our overlay (TDM speakers, capped stream gain)":
> `cp -a audio/topology/. audioreach-topology/` then
> `m4 -I . OnePlus-Pad4.m4 > OnePlus-Pad4.conf && alsatplg -c OnePlus-Pad4.conf -o OnePlus-Pad4-tplg.bin`
> followed by the build gate `grep -q 'max "8192"' …OnePlus-Pad4.conf`.

- Upstream base: **`github.com/linux-msm/audioreach-topology` pinned at
  `993a17d`** (spec:80-81, Source20; verified on GitHub: merge "glymur: Add
  Asus Zenbook A14", full hash `993a17dcb672357998a463a73f120064d6c74f4f`).
  BSD-3-Clause, Copyright Linaro 2021-2024; the same project linux-firmware
  builds its shipped `*-tplg.bin` from for x1e80100/sm8550 boards
  (WHENCE: "Redistributable", LICENCE.linaro). No kaanapali board upstream yet.
- Their overlay: `iceland-mainline/audio/topology/OnePlus-Pad4.m4` plus six
  overlay modules under `audio/topology/audioreach/`:
  `module_tdm.m4`, `module_vol_ctrl_capped.m4`, `module_audio_if.m4`,
  `subgraph-device-tdm-playback.m4`, `subgraph-stream-vol-playback-capped.m4`,
  `subgraph-compress-stream-vol-playback-capped.m4`, `tokens.m4`.
- Installed to `/usr/lib/firmware/qcom/kaanapali/OnePlus-Pad4-tplg.bin`
  (spec:470, %files :890).

Topology content (OnePlus-Pad4.m4) **[verified]**:

- FEs: MultiMedia1/2 PCM playback + MultiMedia5 compress (all through the
  **capped** stream-volume subgraph), MultiMedia3/4 capture, MultiMedia6 → DP.
- BEs: `PRIMARY_TDM_RX_0` (speakers), `RX_CODEC_DMA_RX_0` (WCD playback),
  `TX_CODEC_DMA_TX_3` (WCD capture), `VA_CODEC_DMA_TX_0`,
  `WSA_CODEC_DMA_RX_0` (inherited, unused on this board), `DISPLAY_PORT_RX_0`.
- The speaker device subgraph is **[MFC] → [LOG] → [classic TDM SINK]**
  (subgraph-device-tdm-playback.m4). The MFC converts 2ch/16-bit stream to the
  8ch/32-bit endpoint; "Without it the sink consumed the 2-ch/16-bit stream as
  8-ch/32-bit frames — 8x faster than real time, and nothing audible"
  (their pc-026 S13; iceland-mainline commit `f64673c`).
- TDM endpoint values, "every value below is the stock ACDB's for this
  endpoint": 8 slots × 32 bit, 48 kHz, internal (LPASS) sync source, data-out
  enable, slot mask 0xff, long sync mode, no inversion, 1-cycle data delay.
- `VOL_CTRL_MAX = 8192` (Q13 linear, 8192 = 0 dB = stock's PAL stream
  ceiling; raised 11 Oct 2026 from the **-12 dB bring-up placeholder 2056**
  once the PipeWire chain existed — the history is in the m4 header comment).

### 2.2 Their kernel patch chain **[verified]**, with our status

PORT-LOG.md "The speaker chain (0038-0050)" documents it link by link; the
patch files confirm. Status = content-checked against our pin tonight.

| Patch (iceland-linux) | What it does | In perpetua @7c98a10e? |
|---|---|---|
| 0002-iceland/0014 TFA9865 driver | base register-table driver | **yes** (our tfa9865.c, same lineage) |
| 0015 sound nodes | card + amps + wcd DT (MI2S era) | **yes** (our :245-308 is this state) |
| 0038 speakers on the primary TDM port | BE link → `PRIMARY_TDM_RX_0`, `dai-tdm-slot-num 8 / width 32 / masks 0xff`; "the mainline DT used Primary MI2S, which the amplifiers never sync to" | **no** |
| 0041 audioreach classic TDM endpoint | adds `MODULE_ID_TDM_SINK/SOURCE` 0x0700100E/F + `PARAM_ID_TDM_INTF_CFG` 0x0800101B; **the stock ADSP has no Audio-IF (QAIF) module** — an AUDIO_IF topology fails `APM_CMD_GRAPH_OPEN` with AR_EFAILED; also surfaces GRAPH_OPEN failures | **no** (audioreach.h:23-40) |
| 0042 q6prm TDM bit clocks | clock ids 0x200-0x209 + table entries | **no** |
| 0043 DT: vote the primary TDM bclk | `q6apmbedai` dai@18 subnode, `clocks = <&q6prmcc LPASS_CLK_ID_PRI_TDM_IBIT …>`, "bclk"; machine driver sets 8×32×48k = 12.288 MHz | **no** |
| 0044 sc8280xp TDM BEs at 32 bit / 8 ch | BE fixup case `PRIMARY_TDM_RX_0…`: S32_LE, channels 8; FEs stay S16 stereo, DSP widens | **no** (our fixup :230-247 lacks it) |
| 0045 default 6/8-channel maps | audioreach_set_default_channel_mapping | **no** (ours stops at 4, audioreach.c:340-354) |
| 0046 tfa9865 stock TDM setup | per-amp `0x20=0x6f91` + slot regs 0x21/0x22 from the stock container (values in Appendix A); old tables were the silent "clock out of range, manager state 1" cause | **no** |
| 0047 tfa9865 MANSCONF after every power-up | manager waits in state 1 until MANSCONF; chip self-clears it on frame mismatch | **no** |
| 0048 TDM ports accept a channel map | `set_channel_map` on q6tdm_ops | **no** (:455-461) |
| 0049 spread stereo over the six amps | `oneplus,iceland-sndcard` card data; prepare() sets channel map **FL FR FL FR FL FR FL FR**; left = slots 0/2/4 (i2c0), right = 1/3/5 (i2c22); with the default map only slots 0/1 played — four amps silent | **no** |
| 0050 DT: use the Pad 4 card | compatible → `"oneplus,iceland-sndcard","qcom,kaanapali-sndcard","qcom,sm8450-sndcard"` | **no** |
| 0051 volume control within the topology max | clamp writes (EINVAL above max) AND clamp the power-up/default gain — unity default would bypass a lower cap | **no** |
| 0104 charge-pump divider + sense map from stock | 0x62 low nibble 4, 0x68=0x0914 | **no** |
| 0290 middle amps' gain/boost from stock | 0x37 pair: 0x5f atten 5, 0x76 boost 0xf0 ("nothing is raised past stock") | **no** |
| 0052 WCD939x TX gain scale 1.5 dB/step | measured on the Pad 4 | **yes** (wcd939x.c:221) |
| 0059 tx-macro: disable decimator ADPT block | noise floor -47 → -64 dBFS on this device | **partial** (regmap defaults only, no power-up write; lpass-tx-macro.c:191,441-448) |
| 0184 soundwire port-count log fix | cosmetic (two bogus errors/boot) | **no** |
| 0186/0187/0188/0192 wcd/MBHC fixes | headset-jack robustness | **no** (headset phase) |
| 0194 ADSP remote-heap no-map | fastrpc-vs-CMA; relevant once linux-next `9981fbe599e8` lands | **no** |
| 0201 q6apm: clear g_apm on removal | UAF on unbind (Qualcomm patch) | **no** |
| 0001-infiniti/0109 apr: register GPR callback before probing | q6apm's probe-time sync command response was dropped → +5 s boot | **no** (apr.c:382-391 sets callback after probe) |
| 0110 q6apm-dai S32_LE | FE formats | superseded (our q6apm-dai-driver.c; FEs stay S16 anyway) |
| 0111 send commands from the APM's GPR service | kaanapali ADSP answers only the registered port | **yes** (q6apm.c:33-43) |
| 0112/0113 MI2S bclk + 32-bit MI2S | infiniti speakers (TFA9866/MI2S) | **yes** (`cbe9370819f0`, `3d56ad997ffe`) |
| 0130 ADSP reserved memory 0x5000000 | "the signed ADSP image spans 0x5000000" | **no** (ours 0x4c00000 — yet our ADSP boots; parity item) |
| 0131 1024-byte GPR intent | "some ADSP responses exceed 512 bytes" | **no** (ours `<512 20>`) |

### 2.3 UCM2 **[verified]** (iceland-mainline/audio/ucm/OnePlus-Pad4/)

Installed as `/usr/share/alsa/ucm2/Qualcomm/kaanapali/OnePlus-Pad4/
{OnePlus-Pad4.conf,HiFi.conf}` with symlink
`ucm2/conf.d/kaanapali/oneplus-OnePlusPad4.conf` (spec:471-474). Card id
"OnePlusPad4", long name "oneplus-OnePlusPad4".

- **FixedBootSequence** (run by alsactl before WirePlumber sees the card):
  turns the speaker and mic BE routes on — WirePlumber's ACP must be able to
  *open* the DPCM front ends or it drops the whole HiFi profile to Dummy
  Output (their pc-026 S10); sets the stream gain to **2056** so raw ALSA
  users get the cap too; and forces `RX_CODEC_DMA_RX_0 / WSA_CODEC_DMA_RX_0
  Audio Mixer MultiMedia1` **off** — a saved asound.state once routed MM1 into
  graphs the ADSP cannot open (`graph 113, AR_ENOTEXIST`) and every MM1
  prepare failed (pc-026 S12). That hazard is our rail A5.
- **HiFi.conf**: Speaker device pins
  `cset "name='stream0.vol_ctrl0 MultiMedia1 Playback Volu' 8192"` (control
  name truncated by ALSA; 8192 = the topology cap), `PlaybackPCM hw:…,0`;
  deliberately **no PlaybackMixerElem** — the control's dB metadata is wrong
  (1 dB/step), so PipeWire keeps a software volume on top of the pinned DSP
  gain. phonewave reaches the same end differently:
  `api.alsa.soft-mixer = true` on the card
  (devices/iceland/rootfs/etc/wireplumber/wireplumber.conf.d/51-pad4-audio.conf).
  Mic device: AMIC1 (bottom) → ADC1 → SWR_MIC0/DEC0, AMIC5 (back) → ADC2 →
  SWR_MIC1/DEC1, `ADC1/2 Volume 14` (stock's recorder path; 0 is mute on this
  TLV), `TX_DEC0/1 Volume 84` (stock's 0 dB; their 98-experiment clipped the
  echo path — comments carry the full story), `CapturePCM hw:…,2`.

### 2.4 Speaker protection: a userspace chain **[verified]**

`packaging/iceland-device/files/62-iceland-speakers.conf` (adapted from
tb323fu-linux, MIT): PipeWire filter-chain sink "Speakers" in front of the UCM
sink `alsa_output.platform-sound.HiFi__Speaker__sink` —
**high-pass 150 Hz (4th order)** → stock-tone EQ (cuts only, fitted to a
LineageOS-with-vendor-DSP sweep reference) → **SC4 compressor** (2.5:1 over
-24 dBFS, +9 dB make-up) → **fast look-ahead limiter at -1 dBFS** (LADSPA
`sc4_1882` + `fast_lookahead_limiter_1913`, Fedora pkg ladspa-swh-plugins ≈
Ubuntu `swh-plugins` 0.4.17, universe). Fail-safe `ifexists nofail`; the raw
ALSA sink stays visible as "Speakers (raw, unprotected)" demoted by
`62-iceland-speaker-raw.conf`; `iceland-speaker-default` (systemd user side)
makes the filtered sink the default. The governing rule, written into the
file: **"never LOUDER than stock's measured loudness"** — every DSP/amp stage
stays at stock, the chain only shapes and limits, make-up gain is capped by
the measured gap to stock.

So the protection path on this port is **userspace (PipeWire), with kernel
backstops** (topology cap + 0051 clamp + stock amp registers). There is no
kernel or ADSP excursion model — see §5.1.

### 2.5 Proof of life + sequencing **[verified]**

iceland-mainline history: `e117ce5` "the speakers play: classic TDM sink, PRM
bit clock, stock endpoint format" → `d558c01` "UCM profile …; PipeWire drives
the speakers and the mics" → `3a3406e` "cap the speaker gain (kernel +
topology + UCM)" → `7afe472` (S12 stray-route fix) → `f64673c` (MFC) →
`3cf084f`/`39c1cd6` (mic gains at stock; "microphone fixed"). PORT-LOG:
area-audio-1, 2026-09-29 — "all six amplifiers engage on stereo, each side
exactly its three". phonewave gates audio in production the same way we will:
`pad4-audio-init` hash-verifies adsp + **its own shipped
OnePlus-Pad4-tplg.bin** (sha `11b78ff1…` — provenance unknown, open question
Q1), modprobes snd-q6apm/q6apm-dai/q6apm-lpass-dais/q6prm-clocks/
snd-soc-sc8280xp, then polls `/proc/asound/cards` for "OnePlus-Pad4" with a
30 s deadline (tools/pad4-audio-init.rs).

---

## 3. Gap analysis, ours vs theirs

| Layer | Theirs | Ours today | Gap |
|---|---|---|---|
| Topology binary | built from linux-msm/audioreach-topology@993a17d + overlay, installed under qcom/kaanapali/ | **absent** (the -2) | A0/A1 |
| Kernel: TDM endpoint module, PRM TDM clocks, BE fixup, 6/8 chmaps, TDM set_channel_map, Pad4 card+chmap spread, GRAPH_OPEN reporting | 0041/0042/0044/0045/0048/0049 | all missing | A2 |
| Kernel: TFA9865 TDM regs, MANSCONF, charge pump/sense, middle amps | 0046/0047/0104/0290 | missing (our tables are the silent I2S-era set) | A2 |
| Kernel: volume clamp | 0051 | missing | A2 (safety-relevant) |
| DT: TDM BE link + slots, bclk vote, card compatible | 0038/0043/0050 | MI2S link, no vote, kaanapali compatible | A2 |
| Kernel: GPR plumbing | 0109 callback order, 0111 src_port, 0131 intents 1024, 0130 adsp mem | 0111 **in**; 0109/0130/0131 missing | A8 parity batch (not gating: our ADSP boots and q6apm reaches the tplg request) |
| Mic quality | 0052 gain scale, 0059 ADPT disable | 0052 in; 0059 partial | 0059 rides A2's bundle, gated at A5 |
| Headset jack | 0186-0192 MBHC set + usbss | missing | A8 |
| UCM2 | Qualcomm/kaanapali/OnePlus-Pad4 + conf.d link | none | A4 |
| PipeWire protection chain + default-sink unit + soft volume | 62-iceland-speakers.conf etc. | none (rootfs doesn't even have pipewire yet — 354-package base) | A6 |
| Housekeeping | 0184 swr log, 0194 heap no-map, 0201 g_apm | missing | A8 |
| Config | required.config TFA9865=m | **parity** (§1.4) | none |
| ADSP firmware | stock 11.A.38 adsp.mbn `781512db…` | **identical bytes** | none |

---

## 4. The ladder — one flight per rung, every rung with a gate

Patch numbering: ours continue at `kernel/patches/0011-…`. Kernel rungs are
bundle flights (rail: diag kernels build no modules): build via
`scripts/build-mainline-kernel.sh` with patches applied, `make modules` +
hand-install to `/lib/modules/$(uname -r)` on the tablet, DTB inside the
RAM-booted image. The audio modules are in the diag blacklist
(make-diag-bootimg.sh:123) so load order is ours on flights.

**A0 — build the topology on the host (no tablet).**
Clone `linux-msm/audioreach-topology`, `git checkout 993a17d`; copy the
mzakamin overlay (`iceland-mainline/audio/topology/`, 8 files, Appendix B)
on top; **set `VOL_CTRL_MAX` to `2056`** in OnePlus-Pad4.m4 (their own
bring-up placeholder; the 8192 raise is A7);
`m4 -I . OnePlus-Pad4.m4 > OnePlus-Pad4.conf && alsatplg -c OnePlus-Pad4.conf -o OnePlus-Pad4-tplg.bin`
(host has alsatplg 1.2.15/m4 **[verified]**). Bank in
`out/rootfs-overlay/lib/firmware/qcom/kaanapali/` + record sha256, source and
license in firmware-manifest.md (BSD-3-Clause: keep LICENSE text + m4
headers; linux-firmware ships sm8550/x1e80100 equivalents as
"Redistributable, LICENCE.linaro" — precedent for shipping the binary).
*Gate G-A0*: alsatplg exits 0; `grep 'max "2056"' OnePlus-Pad4.conf` hits;
manifest row written. Compare sha against phonewave's `11b78ff1…` (Q1).

**A1 — stage the topology alone (no kernel change, current MI2S DT).**
One variable: the file appears. scp to
`/lib/firmware/qcom/kaanapali/OnePlus-Pad4-tplg.bin`, remove
`/var/lib/alsa/asound.state` (rail A5), reboot the release system (or
re-coldplug the audio set on a diag boot).
*Gate G-A1*: dmesg has **no** "tplg firmware loading … failed -2";
`/proc/asound/cards` lists `OnePlus-Pad4`; `aplay -l` shows the MultiMedia
FE PCMs; `arecord -l` shows capture. Expect dangling-route warnings for
DISPLAY_PORT/WSA widgets (no such BE links in our DT) — record them (Q2).
**No playback this flight** — the MI2S speaker link cannot sync the amps
(their 0038 text) and must not be fed.

**A2 — the TDM speaker chain as one unit (kernel+DT bundle, no sound).**
Adopt, as our 0011-0025 (15 patches), their 0041, 0042, 0044, 0045, 0046,
0047, 0048, 0049, **0051 (the clamp — same bundle as the first TDM card,
rail A2)**, 0104, 0290, 0059 (capture-only rider, gated at A5), plus DT
0038+0043+0050.
This is one functional variable — "the Fedora TDM speaker chain", flown the
way their port proved it; splitting it yields only guaranteed-silent flights.
Diff our tfa9865.c against their final first (0014+0046+0047+0104+0290) and
transcribe exactly.
*Gate G-A2* (still silent): card instantiates on the TDM DT; dmesg shows six
`Found TFA9865 MN1`; `amixer -c OnePlusPad4 cset name='stream0.vol_ctrl0 MultiMedia1 Playback Volu' 8192`
**fails with EINVAL** (clamp + 2056 cap proven live); all
`… Audio Mixer MultiMedia1` routes read 0.

**A3 — first sound (the guarded flight).**
Preconditions checked on the wire: cap 2056 in `/proc/asound/…` controls,
routes off, hand on chassis. Then:
`amixer -c OnePlusPad4 cset name='PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1' 1`;
generate 1.0 s of -30 dBFS 440 Hz (sox/python, 48 kHz S16 stereo);
`aplay -D plughw:OnePlusPad4,0 tone.wav`; route back off.
*Gate G-A3*: tone audible from **both** sides at low level; during playback
each `/sys/kernel/debug/regmap/{0-0034,0-0036,0-0037,22-0034,22-0036,22-0037}/registers`
reg 0x12 low nibble (MANSTATE) reads operating (9), not 1; no distortion;
chassis cool. Any miss → rail A4 stop. (Regmap reads are plain I2C — safe;
never devmem LPASS MMIO, the TLMM/XPU lesson from wifi-plan generalizes.)
Optional same-flight bonus after the gate passes: per-side check by muting
one `TopLeft/...` route if exposed, else skip.

**A4 — UCM + PipeWire + GNOME.**
Userspace only: extend `packaging/ubuntu-iceland-device` with the two UCM
files (adapted verbatim from theirs; install under
`/usr/share/alsa/ucm2/Qualcomm/kaanapali/OnePlus-Pad4/` + real file in
`ucm2/conf.d/kaanapali/oneplus-OnePlusPad4.conf` — Ubuntu alsa-ucm-conf
1.2.15 supports Syntax 4/FixedBootSequence), a wireplumber drop-in with
`api.alsa.soft-mixer = true` (phonewave precedent, dodges the broken dB
metadata), and deps pipewire/wireplumber/alsa-ucm-conf. Keep the UCM Speaker
pin at **2056** for now (differs from their final 8192 — ours rises at A7).
*Gate G-A4*: `alsaucm -c OnePlusPad4 list _verbs` shows HiFi; `wpctl status`
shows the Speaker sink and Mic source (no "Dummy Output" — if Dummy, check
FixedBootSequence ran: the S10 failure mode); GNOME Settings → Sound test
plays Front Left / Front Right audibly; `pactl list sinks` volume moves are
software-side while the DSP control stays pinned.

**A5 — microphones.**
Already carried: 0052 (in-tree), 0059 (A2 bundle), UCM Mic device (A4).
*Gate G-A5*: `arecord -D hw:OnePlusPad4,2 -f S16_LE -r48000 -c2 -d3 m.wav`
captures speech on both channels (bottom mic ch0, back mic ch1); GNOME input
meter follows; quiet-room noise floor ≈ -60 dBFS or better (their measured
-64 with ADPT off vs -47 without — this validates the 0059 rider).

**A6 — the protection chain.**
Install `swh-plugins`; port `62-iceland-speakers.conf` (+ raw-sink demotion +
default-sink user unit) with `target.object` matching our UCM sink name
(`alsa_output.platform-sound.HiFi__Speaker__sink` — same card/UCM names, so
same string; verify with `pw-cli ls Node | grep alsa_output`). Cap still 2056.
*Gate G-A6*: "Speakers" filter sink exists and is the default; playing the
GNOME sound test shows the chain active (`pw-top` lists the filter-chain
nodes; raw sink demoted); pulling `swh-plugins` out in a bench test only
drops the filtered sink (ifexists/nofail fail-safe works) — then reinstall.

**A7 — raise the ceiling to stock (the last gain change).**
Rebuild the topology with `VOL_CTRL_MAX 8192`, set the UCM Speaker pin to
8192, redeploy both together (they are one variable: "stock ceiling"). Their
build gate becomes ours: `grep 'max "8192"' OnePlus-Pad4.conf`.
*Gate G-A7*: writes above 8192 still EINVAL; an A/B loudness check against a
stock-Android reference recording of the same content is **not louder than
stock** (their owner rule; a phone SPL meter at fixed distance is enough
fidelity); limiter confirmed in-path during the test. This closes C4's core:
PipeWire playback + mic + UCM in GNOME at stock loudness, protected.

**A8 — parity backlog (next kernel refresh, not flights).**
0109 (GPR callback before probe: kills a 5 s boot stall), 0131 (1024-byte
GPR intents), 0130 (ADSP region 0x5000000), 0201 (g_apm UAF), 0184 (swr port
log), 0186-0192 + usbss work (USB-C analog headset + MBHC — new gate: plug
detection in GNOME), DP audio when DP lands (their 0134 adds the BE link;
topology MM6 path already carried), 0194 (heap no-map, pre-req for future
fastrpc backports).

---

## 5. Risks and rails

### 5.1 The amps are the one way to break hardware — why and how we don't

**[verified]** The TFA9865 is a DSP-less smart amp: the stock container holds
only register profiles ("dummy" patch entries, §1.5), and stock Android runs
the excursion/thermal protection model **on the ADSP** (the sense-data TDM
return slots the container maps — regs 0x21/0x22 high fields, 0x68 — feed it).
Our mainline graph has **no such module**; the chip's own last-ditch hardware
protections (OCP/OTP/UVP, clip control) plus the stock boost/attenuation
registers are all that exist below userspace. Therefore:

- The **PipeWire chain is the protection layer**, and the kernel's role is to
  make its bypass harmless: topology cap + 0051 clamp + UCM pin keep even raw
  `aplay` users at or below stock's stream ceiling, and the amp registers
  (0046/0104/0290 = stock container values, rail A1) keep per-amp gain, boost
  and limiter behavior at stock. Stock's own PAL never exceeds unity on a
  stream (their m4 header), so "everything at stock + peaks ≤ -1 dBFS" cannot
  out-drive what Android drives. The ladder keeps -12 dB of margin on top of
  that until the chain is proven (A2→A7 ordering is the rail).
- A **wrong topology** mostly fails safe here (silence: graph rejected, amps
  can't lock) — the dangerous wrong topology is one whose speaker subgraph
  *omits the capped vol_ctrl* or feeds the TDM sink from an uncapped FE.
  Rail: only the two capped stream subgraphs ever route to
  `PRIMARY_TDM_RX_0`; any topology edit re-runs the `grep max` gate.
- **Register-table discipline**: 0290's own commit line is the standard —
  "nothing is raised past stock". Any future tuning (EQ taste etc.) happens in
  the PipeWire chain (cuts and limited make-up), never in amp registers or DSP
  gain.

### 5.2 Everything else

- **Silent-failure debugging order** (from their chain, §2.2): card up but no
  sound → check MANSTATE (amps not locking = TDM frame/regs), then the MFC
  ("8x too fast" = stream format vs endpoint), then routes/chmap (four amps
  silent = default map). Each has a distinct signature; don't shotgun.
- **ADSP interaction**: graph opens can fail (AR_ENOTEXIST/AR_EFAILED) without
  harming the DSP; PDR restarts the audio PD. Battery telemetry shares the
  ADSP — if battmgr ever hiccups during audio flights, land and compare notes
  with the C-phase PM crowd before re-flying. RAM boots make every mistake
  recoverable; nothing here writes flash.
- **asound.state** poisoning (S12): rail A5; also ship the FixedBootSequence
  route-offs exactly as theirs so a stray state can't wedge WirePlumber.
- **GPR intents 512 vs 1024** (their 0131): if A2/A3 logs show missing GPR
  responses or stalls on big graphs, this is the first suspect — cheap DT
  bump, but it waits for evidence (one variable).
- **Boot-time 5 s stall** (their 0109) will appear once audio coldplugs with
  topology present; cosmetic until A8 — don't mistake it for a hang.
- **Ubuntu packaging drift**: swh-plugins is universe; pin it as a device-deb
  dependency so an image rebuild can't silently drop the limiter (the chain
  fails safe to the raw sink, but then the raw sink is default — exactly the
  state A6 exists to prevent; consider shipping the raw-sink demotion even
  before A6).

---

## 6. Open questions

1. **phonewave's tplg** (`11b78ff1…`, pad4-audio-init.rs): byte-identical to
   an audioreach-topology build with the mzakamin overlay, or a third
   lineage? Compare after A0; if identical, we have triple corroboration for
   the binary. Also: their `adsp-runtime.mbn` (`eb56ce03…`) differs from the
   stock 11.A.38 `adsp.mbn` we and Fedora ship while `adsp_dtb.mbn` matches —
   which OTA is that, and does topology behavior differ on it? (Ask DocLogix.)
2. **DP/WSA dangling widgets at A1**: warnings only, or instantiation
   trouble on our 3-link DT? If trouble: trim MM6/WSA/DP from our m4 build
   (overlay edit, not upstream) or carry their 0134 DP link early.
3. **Does the denialwm devicesN kernel already carry the TDM chain?** Our
   perpetua/v7.3 branch does not, but phonewave's working audio implies the
   devicesN branches do. If denialwm publishes them, re-run the §2.2 table
   against that tree before writing our 0011+ series — we may be able to
   cherry-pick from our own lineage instead of porting Fedora's queue.
4. **q90-era audio deltas**: our patch table is q90x (`c060e3b`). Their README
   bumps queues weekly; re-diff `patches/0002-iceland` before A2 lands.
5. **Headset detection scope** (A8): which USB-C analog dongle/headset is the
   MBHC test target, and does the wcd_usbss mux path need the infiniti 0085
   DP-AUX coexistence fix at the same time?
6. **VA macro / DMIC**: topology carries VA_CODEC_DMA_TX_0 but the UCM never
   uses it and the board seems to have only the two AMICs — confirm no DMIC
   exists (schematic/stock mixer paths) and drop the VA subgraph from our
   build if so (smaller graph, fewer dangling widgets).
7. **`alsactl` ordering on Ubuntu**: Fedora relies on 90-alsa-restore.rules
   running the FixedBootSequence before WirePlumber. Verify the same ordering
   holds with Ubuntu's alsa-utils/udev packaging on our image (else ship a
   small ordered unit).

---

## Appendix A — handy numbers

Amps (DT :913-978; container slots from their 0046, decoded from our own cnt):

| amp | bus/addr | reset | devindex | prefix | 0x21 | 0x22 | speaker slot |
|---|---|---|---|---|---|---|---|
| tfa9865_tl | i2c0 0x34 | tlmm 2 | 0 | TopLeft | 0x101f | 0x0210 | 0 |
| tfa9865_bl | i2c0 0x36 | tlmm 114 | 1 | BottomLeft | 0x321f | 0x0212 | 2 |
| tfa9865_ml | i2c0 0x37 | tlmm 115 | 2 | MiddleLeft | 0x541f | 0x0214 | 4 |
| tfa9865_tr | i2c22 0x34 | tlmm 160 | 3 | TopRight | 0x011f | 0x0211 | 1 |
| tfa9865_br | i2c22 0x36 | tlmm 116 | 4 | BottomRight | 0x231f | 0x0213 | 3 |
| tfa9865_mr | i2c22 0x37 | tlmm 117 | 5 | MiddleRight | 0x451f | 0x0215 | 5 |

All six: reg 0x20 = 0x6f91 (TDM frame), 0x62 low nibble = 4, 0x68 = 0x0914
(0104); middle pair additionally 0x5f atten 5, 0x76 boost 0xf0 (0290).
Channel map FL FR FL FR FL FR FL FR; slots 6/7 empty. TDM endpoint: 8×32 bit,
48 kHz, LPASS master, long sync, data delay 1, bclk 12.288 MHz via
`LPASS_CLK_ID_PRI_TDM_IBIT` (0x200).

Module set (names as in our blacklist, make-diag-bootimg.sh:123): snd_q6apm,
q6apm_dai, q6apm_lpass_dais, q6prm, q6prm_clocks, snd_soc_sc8280xp,
snd_soc_tfa9865, snd_soc_wcd939x, soundwire_qcom, snd_soc_lpass_{rx,tx,va,
wsa}_macro, pinctrl_sm8650_lpass_lpi (+ qcom_q6v5_pas already up). phonewave's
load order: snd-q6apm → q6apm-dai → q6apm-lpass-dais → q6prm-clocks →
snd-soc-sc8280xp, then poll /proc/asound/cards (30 s).

Key controls (names from their UCM, ALSA-truncated):
`stream0.vol_ctrl0 MultiMedia1 Playback Volu` (Q13; 2056 = -12 dB, 8192 =
0 dB), `PRIMARY_TDM_RX_0 Audio Mixer MultiMedia1`,
`MultiMedia3 Mixer TX_CODEC_DMA_TX_3`, PCMs: playback hw:,0 — capture hw:,2.

## Appendix B — provenance of everything we adopt (manifest rules apply)

| artifact | source | license | note |
|---|---|---|---|
| audioreach-topology base m4 | github.com/linux-msm/audioreach-topology @ `993a17dcb672357998a463a73f120064d6c74f4f` | BSD-3-Clause (Linaro) | pin exactly; linux-firmware ships sibling tplg builds as redistributable |
| Pad 4 topology overlay (OnePlus-Pad4.m4 + audioreach/{module_tdm, module_vol_ctrl_capped, module_audio_if, subgraph-device-tdm-playback, subgraph-stream-vol-playback-capped, subgraph-compress-stream-vol-playback-capped, tokens}.m4) | mzakamin-hub/iceland-mainline @ `a7aab9f`, audio/topology/ | BSD-3-Clause headers | "THE REPO IS THE SOURCE OF TRUTH … sync your build copies FROM here" (their HiFi.conf) |
| UCM2 pair | same repo, audio/ucm/OnePlus-Pad4/ | (repo) | adapt pin value per rung (2056 → 8192 at A7) |
| PipeWire chain + raw-demotion + default-sink unit | same repo, packaging/iceland-device/files/62-iceland-speakers.conf, 62-iceland-speaker-raw.conf, iceland-speaker-default(.service) | chain header: adapted from tb323fu-linux (MIT) | keep attribution block |
| Kernel patches (table §2.2) | mzakamin-hub/iceland-linux @ `c060e3b`, patches/0001-infiniti + 0002-iceland | GPL-2.0 | re-diff against the live queue before A2 (Q4) |
| OnePlus-Pad4-tplg.bin (built) | A0 output | BSD-3-Clause | record sha256 in firmware-manifest.md before staging |
| tfa98xx.cnt (reference only, never shipped) | OUR odm.img `/firmware/tfa98xx.cnt`, dump.erofs --cat | proprietary | sha256 `9ef2463d5196…da2d`, 3702 B; register provenance for 0046/0104/0290 |
| adsp.mbn / adsp_dtb.mbn | already shipped (firmware-manifest.md) | qcom | `781512db…` / `09e35c42…`; byte-identical to Fedora's set |
