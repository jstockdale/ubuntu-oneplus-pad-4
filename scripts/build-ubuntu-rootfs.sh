#!/bin/bash
# Build a reproducible Ubuntu 26.04 LTS arm64 root filesystem for the OnePlus
# Pad 4 (OPD2514, iceland).
#
# Derived from scripts/build-ubuntu-rootfs.sh of the ubuntu-galaxy-tab-s9-
# ultra port; the structure, the hooks discipline (the rootfs is never
# modified by hand after mmdebstrap finishes) and the variable names are kept
# so the family of ports builds the same way.  What changed and why:
#
#   * 26.04 (resolute) instead of 24.04: Mesa 26 carries the initial
#     Adreno 840 support, so the GPU stack needs no backports.
#   * no fingerprint stack: the Pad 4 has no fingerprint hardware.
#   * no microSD path: the Pad 4 has no card slot; the only install target is
#     the userdata image.
#   * waydroid is installed from the archive (universe), per the phase-1
#     decision.
#
# The result is a directory tree, not an image; scripts/build-rootfs-image.sh
# turns it into the ext4 userdata image.  Nothing here writes to a device.
#
# Profiles:
#   minimal   base system, USB networking and SSH only — the bring-up image
#   desktop   adds GNOME/Wayland, PipeWire, Mesa and Waydroid (default)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
rootfs=${ROOTFS_DIR:-$base/rootfs}
profile=${ICELAND_PROFILE:-desktop}
suite=${UBUNTU_SUITE:-resolute}
mirror=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
hostname=${ICELAND_HOSTNAME:-ubuntu-iceland}
username=${ICELAND_USER:-ubuntu}
# Neutral defaults: whatever the image ships is what GNOME's first-boot wizard
# shows pre-selected, and the wizard asks for all three anyway.
locale=${ICELAND_LOCALE:-en_US.UTF-8}
timezone=${ICELAND_TIMEZONE:-UTC}
keymap=${ICELAND_KEYMAP:-us}
kernel_out=${KERNEL_OUT_DIR:-$base/out/kernel-iceland}
kernel_release=${KERNEL_RELEASE:-$(cat "$kernel_out/kernel.release" 2>/dev/null || true)}
modules_root=${KERNEL_MODULES_ROOT:-$kernel_out/modules-root}
authorized_keys=${ICELAND_AUTHORIZED_KEYS:-}
# No account is created by default: the image ships none and GNOME's
# first-boot wizard creates the owner's.  ICELAND_PW brings back a known
# account for development images, where unattended SSH matters more.
password=${ICELAND_PW:-}
root_label=${ROOT_LABEL:-UBPAD4_ROOT}

command -v mmdebstrap >/dev/null || {
	echo 'mmdebstrap is missing; see scripts/check-build-deps.sh' >&2
	exit 1
}
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || {
	echo 'binfmt qemu-aarch64 is not registered; see scripts/check-build-deps.sh' >&2
	exit 1
}

