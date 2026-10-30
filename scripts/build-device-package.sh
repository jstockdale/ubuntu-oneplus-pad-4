#!/bin/bash
# Build the ubuntu-iceland-device .deb from packaging/ubuntu-iceland-device.
#
# Same contract as the gts9u port's package builders: deterministic
# permissions regardless of the checkout's umask, root-owned contents without
# needing a root checkout, and the output lands in the shared packages
# directory the rootfs build stages from.  Nothing is flashed.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
src=$repo/packaging/ubuntu-iceland-device
out=${PACKAGES_OUT_DIR:-$base/out/packages}
build=$base/build/ubuntu-iceland-device

version=$(sed -n 's/^Version: //p' "$src/DEBIAN/control")
[ -n "$version" ] || { echo 'no Version in DEBIAN/control' >&2; exit 1; }

rm -rf -- "$build"
mkdir -p "$build" "$out"
cp -a "$src/." "$build/"

# Permissions are part of the package, not of the checkout.
find "$build" -type d -exec chmod 0755 {} +
find "$build" -type f -exec chmod 0644 {} +
chmod 0755 "$build"/DEBIAN/postinst "$build"/usr/libexec/* 2>/dev/null || true

# dpkg-deb refuses stray editor droppings and so should we.
find "$build" -name '*~' -o -name '*.swp' | grep -q . && {
	echo 'editor temp files in the package tree' >&2
	exit 1
}

dpkg-deb --build --root-owner-group "$build" \
	"$out/ubuntu-iceland-device_${version}_arm64.deb" >/dev/null

echo "built $out/ubuntu-iceland-device_${version}_arm64.deb"
