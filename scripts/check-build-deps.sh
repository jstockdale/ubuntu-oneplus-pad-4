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
# A usable aarch64 interpreter is either the classic static binary or any
# qemu-aarch64 registered with binfmt's F (fix-binary) flag, which pre-opens
# the interpreter and makes it work inside chroots exactly as the static one
# does.  Modern Ubuntu ships the latter (qemu-user-hwe + qemu-user-binfmt-hwe)
# and has made qemu-user-static a virtual package.
if command -v qemu-aarch64-static >/dev/null 2>&1; then
	printf 'OK    %-20s %s\n' qemu-aarch64-static "$(command -v qemu-aarch64-static)"
elif grep -q '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
	printf 'OK    %-20s %s\n' 'qemu-aarch64 (F)' \
		"$(sed -n 's/^interpreter //p' /proc/sys/fs/binfmt_misc/qemu-aarch64)"
else
	printf 'MISS  %-20s (%s)\n' qemu-aarch64 \
		'apt install qemu-user-binfmt (or qemu-user-static where it exists)'
	missing=$((missing + 1))
fi
need dpkg-deb 'apt install dpkg'
need debootstrap 'apt install debootstrap (fallback only)'

echo '=== stock image + firmware staging ==='
need payload-dumper-go 'github.com/ssut/payload-dumper-go (extracts boot/init_boot from the OTA payload)'
need unzip 'apt install unzip'
need fsck.erofs 'apt install erofs-utils (extracts firmware from vendor/odm images)'
need python3 'apt install python3'

echo '=== Android boot packaging (Perpetua devices/boot/android-gki) ==='
need avbtool 'no apt package on current Ubuntu: apt install pipx && sudo pipx install --global avbtool'
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
if grep -q '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
	echo 'OK    binfmt qemu-aarch64 registered with fix-binary (F)'
elif [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	echo 'WARN  binfmt qemu-aarch64 registered WITHOUT the F flag; a dynamic'
	echo '      interpreter without fix-binary fails inside mmdebstrap chroots'
	missing=$((missing + 1))
else
	echo 'MISS  binfmt qemu-aarch64 (apt install qemu-user-binfmt binfmt-support)'
	missing=$((missing + 1))
fi

echo
if [ "$missing" -eq 0 ]; then
	echo 'All build dependencies are present.'
else
	echo "$missing dependency/dependencies missing."
fi
exit 0
