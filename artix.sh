#!/bin/sh

set -e

source "$(basename "$0")/header.sh"

DISK=""
[ -z "$DISK" ] && error "Need to specify disk!"
[ ! -d "$DISK" ] && error "$1 does not exist!"

BOOT_PART_SIZE=""
[ -z "$BOOT_PART_SIZE" ] && error "Need to specify boot partition size (in MB)!"

HOSTNAME=""
[ -z "$HOSTNAME" ] && error "Need to specify hostname."

USER_NAME=""
[ -z "$USER_NAME" ] && error "Need to specify username."

TIMEZONE=""
[ -z "$TIMEZONE" ] && error "Need to specify timezone."

#WIFI_DEV=""
#[ -z "$WIFI_DEV" ] && error "Need to specify wifi device."
#WIFI_SSID=""
#[ -z "$WIFI_SSID" ] && error "Need to specify wifi ssid."
#WIFI_PASS=""
#[ -z "$WIFI_PASS" ] && error "Need to specify wifi passphrase."

# wifi
# rfkill unblock all
# ip link set up "${WIFI_DEV}" #ipconfig
# wpa_passphrase "${WIFI_SSID}" "${WIFI_PASS}" >"/tmp/wpa.conf"
# wpa_supplicant -Bi "${WIFI_DEV}" -c "/tmp/wpa.conf"
# rm "/tmp/wpa.conf"
# dhcpd
# ping gnu.org
# sleep 3s

# write random data to disk
dd if="/dev/urandom" of="${DISK}" status="progress"

# partitioning
BOOT_PART_SIZE=$((BOOT_PART_SIZE + 1))
parted -s "$DISK" mklabel "gpt"
parted -s "$DISK" mkpart "BOOT" "1MiB" "${BOOT_PART_SIZE}MiB" set "1 esp on"
parted -s "$DISK" mkpart "ROOT" "${BOOT_PART_SIZE}MiB" "100%"

# encryption
cryptsetup luksFormat "${DISK}2"
cryptsetup luksOpen "${DISK}2" "root"

# filesystems
mkfs.fat -F "32" -n "BOOT" "${DISK}1"
mkfs.btrfs -L "ROOT" --force "/dev/mapper/root"

# mounting
mount -o "compress-force=zstd" "/dev/mapper/root" "/mnt"
mount --mkdir=0755 "${DISK}1" "/mnt/boot"

# compression
btrfs property set "/mnt" compression "zstd"

# installing system
basestrap "/mnt" base base-devel openrc elogind elogind-openrc linux linux-firmware lvm2 lvm2-openrc cryptsetup grub \
	efibootmgr os-prober networkmanager networkmanager-openrc

# fstab
fstabgen -U "/mnt" | sed 's/\s\+/ /g' >"/mnt/etc/fstab"

# chroot
artix-chroot "/mnt"

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
grub-install --target "x86_64-efi" --efi-directory "/boot" --bootloader-id "grub"
grub-mkconfig -o "/boot/grub/grub.cfg"

# users
useradd -m "${USER_NAME}"

# passwords
passwd "root"
passwd "${USER_NAME}"

# services
rc-update add NetworkManager default
