#!/bin/bash
### The config I use for a minimal KVM-PR hypervisor installation on my PowerPC G5 Quad // Useful for AmigaOS 4.1, Mac OS 9 (and probably AIX 4/5) virtualization ###
### Note that /dev/sda would be wiped without a further notice ###

### Install script -> cellularmitosis@MacRumors // Modified for a precompiled kernel and made some small changes ###
### Kernel config -> Tratkazir_the_1st@GentooForums // Added KVM, Virtio, USB3.0 and some other modules ###
### Genfstab -> glacion@GitHub -> Forked from arch-install-scripts (https://projects.archlinux.org/arch-install-scripts.git/) ###

set -x

### Partitioning the disk and creating the filesystem ###
mac-fdisk /dev/sda << EOF
i
y

b
2p
c
3p
4G
swap
c
4p
4p
root
w
y
EOF
sleep 1
umount /dev/sda4 || true
mkfs.xfs -f /dev/sda4

### Mounting the disk and getting the stage3 ready ###
mkdir -p /mnt/gentoo
mount /dev/sda4 /mnt/gentoo
stage3_tarball=$(wget -O - https://distfiles.gentoo.org/releases/ppc/autobuilds/current-stage3-ppc64-openrc/latest-stage3-ppc64-openrc.txt | grep '\.tar\.' | awk '{print $1}')
cd /mnt/gentoo
url=https://distfiles.gentoo.org/releases/ppc/autobuilds/current-stage3-ppc64-openrc/$stage3_tarball
wget -O - $url | unxz | tar xp --xattrs-include='*.*' --numeric-owner
wget https://raw.githubusercontent.com/ctemucin99/macppc64-gentoo/refs/heads/main/boot-6.12.41-gentoo-ppc64.tar.xz
tar xpvf boot*.tar.xz -C /mnt/gentoo/boot
rm -f boot*.tar.xz
mkdir -p /mnt/gentoo/lib/modules
wget https://raw.githubusercontent.com/ctemucin99/macppc64-gentoo/refs/heads/main/modules-6.12.41-gentoo-ppc64.tar.xz
tar xpvf modules*.tar.xz -C /mnt/gentoo/lib/modules
rm -f modules*.tar.xz

### Configuring GRUB ###
hformat -l bootstrap /dev/sda2
mkdir -p /mnt/gentoo/tmp/bootstrap
mount --types hfs /dev/sda2 /mnt/gentoo/tmp/bootstrap
grub-install --boot-directory=/mnt/gentoo/boot --macppc-directory=/mnt/gentoo/tmp/bootstrap /dev/sda2
umount /mnt/gentoo/tmp/bootstrap/
hmount /dev/sda2
hattrib -t tbxi -c UNIX :System:Library:CoreServices:BootX
hattrib -b :System:Library:CoreServices
humount

### Chrooting into the stage3 install ###
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash << 'ENDCHROOT'
set -e -o pipefail
source /etc/profile

### Setting password for 'root'
passwd << EOF
root
root
EOF

### Adding user and setting password for user
useradd -g users -G wheel,portage,audio,video,usb,cdrom -m gentoo
passwd gentoo << EOF
gentoo
gentoo
EOF
locale-gen
echo gentoo > /etc/hostname

### Portage config
cat << EOF > /etc/portage/make.conf 
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.
COMMON_FLAGS="-mcpu 970 -O2 -maltivec -mabi=altivec -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
USE="X udev dbus lto lm-sensors ibm ieee1394 opencl opengl -systemd -nvenc -wayland -xwayland -qt5 -qt6 -kde -gnome"
ACCEPT_LICENSES="*"
ACCEPT_KEYWORDS="~ppc64"
VIDEO_CARDS="nouveau radeon"
GRUB_PLATFORMS="ieee1275"

# WARNING: Changing your CHOST is not something that should be done lightly.
# Please consult https://wiki.gentoo.org/wiki/Changing_the_CHOST_variable before changing.
CHOST="powerpc64-unknown-linux-gnu"

# NOTE: This stage was built with the bindist USE flag enabled

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
LC_MESSAGES=C.utf8
EOF

### Configuring NPROC for MAKEOPTS ###
export NPROC=$(nproc)
export NPROC1=$(( NPROC + 1 ))
echo "MAKEOPTS=\"-j${NPROC1} -l$(nproc)\"" > nproc
sed -i 10r<(sed '1,1!d' nproc) /etc/portage/make.conf
rm nproc

### Getting genfstab and creating a temporary fstab ###
wget https://raw.githubusercontent.com/glacion/genfstab/refs/heads/master/genfstab -O /usr/bin
chmod /usr/bin/genfstab
/usr/bin/genfstab -U > /etc/fstab

### Rebooting the system ###
reboot
