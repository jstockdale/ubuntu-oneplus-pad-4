#!/bin/bash
# The last handoff question: what root `model` and `compatible` does ABL's
# COMPOSED tree carry on this unit — base DTB (vendor_boot, ro.boot.dtb_idx)
# merged with the board overlay (dtbo, ro.boot.dtbo_idx)?
#
# OPPO's overlays carry properties at the overlay root (libufdt root-merge
# style, not fragment style), so the composition rule is simple: overlay
# root properties override the base root's, everything else of the base
# root stays. fdtoverlay cannot apply this style, so this script reads both
# roots and states the merged result instead of pretending to apply it.
#
# Usage: check-handoff-final.sh [DTB_IDX] [DTBO_IDX]
#        (defaults 12 and 6 — this unit's ro.boot.dtb_idx / dtbo_idx)
# Reads only files; nothing is flashed.
set -euo pipefail

base_dir=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
stock=${STOCK_DIR:-$base_dir/stock/current}
kernel_src=${KERNEL_SRC:-$base_dir/linux-perpetua}
kernel_out=${KERNEL_OUT_DIR:-$base_dir/out/kernel-iceland}
dtb_idx=${1:-12}
dtbo_idx=${2:-6}

for f in "$stock/vendor_boot.img" "$stock/dtbo.img"; do
	test -f "$f" || { echo "missing $f" >&2; exit 1; }
done
for tool in unpack_bootimg fdtget; do
	command -v "$tool" >/dev/null || { echo "$tool missing" >&2; exit 1; }
done

tmp=$(mktemp -d)
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

# Base: FDT number dtb_idx inside vendor_boot's dtb blob, in file order —
# the same order ABL's index counts.
unpack_bootimg --boot_img "$stock/vendor_boot.img" --out "$tmp/vb" >/dev/null
python3 - "$tmp/vb/dtb" "$tmp/base.dtb" "$dtb_idx" <<'EOF'
import struct, sys
blob = open(sys.argv[1], 'rb').read()
want, i, n = int(sys.argv[3]), 0, 0
while True:
    i = blob.find(b'\xd0\x0d\xfe\xed', i)
    if i < 0:
        sys.exit(f'only {n} FDTs; index {want} does not exist')
    size = struct.unpack('>I', blob[i+4:i+8])[0]
    if size < 64 or i + size > len(blob):
        i += 4
        continue
    if n == want:
        open(sys.argv[2], 'wb').write(blob[i:i+size])
        break
    n += 1
    i += size
EOF

# Overlay: entry dtbo_idx of the dt_table.
python3 - "$stock/dtbo.img" "$tmp/overlay.dtbo" "$dtbo_idx" <<'EOF'
import struct, sys
blob = open(sys.argv[1], 'rb').read()
magic, total, hdr, esz, cnt, eoff, page, ver = struct.unpack('>8I', blob[:32])
assert magic == 0xD7B7AB1E, 'not a dt_table image'
want = int(sys.argv[3])
assert want < cnt, f'only {cnt} overlays'
size, off, *_ = struct.unpack('>8I', blob[eoff + want*esz: eoff + want*esz + 32])
open(sys.argv[2], 'wb').write(blob[off:off+size])
EOF

prop() { fdtget -d '<absent>' "$1" / "$2" 2>/dev/null; }

base_model=$(prop "$tmp/base.dtb" model)
base_compat=$(prop "$tmp/base.dtb" compatible)
ov_model=$(prop "$tmp/overlay.dtbo" model)
ov_compat=$(prop "$tmp/overlay.dtbo" compatible)

echo "base   dtb  #$dtb_idx:  model='$base_model'"
echo "                   compatible='$base_compat'"
echo "board  dtbo #$dtbo_idx:  model='$ov_model'"
echo "                   compatible='$ov_compat'"

final_model=$base_model
[ "$ov_model" != '<absent>' ] && final_model=$ov_model
final_compat=$base_compat
[ "$ov_compat" != '<absent>' ] && final_compat=$ov_compat

echo
echo "composed root:     model='$final_model'"
echo "                   compatible='$final_compat'"

# What the kernel will accept, from the built DTB when it exists.
expected_src=$kernel_out/iceland.dtb
if [ -f "$expected_src" ]; then
	exp_models=$(fdtget -d '' "$expected_src" /chosen/fdt-handoff stock-model 2>/dev/null)
	exp_compat=$(fdtget -d '' "$expected_src" /chosen/fdt-handoff stock-compatible 2>/dev/null)
	from="built DTB"
else
	dts=$kernel_src/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts
	exp_models=$(sed -n 's/.*stock-model = //p' "$dts" | grep -o '"[^"]*"' | tr -d '"')
	exp_compat=$(sed -n 's/.*stock-compatible = //p' "$dts" | grep -o '"[^"]*"' | tr -d '"')
	from="DTS source"
fi
echo
echo "kernel expects ($from):  stock-model='$exp_models'"
echo "                             stock-compatible='$exp_compat'"

echo
ok=1
if [ "$final_model" = "$exp_models" ]; then
	echo 'model:      MATCH'
else
	echo 'model:      MISMATCH — add the composed model to stock-model'
	ok=0
fi
case " $final_compat " in
	*" $exp_compat "*) echo 'compatible: MATCH' ;;
	*)
		echo "compatible: MISMATCH — add '$final_compat' (first entry) to stock-compatible"
		ok=0
		;;
esac
echo 'bootargs:   prjname 25978 confirmed from the running unit earlier'
echo
if [ "$ok" = 1 ]; then
	echo 'VERDICT: the handoff accepts this unit as pinned — no patch needed.'
else
	echo 'VERDICT: patch kernel/patches/ with the strings above before the RAM boot.'
	exit 1
fi
