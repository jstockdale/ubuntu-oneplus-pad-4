# Upstreaming

Status of everything this port carries that belongs somewhere else. The rule
(kernel/patches/README): a local patch is a loan, and this file is the ledger.

| What | Where it belongs | Status |
|---|---|---|
| 0028 q6apm READ/WRITE_DONE payload-size fix | denialwm/linux-perpetua, branch perpetua/v7.3 | **READ_DONE half merged upstream independently on 2026-11-02** (9ba37ef1db70, same `offsetofend` approach); drop that hunk at the next pin bump. WRITE_DONE half prepared as an optional consistency patch, see below |
| 0002 watchdog: stop the bootloader-armed dog | denialwm/linux-perpetua | to prepare |
| 0004–0007, 0010 (WCN7860 supplies/roles/floor, btqca names, nt36536 probe gate, DSI sync orientation) | denialwm/linux-perpetua | to prepare, after 0028 lands |
| 0011–0024 (TDM speaker chain), 0003/0008/0009 | mzak's Fedora iceland queue → Perpetua | theirs to submit; we carry with attribution |
| 0025/0026 (GPR callback order, GPR intent size) | infiniti-mainline → Perpetua | theirs |
| Userspace audio (UCM2, PipeWire chain) | alsa-ucm-conf / the Fedora iceland port | after the headphone profile exists |

## 0028 — ASoC: qcom: q6apm: validate READ/WRITE_DONE payloads by the fields used

Timeline. On 2026-11-02 at head `5c1eafa7b755` the bug was still present
upstream (`sound/soc/qcom/qdsp6/q6apm.c` lines 633 `sizeof(*done)` and 662
`sizeof(*rd_done)`), and this submission was prepared. Hours later the
branch gained `9ba37ef1db70` ("ASoC: qcom: q6apm: accept short read-done
responses", Doctor Logix, 2026-11-02): the READ_DONE check now reads
`offsetofend(typeof(*rd_done), buf_addr_msw)` with the comment "Kaanapali's
DSP sends 56 bytes, short of the metadata fields at the end" — the same fix
as 0028's READ_DONE hunk. The microphone regression is therefore fixed
upstream independently, and 0028's READ_DONE hunk is dropped at the next
pin bump (the pin must move past `9ba37ef1db70`).

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

### Issue text (fallback if PRs are not the project's channel)

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
