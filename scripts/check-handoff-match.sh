#!/bin/bash
# Check whether the Perpetua kernel's FDT handoff will accept THIS unit's
# bootloader device tree — before anything touches the tablet.
#
# Background: the kernel's built-in tree replaces the bootloader's only when
# /chosen/fdt-handoff matches it (Documentation/devicetree/bindings/arm/
# fdt-handoff.yaml in Perpetua).  The match is stock-compatible AND
# stock-model AND stock-bootargs, each a "one of these" list.  A mismatch
# does not fail loudly: the kernel boots the vendor tree "as usual", which
# with a mainline kernel is a silently dead tablet.  The pinned iceland DTS
# names the India variant's model ("...Canoe MTP,iceland-O IN"); other
# regions likely differ, and this script is how we find out from the staged
# stock images instead of from a dark panel.
#
# What it can and cannot verify offline:
#   model + compatible  come from the static DTBs inside stock vendor_boot —
#                       fully checkable here;
#   stock-bootargs      ("oplusboot.prjname=...") is appended by ABL at boot
#                       and is usually NOT in the static tree — this script
#                       reports what it finds but a miss here is only
#                       "unverified", not "mismatch".
#
# Reads only files; nothing is flashed.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/root/ubuntu-iceland}
stock=${STOCK_DIR:-$base/stock/current}
kernel_src=${KERNEL_SRC:-$base/linux-perpetua}
kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}

vendor_boot=$stock/vendor_boot.img
test -f "$vendor_boot" || {
	echo "missing $vendor_boot; run scripts/stage-stock-images.sh first" >&2
	exit 1
}
for tool in unpack_bootimg fdtget; do
	command -v "$tool" >/dev/null || {
		echo "$tool is missing; see scripts/check-build-deps.sh" >&2
		exit 1
	}
done

# --- what the kernel expects ------------------------------------------------
# Prefer the built DTB (ground truth for what will boot); fall back to the
# pinned source tree so the check does not require a kernel build.
expected_models=() expected_compat=() expected_bootargs=()
# Quoted-string splitting, never a bare comma split: device tree strings
# ("qcom,canoe", "... MTP,iceland-O IN") carry commas inside them, which is
# exactly the mistake this function's first version made.
split_quoted() { grep -o '"[^"]*"' | tr -d '"'; }
read_expected_dtb() {
	# dtc round-trips the node with proper quoting; fdtget joins string
	# arrays with spaces and cannot be parsed back once strings have spaces.
	local node
	node=$(dtc -I dtb -O dts -q "$1" 2>/dev/null \
		| sed -n '/fdt-handoff {/,/};/p')
	mapfile -t expected_models < <(printf '%s\n' "$node" \
		| sed -n 's/.*stock-model = //p' | split_quoted)
	mapfile -t expected_compat < <(printf '%s\n' "$node" \
		| sed -n 's/.*stock-compatible = //p' | split_quoted)
	mapfile -t expected_bootargs < <(printf '%s\n' "$node" \
		| sed -n 's/.*stock-bootargs = //p' | split_quoted)
}
read_expected_dts() {
	mapfile -t expected_models < <(sed -n 's/.*stock-model = //p' "$1" \
		| split_quoted)
	mapfile -t expected_compat < <(sed -n 's/.*stock-compatible = //p' "$1" \
		| split_quoted)
	mapfile -t expected_bootargs < <(sed -n 's/.*stock-bootargs = //p' "$1" \
		| split_quoted)
}
if [ -f "$kernel_out/iceland.dtb" ]; then
	read_expected_dtb "$kernel_out/iceland.dtb"
	expected_from="built DTB $kernel_out/iceland.dtb"
elif [ -f "$kernel_src/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts" ]; then
	read_expected_dts \
		"$kernel_src/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts"
	expected_from="DTS source in $kernel_src"
else
	echo 'neither a built iceland.dtb nor the Perpetua checkout found' >&2
	exit 1
