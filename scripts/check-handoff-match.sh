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
read_expected() {
	local dtb=$1
	mapfile -t expected_models < <(fdtget -d '' "$dtb" /chosen/fdt-handoff \
		stock-model 2>/dev/null | tr '\0' '\n' | sed '/^$/d')
	mapfile -t expected_compat < <(fdtget -d '' "$dtb" /chosen/fdt-handoff \
		stock-compatible 2>/dev/null | tr '\0' '\n' | sed '/^$/d')
	mapfile -t expected_bootargs < <(fdtget -d '' "$dtb" /chosen/fdt-handoff \
		stock-bootargs 2>/dev/null | tr '\0' '\n' | sed '/^$/d')
}
if [ -f "$kernel_out/iceland.dtb" ]; then
	read_expected "$kernel_out/iceland.dtb"
	expected_from="built DTB $kernel_out/iceland.dtb"
elif [ -f "$kernel_src/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts" ]; then
	# A quick dtc of the source needs the full include chain; grep instead.
	mapfile -t expected_models < <(sed -n \
		's/.*stock-model = \(.*\);/\1/p' \
		"$kernel_src/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts" \
		| tr ',' '\n' | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//' | sed '/^$/d')
	mapfile -t expected_compat < <(sed -n \
		's/.*stock-compatible = \(.*\);/\1/p' \
		"$kernel_src/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts" \
		| tr ',' '\n' | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//' | sed '/^$/d')
	expected_from="DTS source in $kernel_src"
else
	echo 'neither a built iceland.dtb nor the Perpetua checkout found' >&2
	exit 1
fi
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
if [ "$matched" -gt 0 ]; then
	echo "VERDICT: $matched of $total stock tree(s) match — the handoff will"
	echo 'take the built-in tree on this firmware. stock-bootargs'
	echo '(oplusboot.prjname) is appended by ABL at boot and stays unverified'
	echo 'until the first RAM boot.'
else
	echo 'VERDICT: NO stock tree matches. The kernel would silently boot the'
	echo 'vendor tree. Fix: add this unit'\''s model string (printed above) to'
	echo 'stock-model in arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts'
	echo '— a one-line patch for kernel/patches/, and worth sending upstream'
	echo 'to Perpetua so the next pin bump carries it for everyone.'
	exit 1
fi
