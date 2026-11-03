#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Obtain the pinned Perpetua kernel checkout this port builds against.
#
# Perpetua (denialwm/linux-perpetua) is the device source for iceland: the
# DTS, the panel/touch/backlight/speaker/Type-C drivers, the merged-fragment
# configuration tool (devices/config) and the boot packaging tool
# (devices/boot/android-gki) all live there.  This port pins one commit of it
# the way the gts9u port pins one upstream tag: builds are reproducible, and
# the pin moves only deliberately, with the porting log saying why.
#
# Upstream rebases onto each kernel release as a new perpetua/v<version>
# branch, so a pin bump can also mean a branch change.  Camera and microphone
# support were landing upstream when this pin was taken (2026-10-28); expect
# to bump often at first.
set -euo pipefail

base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
branch=${PERPETUA_BRANCH:-perpetua/v7.3}
commit=${PERPETUA_COMMIT:-b7d639cfb2825da1d922c48f65338becdf8d94d0}
# A local kernel checkout (any clone of torvalds/linux or of Perpetua itself)
# shares most objects; cloning from it avoids re-downloading ~3 GiB of history.
reference=${LINUX_REFERENCE:-}
target=$base/linux-perpetua
upstream=${PERPETUA_URL:-https://github.com/denialwm/linux-perpetua.git}

mkdir -p "$base"

if [ ! -d "$target/.git" ]; then
	if [ -n "$reference" ] && [ -d "$reference/.git" ]; then
		echo "cloning with local reference objects: $reference"
		git clone --reference-if-able "$reference" --dissociate \
			--branch "$branch" "$upstream" "$target"
	else
		# Not --depth 1: the pinned commit must stay reachable when the
		# branch moves on, and git describe / rev-parse in the build
		# metadata need real history.
		echo "cloning $branch from $upstream"
		git clone --branch "$branch" "$upstream" "$target"
	fi
else
	echo "already present: $target"
	git -C "$target" fetch origin "$branch"
fi

# The pin is the contract; the branch name is only where to find it.
if ! git -C "$target" cat-file -e "$commit^{commit}" 2>/dev/null; then
	echo "fetching the pinned commit $commit" >&2
	git -C "$target" fetch origin "$commit"
fi
git -C "$target" checkout --detach "$commit"

# Fail now, not at build time, if the checkout is not what iceland needs.
for path in devices/iceland/device devices/iceland/kernel.config \
	devices/config devices/boot/android-gki \
	arch/arm64/boot/dts/qcom/kaanapali-oneplus-iceland.dts; do
	test -e "$target/$path" || {
		echo "the pinned Perpetua commit lacks $path" >&2
		echo 'wrong branch, wrong commit, or upstream moved the layout' >&2
		exit 1
	}
done

echo "perpetua: $(git -C "$target" rev-parse HEAD) ($branch)"