case "$rootfs" in
	"$base"/*) ;;
	*) echo "refusing to build outside $base: $rootfs" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Package sets
# ---------------------------------------------------------------------------

# snapd and apparmor are explicit rather than left to Recommends: in Ubuntu
# `apt install firefox` exists only to install a snap, and AppArmor profiles
# only load when the userspace tools are present (our kernel enables the LSM).
base_packages='
ubuntu-minimal,ubuntu-standard,
systemd,systemd-sysv,systemd-resolved,udev,dbus,
initramfs-tools,busybox-initramfs,
e2fsprogs,dosfstools,parted,gdisk,
zstd,xz-utils,lz4,
sudo,locales,tzdata,console-setup,keyboard-configuration,
cloud-guest-utils,
apparmor,apparmor-utils,
snapd,squashfs-tools,
netplan.io,network-manager,wpasupplicant,
openssh-server,avahi-daemon,
protection-domain-mapper,qrtr-tools,
iputils-ping,curl,wget,ca-certificates,
nano,less,htop,rsync,unzip,acl,
usbutils,pciutils,ethtool,evtest,i2c-tools,v4l-utils,
strace,tree
'

# yaru-theme-icon and gnome-keyring are explicit for the reasons the gts9u
# port documented: without the first the icon theme silently falls back to
# Adwaita, without the second NetworkManager has no secret agent and joining
# protected Wi-Fi never prompts for a password.
desktop_packages='
ubuntu-desktop-minimal,gdm3,gnome-shell,gnome-session,gnome-control-center,
gnome-initial-setup,
gnome-terminal,nautilus,gnome-text-editor,
mutter,xdg-desktop-portal-gnome,xdg-user-dirs,
yaru-theme-icon,yaru-theme-gtk,yaru-theme-sound,yaru-theme-gnome-shell,
gnome-keyring,libpam-gnome-keyring,
mesa-utils,mesa-vulkan-drivers,libgl1-mesa-dri,vulkan-tools,
libdrm-tests,edid-decode,
pipewire,pipewire-pulse,pipewire-audio,wireplumber,
pulseaudio-utils,
libspa-0.2-bluetooth,bluez,alsa-ucm-conf,alsa-utils,
iio-sensor-proxy,upower,power-profiles-daemon,
fonts-ubuntu,fonts-noto-color-emoji,
locales-all,
gnome-software,gnome-software-plugin-snap,
waydroid
'

packages=$(printf '%s' "$base_packages" | tr -d ' \n')
if [ "$profile" = desktop ]; then
	packages="$packages,$(printf '%s' "$desktop_packages" | tr -d ' \n')"
fi

# ---------------------------------------------------------------------------
# Customisation applied inside the same mmdebstrap invocation, so the rootfs
# is never modified afterwards by hand.
# ---------------------------------------------------------------------------

hooks=$base/hooks
rm -rf -- "$hooks"
mkdir -p "$hooks"

cat > "$hooks/configure.sh" <<HOOK
#!/bin/sh
set -eu
target="\$1"

# --- identity -------------------------------------------------------------
echo '$hostname' > "\$target/etc/hostname"
cat > "\$target/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$hostname
::1		localhost ip6-localhost ip6-loopback
fe00::0		ip6-localnet
ff00::0		ip6-mcastprefix
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

# --- locale, timezone and keyboard ---------------------------------------
# locales-all ships every locale pre-generated, which keeps locale-gen — slow
# under emulation — out of the build, and keeps the first-boot wizard's
# language list honest (the gts9u port learned this the hard way).
echo '$locale UTF-8' > "\$target/etc/locale.gen"
echo 'LANG=$locale' > "\$target/etc/default/locale"
ln -sf "/usr/share/zoneinfo/$timezone" "\$target/etc/localtime"
echo '$timezone' > "\$target/etc/timezone"
cat > "\$target/etc/default/keyboard" <<EOF
XKBMODEL="pc105"
XKBLAYOUT="$keymap"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# --- filesystems ----------------------------------------------------------
# By label, never by device: UFS LUN enumeration order is not a contract.
# /boot stays inside the root filesystem (ABL never reads a filesystem), so
# unlike the gts9u microSD image there is exactly one entry.
cat > "\$target/etc/fstab" <<EOF
LABEL=$root_label	/	ext4	defaults,noatime,errors=remount-ro	0 1
EOF

# --- initramfs --------------------------------------------------------------
# LZ4 legacy is mandatory: ABL concatenates the stock vendor_boot ramdisk
# fragments with our init_boot ramdisk, and the gts9u port physically
# established that a gzip generic ramdisk behind an LZ4 vendor fragment makes
# Linux reject the initrd.  MODULES=list with an empty list, measured, not
# guessed: MODULES=most packed all 939 modules into 17.3 MB against the
# 8.4 MB init_boot partition, and Perpetua builds every pre-rootfs provider
# (UFS, ext4) into the kernel precisely so the initramfs needs none.
# Anything that ever does belong here goes in /etc/initramfs-tools/modules,
# named and justified.  The budget is enforced by make-initramfs.sh and by
# android-gki against the stock partition size.
cat > "\$target/etc/initramfs-tools/initramfs.conf" <<EOF
MODULES=list
BUSYBOX=y
KEYMAP=n
COMPRESS=lz4
COMPRESSLEVEL=9
DEVICE=
NFSROOT=auto
RUNSIZE=10%
EOF

# --- network --------------------------------------------------------------
mkdir -p "\$target/etc/netplan"
cat > "\$target/etc/netplan/01-network-manager-all.yaml" <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 0600 "\$target/etc/netplan/01-network-manager-all.yaml"

# --- apt pockets ----------------------------------------------------------
cat > "\$target/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $mirror
Suites: $suite $suite-updates $suite-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $mirror
Suites: $suite-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f "\$target/etc/apt/sources.list"

# --- ssh ------------------------------------------------------------------
mkdir -p "\$target/etc/ssh/sshd_config.d"
cat > "\$target/etc/ssh/sshd_config.d/10-iceland.conf" <<EOF
PasswordAuthentication yes
PermitRootLogin no
EOF
HOOK
chmod +x "$hooks/configure.sh"

# Local packages: for now only the device integration.  The gts9u port grew
# camera, fingerprint, sensor and companion packages here over time; this port
# will grow its own the same way — each behind an input-hash stamp so a stale
# .deb can never silently ride into a fresh rootfs.
bash "$repo/scripts/build-device-package.sh" >/dev/null

stage_debs=$base/out/local-debs
rm -rf -- "$stage_debs"
mkdir -p "$stage_debs"
for pkg in ubuntu-iceland-device; do
	deb=$(ls -t "$base"/out/packages/${pkg}_*.deb 2>/dev/null | head -1 || true)
	if [ -z "$deb" ]; then
		echo "missing local package: $pkg" >&2
		exit 1
	fi
	cp "$deb" "$stage_debs/"
	echo "local package: ${deb##*/}"
