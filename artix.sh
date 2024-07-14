#!/bin/sh

set -e

BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
RESET="\033[0m"

error() {
	echo "${BOLD}${RED}${1}${RESET}"
	exit 1
}

[ "$(whoami)" != "root" ] && error "You need to run this script as root"
[ ! "$#" -eq 1 ] && echo "Need to specify disk."
[ ! -e "$1" ] && error "$1 does not exist."

DISK="$1"
HOSTNAME="$2"
USER_NAME="$3"
TIMEZONE="$4"
#WIFI_DEV=""
#WIFI_SSID=""
#WIFI_PASS=""

# write random data to disk
dd if="/dev/urandom" of="${DISK}" status="progress"

# wifi
# rfkill unblock all
# ip link set up "${WIFI_DEV}" #ipconfig
# wpa_passphrase "${WIFI_SSID}" "${WIFI_PASS}" >"/tmp/wpa.conf"
# wpa_supplicant -Bi "${WIFI_DEV}" -c "/tmp/wpa.conf"
# rm "/tmp/wpa.conf"
# dhcpd
# ping gnu.org
# sleep 3s

# partitioning
parted -s "$DISK" mklabel "gpt"                                  # gpt
parted -s "$DISK" mkpart "BOOT" "1MiB" "1050623s" set "1 esp on" # uefi 512MB boot partition
parted -s "$DISK" mkpart "ROOT" "1050624s" "100%"                # root partition

# encryption
cryptsetup luksFormat "${DISK}2"
cryptsetup luksOpen "${DISK}2" "root"

# filesystems
mkfs.fat -n "BOOT" -F "32" "${DISK}1"
mkfs.btrfs -L "ROOT" --force "/dev/mapper/root"

# mounting
mount "/dev/mapper/root" "/mnt"
mount --mkdir=0755 "${DISK}1" "/mnt/boot"

# installing system
basestrap "/mnt" base base-devel openrc elogind elogind-openrc linux linux-firmware lvm2 lvm2-openrc cryptsetup grub efibootmgr os-prober networkmanager networkmanager-openrc neovim

# fstab
fstabgen -U "/mnt" >"/mnt/etc/fstab"

# chroot
# or you can do
# artix-chroot "/mnt"
# instead of all this
mount --types "proc" "/proc" "/mnt/proc"
mount --rbind "/sys" "/mnt/sys"
mount --make-rslave "/mnt/sys"
mount --rbind "/dev" "/mnt/dev"
mount --make-rslave "/mnt/dev"
mount --bind "/run" "/mnt/run"
mount --make-slave "/mnt/run"
chroot "/mnt"

# decryption
sed -i "s/block filesystems/block encrypt lvm2 filesystems/" "/etc/mkinitcpio.conf"
UUID="$(blkid -s UUID -o value ${DISK}2)"
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=*/GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${UUID}:root root=\/dev\/mapper\/root\"/" "/etc/default/grub"

# computer info
echo "${HOSTNAME}" >"/etc/hostname"
echo "hostname=\"${HOSTNAME}\"" >"/etc/conf.d/hostname"
echo "127.0.0.1 localhost" >"/etc/hosts"
echo "::1 localhost" >>"/etc/hosts"
echo "127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}" >>"/etc/hosts"

# time
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "/etc/localtime"
hwclock --systohc

# locale
echo "en_US.UTF-8 UTF-8" >"/etc/locale.gen"
locale-gen

# bootloader
mkinitcpio -p "linux" # because we need to enable lvm support
grub-install --target "x86_64-efi" --efi-directory "/boot" --bootloader-id "grub"
grub-mkconfig -o "/boot/grub/grub.cfg"

# users
useradd -m "${USER_NAME}"

# passwords
passwd "root"
passwd "${USER_NAME}"

# services
rc-update add NetworkManager default