fi
[ "${#expected_compat[@]}" -gt 0 ] || {
	echo 'could not parse stock-compatible from the kernel side' >&2
	exit 1
}
echo "expected (from $expected_from):"
printf '  stock-compatible: %s\n' "${expected_compat[@]:-<none>}"
printf '  stock-model:      %s\n' "${expected_models[@]:-<none>}"
printf '  stock-bootargs:   %s\n' "${expected_bootargs[@]:-<none, or source-grep skipped>}"

# --- what the bootloader will pass ------------------------------------------
tmp=$(mktemp -d)
cleanup() { rm -rf -- "$tmp"; }
trap cleanup EXIT

unpack_bootimg --boot_img "$vendor_boot" --out "$tmp/unpacked" >/dev/null
dtb_blob=$tmp/unpacked/dtb
test -s "$dtb_blob" || { echo 'vendor_boot carries no dtb' >&2; exit 1; }

# vendor_boot's dtb area concatenates one FDT per board revision; split on
# the magic and each header's totalsize.
python3 - "$dtb_blob" "$tmp" <<'EOF'
import struct, sys
blob = open(sys.argv[1], 'rb').read()
out, i, n = sys.argv[2], 0, 0
while True:
    i = blob.find(b'\xd0\x0d\xfe\xed', i)
    if i < 0:
        break
    size = struct.unpack('>I', blob[i+4:i+8])[0]
    if size < 64 or i + size > len(blob):
        i += 4
        continue
    open(f'{out}/stock-{n:02d}.dtb', 'wb').write(blob[i:i+size])
    n += 1
    i += size
print(f'{n} device tree(s) in vendor_boot', file=sys.stderr)
EOF

matched=0 total=0
stock_compats_seen=()
echo
for dtb in "$tmp"/stock-*.dtb; do
	total=$((total + 1))
	model=$(fdtget -d '<none>' "$dtb" / model 2>/dev/null)
	compat=$(fdtget -d '<none>' "$dtb" / compatible 2>/dev/null)
	bootargs=$(fdtget -d '' "$dtb" /chosen bootargs 2>/dev/null || true)
	echo "${dtb##*/}:"
	echo "  model:      $model"
	echo "  compatible: $compat"
	[ -n "$bootargs" ] && echo "  bootargs:   $bootargs"
	for c in $compat; do stock_compats_seen+=("$c"); done
	model_ok=no
	for m in "${expected_models[@]:-}"; do
		[ "$model" = "$m" ] && model_ok=yes
	done
	compat_ok=no
	for c in "${expected_compat[@]:-}"; do
		case " $compat " in *" $c "*) compat_ok=yes ;; esac
	done
	echo "  -> model ${model_ok^^}, compatible ${compat_ok^^}"
	[ "$model_ok" = yes ] && [ "$compat_ok" = yes ] && matched=$((matched + 1))
done

echo
echo 'NOTE: vendor_boot carries SoC-level base trees; the board identity'
echo '(the "... MTP,iceland-O <region>" model) is applied at boot as a dtbo'
echo 'overlay, so this offline check can only prove the COMPATIBLE leg and'
echo 'enumerate the bases. The authoritative model string comes from the'
echo 'RUNNING tablet, no root needed:'
echo '    adb shell cat /proc/device-tree/model'
echo
if [ "$matched" -gt 0 ]; then
	echo "VERDICT: $matched of $total stock tree(s) match on model+compatible."
elif printf '%s\n' "${stock_compats_seen[@]:-}" | grep -qxF -- "${expected_compat[0]}"; then
	echo 'VERDICT: compatible MATCHES on at least one base tree; the model'
	echo 'leg must be settled from the running tablet (command above). If its'
	echo 'model differs from the expected list, add it to stock-model in the'
	echo 'iceland DTS — a one-line patch for kernel/patches/, worth sending'
	echo 'upstream to Perpetua.'
else
	echo 'VERDICT: NO stock tree even matches stock-compatible — wrong'
	echo 'firmware for this device tree, or a staging problem. Stop and'
	echo 'investigate before any boot attempt.'
	exit 1
fi