done

cat > "$hooks/local-packages.sh" <<HOOK
#!/bin/sh
set -eu
target="\$1"
mkdir -p "\$target/tmp/local-debs"
cp $stage_debs/*.deb "\$target/tmp/local-debs/"
# One apt transaction, so dependency order and any archive-package conflicts
# are resolved by the solver, not by our luck with dpkg ordering.
chroot "\$target" sh -c 'apt-get install -y /tmp/local-debs/*.deb'
chroot "\$target" apt-get check
rm -rf "\$target/tmp/local-debs"

# Every language pack, as on gts9u: a tablet that offers Japanese and then
# talks English is worse than a gigabyte of packs.  apt expands the glob.
if [ '$profile' = desktop ]; then
	chroot "\$target" sh -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y \
		"language-pack-*" "language-pack-gnome-*" >/dev/null'
	installed_langs=\$(chroot "\$target" sh -c \
		'dpkg-query -W -f "\${Package}\n" "language-pack-*" 2>/dev/null | wc -l')
	echo "language packs installed: \$installed_langs"
	[ "\$installed_langs" -gt 50 ] || {
		echo 'the language pack glob matched almost nothing' >&2
		exit 1
	}
fi
HOOK
chmod +x "$hooks/local-packages.sh"

cat > "$hooks/chroot-setup.sh" <<HOOK
#!/bin/sh
set -eu
target="\$1"

# locales-all ships every locale pre-generated; keep the fallback for trimmed
# profiles that deliberately omit it.
if ! chroot "\$target" dpkg-query -W -f '\${Status}' locales-all 2>/dev/null | \
	grep -q 'ok installed'; then
	chroot "\$target" locale-gen
fi
chroot "\$target" update-locale LANG=$locale

chroot "\$target" passwd -l root

if [ -n '$password' ]; then
	# Development image: an account the build knows, so SSH works before
	# anyone has touched the screen.
	chroot "\$target" useradd -m -s /bin/bash \
		-G sudo,adm,dialout,audio,video,plugdev,netdev,input,render '$username'
	echo '$username:$password' | chroot "\$target" chpasswd
	# Development image only (this branch exists only when ICELAND_PW is
	# set): passwordless sudo, because capture-device-data.sh and every
	# other scripted remote step run "ssh ... sudo ..." with no TTY to
	# answer a prompt on. Shipping images never get this file.
	echo '$username ALL=(ALL) NOPASSWD:ALL' \
		> "\$target/etc/sudoers.d/90-iceland-dev"
	chmod 0440 "\$target/etc/sudoers.d/90-iceland-dev"
elif [ '$profile' = desktop ]; then
	# Shipping image: no account, so GDM runs gnome-initial-setup and the
	# owner creates their own.  The key must be written, not uncommented:
	# Ubuntu ships custom.conf with every key commented out.
	mkdir -p "\$target/etc/gdm3"
	touch "\$target/etc/gdm3/custom.conf"
	if grep -q '^InitialSetupEnable' "\$target/etc/gdm3/custom.conf"; then
		sed -i 's/^InitialSetupEnable.*/InitialSetupEnable=true/' \
			"\$target/etc/gdm3/custom.conf"
	elif grep -q '^\[daemon\]' "\$target/etc/gdm3/custom.conf"; then
		sed -i '/^\[daemon\]/a InitialSetupEnable=true' \
			"\$target/etc/gdm3/custom.conf"
	else
		printf '[daemon]\nInitialSetupEnable=true\n' \
			>> "\$target/etc/gdm3/custom.conf"
	fi
	grep -q '^InitialSetupEnable=true' "\$target/etc/gdm3/custom.conf" || {
		echo 'could not enable the first-boot wizard in gdm3 custom.conf' >&2
		exit 1
	}
