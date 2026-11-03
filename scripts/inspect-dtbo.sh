#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Enumerate the overlays inside a stock dtbo partition image and print what
# each one says about board identity — model strings and the id/rev fields
# the bootloader selects by. Cross this with the running tablet's
# `getprop ro.boot.dtbo_idx` to learn the exact model string ABL composes on
# THIS unit, which is the last leg of the fdt-handoff match.
#
# The image is the AOSP dt_table format: a big-endian header (magic
# 0xD7B7AB1E) and an entry table of {size, offset, id, rev, custom[4]}.
# Reads only files; nothing is flashed.
#
# Usage: inspect-dtbo.sh [dtbo.img]   (default: $STOCK_DIR/dtbo.img)
set -euo pipefail

base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
stock=${STOCK_DIR:-$base/stock/current}
img=${1:-$stock/dtbo.img}

test -f "$img" || {
	echo "missing $img" >&2
	echo 'stage it from the OTA payload first:' >&2
	echo '  unzip -o <OTA.zip> payload.bin -d /tmp/ota-payload' >&2
	echo "  payload-dumper-go -partitions dtbo -output $stock /tmp/ota-payload/payload.bin" >&2
	exit 1
}
command -v dtc >/dev/null || { echo 'dtc is missing' >&2; exit 1; }

tmp=$(mktemp -d)
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

python3 - "$img" "$tmp" <<'EOF'
import struct, sys
blob = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
magic, total, hdr_sz, ent_sz, ent_cnt, ent_off, page_sz, ver = \
    struct.unpack('>8I', blob[:32])
if magic != 0xD7B7AB1E:
    sys.exit(f'not a dt_table image (magic {magic:#x})')
print(f'dt_table: {ent_cnt} overlays, version {ver}, page size {page_sz}')
for n in range(ent_cnt):
    off = ent_off + n * ent_sz
    size, dt_off, dt_id, rev, *custom = struct.unpack('>8I', blob[off:off+32])
    open(f'{out}/overlay-{n:02d}.dtbo', 'wb').write(blob[dt_off:dt_off+size])
    print(f'overlay {n:02d}: {size:7d} bytes  id={dt_id:#010x}  rev={rev:#x}  '
          f'custom={[hex(c) for c in custom]}')
EOF

echo
for dtbo in "$tmp"/overlay-*.dtbo; do
	n=${dtbo##*overlay-}; n=${n%.dtbo}
	dts=$tmp/overlay-$n.dts
	dtc -I dtb -O dts -q -o "$dts" "$dtbo" 2>/dev/null || {
		echo "overlay $n: dtc could not decompile"
		continue
	}
	echo "overlay $n:"
	# Everything that names the board: model strings anywhere in the
	# overlay, and the id properties selection logic keys on.  No `head` at
	# a pipeline's end under pipefail: it SIGPIPEs grep at the cutoff and
	# set -e then kills the whole script, which is exactly how the first
	# run died after one overlay.  awk consumes its whole input instead.
	grep -nE 'model =|board-id|msm-id|pmic-id|oplus,project|hw-id|platform_support' \
		"$dts" 2>/dev/null | sed 's/^/    /' | awk 'NR<=12{print}' || true
	grep -qE 'model =' "$dts" || echo '    (no model property)'
done

echo
echo "Map the running unit's choice with:  adb shell getprop ro.boot.dtbo_idx"
echo 'The selected overlay'\''s model string (plus any base-tree model it'
echo 'overrides) is what the bootloader passes — the string the iceland DTS'\''s'
echo 'stock-model list must contain.'
