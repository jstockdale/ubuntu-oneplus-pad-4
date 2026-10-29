#!/bin/bash
# Report which host tools the Ubuntu image pipeline needs and which are
# missing.  Read-only: it installs nothing and touches no device.
set -uo pipefail

missing=0

need() {
	if command -v "$1" >/dev/null 2>&1; then
		printf 'OK    %-20s %s\n' "$1" "$(command -v "$1")"
	else
		printf 'MISS  %-20s (%s)\n' "$1" "$2"
		missing=$((missing + 1))
	fi
}

echo '=== kernel build ==='
need git 'apt install git'
need clang 'apt install clang lld llvm (Perpetua builds with LLVM=1)'
need ld.lld 'apt install lld'
need llvm-objcopy 'apt install llvm'
need make 'apt install make'
need flex 'apt install flex'
need bison 'apt install bison'
need bc 'apt install bc'
need dtc 'apt install device-tree-compiler'

echo '=== rootfs construction ==='
need mmdebstrap 'apt install mmdebstrap'
need qemu-aarch64-static 'apt install qemu-user-static'
need dpkg-deb 'apt install dpkg'
need debootstrap 'apt install debootstrap (fallback only)'

echo '=== stock image + firmware staging ==='
need payload-dumper-go 'github.com/ssut/payload-dumper-go (extracts boot/init_boot from the OTA payload)'
need unzip 'apt install unzip'
need fsck.erofs 'apt install erofs-utils (extracts firmware from vendor/odm images)'
need python3 'apt install python3'

echo '=== Android boot packaging (Perpetua devices/boot/android-gki) ==='
need avbtool 'apt install avbtool, or pip install avbtool'
need unpack_bootimg 'apt install mkbootimg (ships unpack_bootimg too)'
need lz4 'apt install lz4'
need cpio 'apt install cpio'

echo '=== image assembly ==='
need mkfs.ext4 'apt install e2fsprogs'
need resize2fs 'apt install e2fsprogs'
need e2fsck 'apt install e2fsprogs'
need debugfs 'apt install e2fsprogs'
need zstd 'apt install zstd'
need xz 'apt install xz-utils'

echo '=== flashing (owner machine, not the build host) ==='
need fastboot 'apt install android-sdk-platform-tools or fastboot'
need adb 'apt install adb'

echo '=== aarch64 emulation ==='
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	echo 'OK    binfmt qemu-aarch64 registered'
else
	echo 'MISS  binfmt qemu-aarch64 (apt install binfmt-support qemu-user-static)'
	missing=$((missing + 1))
fi

echo
if [ "$missing" -eq 0 ]; then
	echo 'All build dependencies are present.'
else
	echo "$missing dependency/dependencies missing."
fi
exit 0