else
	echo 'minimal profile with no ICELAND_PW: the image has no login path' >&2
	echo 'except SSH keys; set ICELAND_AUTHORIZED_KEYS or ICELAND_PW' >&2
fi

chroot "\$target" systemctl enable ssh.service
chroot "\$target" systemctl enable NetworkManager.service
chroot "\$target" systemctl enable systemd-timesyncd.service || true
chroot "\$target" systemctl enable ubuntu-iceland-grow-rootfs.service

# Waydroid is opt-in at runtime (waydroid init downloads images); the session
# service stays disabled until the owner runs it.  Nothing to enable here.

# Persistent journal: the panel can stay dark long before a display manager
# starts, so the journal is the primary diagnostic channel.
mkdir -p "\$target/var/log/journal"
mkdir -p "\$target/etc/systemd/journald.conf.d"
cat > "\$target/etc/systemd/journald.conf.d/10-iceland-persistent.conf" <<EOF
[Journal]
Storage=persistent
SystemMaxUse=256M
EOF

# No apt-installed kernel: this port boots the Perpetua kernel from the
# Android boot partition and stages its modules itself.
cat > "\$target/etc/apt/preferences.d/no-distro-kernel" <<EOF
Package: linux-image-* linux-headers-* linux-generic*
Pin: release *
Pin-Priority: -1
EOF
HOOK
chmod +x "$hooks/chroot-setup.sh"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

if [ "${RESUME_ROOTFS:-0}" = 1 ]; then
	# A completed mmdebstrap tree is expensive; resume only after checking
	# enough of it to avoid staging a kernel into a partial tree.
	test -x "$rootfs/usr/bin/dpkg"
	test -f "$rootfs/etc/os-release"
	chroot "$rootfs" dpkg --audit
	chroot "$rootfs" apt-get check
	echo "resuming completed $profile rootfs: $rootfs"
