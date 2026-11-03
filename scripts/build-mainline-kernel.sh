#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Portions derived from ubuntu-galaxy-tab-s9-ultra (scripts/build-mainline-kernel.sh), Copyright (c) 2026 Ubuntu gts9uwifi port
# contributors, MIT License: see LICENSES/MIT.txt.
# Build the Perpetua kernel for iceland (OnePlus Pad 4) with this port's
# Ubuntu fragments merged in, and stage the artifacts in the shared layout.
#
# Derived from scripts/build-mainline-kernel.sh of the ubuntu-galaxy-tab-s9-
# ultra port.  The big structural difference: the device sources are not
# applied here, because they live upstream in Perpetua; what this script owns
# is the Ubuntu configuration delta (kernel/config/*.fragment), the optional
# local patches (kernel/patches/), and the artifact layout every later stage
# consumes.
#
# The pinned checkout stays pristine: patches apply to a detached git worktree
# and the build happens out of tree.  Nothing is flashed and no device is
# touched.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
kernel_src=${KERNEL_SRC:-$base/linux-perpetua}
kernel_tree=${KERNEL_WORKTREE:-$base/build/linux-src-iceland}
build_dir=${KERNEL_BUILD_DIR:-$base/build/linux-iceland}
out_dir=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
device=iceland
jobs=${KERNEL_JOBS:-$(nproc)}

test -d "$kernel_src/.git" || {
	echo "missing Perpetua checkout: $kernel_src" >&2
	echo 'run scripts/fetch-perpetua.sh first' >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Worktree: pinned commit plus our patches, never the checkout itself
# ---------------------------------------------------------------------------

commit=$(git -C "$kernel_src" rev-parse HEAD)
if [ -d "$kernel_tree" ]; then
	git -C "$kernel_src" worktree remove --force "$kernel_tree" 2>/dev/null || \
		rm -rf -- "$kernel_tree"
fi
git -C "$kernel_src" worktree prune
git -C "$kernel_src" worktree add --detach "$kernel_tree" "$commit"

shopt -s nullglob
patches=("$repo"/kernel/patches/*.patch)
shopt -u nullglob
for patch in "${patches[@]}"; do
	echo "applying ${patch##*/}"
	git -C "$kernel_tree" apply --index "$patch" || {
		echo "${patch##*/} no longer applies to $commit" >&2
		echo 'rebase the patch or drop it; never fix up the tree by hand' >&2
		exit 1
	}
done

# ---------------------------------------------------------------------------
# Configuration: Perpetua's own merged fragments, then this port's
# ---------------------------------------------------------------------------

# devices/config merges defconfig + mobile.config + qcom.config +
# kaanapali.config + devices/iceland/kernel.config, and fails when Kconfig
# drops a value a fragment asked for.  Our fragments ride on top under the
# same contract, enforced below, so an Ubuntu requirement cannot silently
# vanish on a Perpetua rebase either.
mkdir -p "$build_dir"
(cd "$kernel_tree" && ARCH=arm64 LLVM=1 devices/config "$device" "$build_dir")

our_fragments=("$repo"/kernel/config/*.fragment)
# Append + olddefconfig, deliberately NOT scripts/kconfig/merge_config.sh:
# merge_config re-resolves through alldefconfig, which re-defaults symbols
# the fragments never mention — observed dropping CONFIG_DRM_MSM (and with
# it DRM_KMS_HELPER=y), which made the vmlinux link fail on undefined DRM
# helper symbols. Appending lets the later assignment win per Kconfig's
# own rules, and olddefconfig resolves only what actually changed.
cat "${our_fragments[@]}" >> "$build_dir/.config"
make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" olddefconfig

# The same promise devices/config makes, extended to our fragments: every
# symbol they set must survive into the final configuration.  "=m is
# satisfied by =y" is the one tolerance, because merge order can promote.
failed=0
while IFS= read -r line; do
	case "$line" in
		''|'#'*) continue ;;
	esac
	symbol=${line%%=*}
	want=${line#*=}
	have=$(grep -E "^$symbol=" "$build_dir/.config" || true)
	case "$want" in
		m) [ "$have" = "$symbol=m" ] || [ "$have" = "$symbol=y" ] || {
			echo "DROPPED: wanted $line, got '${have:-unset}'" >&2
			failed=1
		} ;;
		*) [ "$have" = "$line" ] || {
			echo "DROPPED: wanted $line, got '${have:-unset}'" >&2
			failed=1
		} ;;
	esac
done < <(cat "${our_fragments[@]}")
[ "$failed" = 0 ] || {
	echo 'a fragment symbol was dropped by Kconfig; fix the fragment or its' >&2
	echo 'dependencies rather than accepting a silently different kernel' >&2
	exit 1
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" -j"$jobs" \
	Image modules

kernel_release=$(cat "$build_dir/include/config/kernel.release")

# ---------------------------------------------------------------------------
# Artifacts, in the layout Perpetua documents and the gts9u port shares:
# everything downstream takes these paths and nothing else.
# ---------------------------------------------------------------------------

rm -rf -- "$out_dir"
mkdir -p "$out_dir"

install -m 0644 "$build_dir/arch/arm64/boot/Image" "$out_dir/Image"
install -m 0644 "$build_dir/.config" "$out_dir/kernel.config"
install -m 0644 "$build_dir/System.map" "$out_dir/System.map"
install -m 0644 "$build_dir/Module.symvers" "$out_dir/Module.symvers"
printf '%s\n' "$kernel_release" > "$out_dir/kernel.release"

# The DTB is built into the Image; this copy exists for inspection and for
# tests, exactly as Perpetua's artifact layout prescribes.
dtb=$build_dir/arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dtb
test -f "$dtb" || { echo "missing built DTB: $dtb" >&2; exit 1; }
install -m 0644 "$dtb" "$out_dir/$device.dtb"

make -C "$kernel_tree" ARCH=arm64 LLVM=1 O="$build_dir" \
	INSTALL_MOD_PATH="$out_dir/modules-root" INSTALL_MOD_STRIP=1 \
	modules_install >/dev/null
# No /lib/modules/<release>/build symlink into the build host's tree: it
# would dangle on the device and confuse dkms-ish tooling into trying.
rm -f "$out_dir/modules-root/lib/modules/$kernel_release/build" \
	"$out_dir/modules-root/lib/modules/$kernel_release/source"

(cd "$out_dir" && find modules-root -type f -name '*.ko*' -exec sha256sum {} + \
	| sort -k2 > modules.sha256)

{
	printf 'device=%s\n' "$device"
	printf 'kernel_source=%s\n' "$commit"
	printf 'kernel_release=%s\n' "$kernel_release"
	printf 'local_patches=%s\n' "${#patches[@]}"
	printf 'image_sha256=%s\n' "$(sha256sum "$out_dir/Image" | cut -d' ' -f1)"
	printf 'dtb_sha256=%s\n' "$(sha256sum "$out_dir/$device.dtb" | cut -d' ' -f1)"
	printf 'config_sha256=%s\n' \
		"$(sha256sum "$out_dir/kernel.config" | cut -d' ' -f1)"
	printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$out_dir/BUILD-METADATA.txt"

echo '=== kernel ==='
cat "$out_dir/BUILD-METADATA.txt"
du -sh "$out_dir/modules-root" | sed 's/^/modules: /'