else
	rm -rf -- "$rootfs"
	mkdir -p "$rootfs" "$base"

	echo "building $profile rootfs: $suite arm64 -> $rootfs"
	mmdebstrap \
		--architecture=arm64 \
		--variant=important \
		--components='main,restricted,universe,multiverse' \
		--include="$packages" \
		--customize-hook="$hooks/configure.sh" \
		--customize-hook="$hooks/local-packages.sh" \
		--customize-hook="$hooks/chroot-setup.sh" \
		--verbose \
		"$suite" \
		"$rootfs" \
		"deb $mirror $suite main restricted universe multiverse" \
		"deb $mirror $suite-updates main restricted universe multiverse" \
		"deb $mirror $suite-security main restricted universe multiverse"
fi

# Settle any pseudo-filesystem mmdebstrap's cleanup lost its unmount race on;
# everything downstream assumes a plain directory tree.
for sub in proc sys dev/pts dev; do
	mountpoint -q "$rootfs/$sub" 2>/dev/null || continue
	for attempt in 1 2 3 4 5; do
		umount "$rootfs/$sub" 2>/dev/null && break
		sleep 2
	done
	if mountpoint -q "$rootfs/$sub" 2>/dev/null; then
		echo "refusing to continue: $rootfs/$sub is still mounted" >&2
		exit 1
	fi
done

# ---------------------------------------------------------------------------
# Kernel modules and optional development key
# ---------------------------------------------------------------------------

if [ -n "$kernel_release" ] && [ -d "$modules_root" ]; then
	echo "staging kernel modules from $modules_root"
	# --owner=0 --group=0: the kernel build may run unprivileged (it needs
	# no root), and modules must land root-owned in the image regardless of
	# who built them.  --keep-directory-symlink: the rootfs is usr-merged
	# (/lib is a symlink to usr/lib) and tar otherwise REPLACES that
	# symlink with a real directory holding only modules/, severing
	# /lib/ld-linux-aarch64.so.1 and every chroot after it — the exact
	# failure the first rootfs build died on.
	tar -C "$modules_root" --owner=0 --group=0 -cf - . \
		| tar -C "$rootfs" --keep-directory-symlink -xf -
	chroot "$rootfs" depmod -a "$kernel_release"
	# initramfs-tools reads /boot/config-<release> to verify the kernel
	# supports the compressor we demand; without it the LZ4 requirement
	# degrades to an unverified warning.
	if [ -f "$kernel_out/kernel.config" ]; then
		install -m 0644 "$kernel_out/kernel.config" \
			"$rootfs/boot/config-$kernel_release"
	fi
else
	echo 'WARNING: no kernel artifacts; /lib/modules is empty and' >&2
	echo '         update-initramfs cannot run yet.' >&2
	echo '         run scripts/build-mainline-kernel.sh first.' >&2
fi

if [ -n "$authorized_keys" ] && [ -f "$authorized_keys" ]; then
	if [ -n "$password" ]; then
		install -d -m 0700 -o 1000 -g 1000 "$rootfs/home/$username/.ssh"
		install -m 0600 -o 1000 -g 1000 "$authorized_keys" \
			"$rootfs/home/$username/.ssh/authorized_keys"
	else
		# /etc/skel is copied into whatever account the first-boot wizard
		# creates, so the key arrives with it.
		install -d -m 0700 "$rootfs/etc/skel/.ssh"
		install -m 0600 "$authorized_keys" \
			"$rootfs/etc/skel/.ssh/authorized_keys"
	fi
fi

echo '=== rootfs summary ==='
# The future updater consumes the same desired package list as a fresh
# installation; release metadata, not a user preference, so not /etc.
printf '%s' "$packages" | tr ',[:space:]' '\n' | sed '/^$/d' | sort -u \
	> "$rootfs/usr/lib/iceland-required-packages.txt"
du -sh --one-file-system "$rootfs" || echo 'rootfs size unavailable'
chroot "$rootfs" dpkg-query -f '${binary:Package}\n' -W | wc -l | \
	sed 's/^/packages installed: /'
