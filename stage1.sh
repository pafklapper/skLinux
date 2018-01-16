#!/bin/sh

# bash run options
set -o pipefail

initVars()
{
installationDirectory="$(dirname $(realpath "$0"))"
. $installationDirectory/globalVariables
. $installationDirectory/globalFunctions
logFile=/var/log/skLinux.log
}

initVars

# constants initialisation
DEBUG="false"
QUIET="true"
logFile=/var/log/skLinux

targetRootPw="r3pelsteeltje"
targetHostname="skLinuxClient"
packages="base  vim net-tools wget curl dialog wpa_supplicant wpa_actiond grml-zsh-config openssh git rsync gdm gnome xorg"

# variables initialisation
# do not change this line! 
VAR_f=$installationDirectory/stage1.runnerFile

# meta functions

function debug {
	if [ "$DEBUG" = "true" ]; then
		return 0
	else
		return 1;
	fi
}

function quiet {
	if [ "$QUIET" = "true" ]; then
		return 0
	else
		return 1;
	fi
}

function announce {
	#run now?

	eval `envsubst < $VAR_f`
	if [ -z $err_at ]; then err_at=-1; fi
	if [ -z $finished ]; then finished=0;fi
	runner=$(($runner+1))

	if [ $runner -lt $err_at ] || [ $runner -le $finished ]; then
		# skip to point of error
		echo "SKIP=1" >> $VAR_f
		debug && echo skipping step: $runner!
		return 1;
	else
		SKIP=
                sed -i '/^SKIP=/d' $VAR_f
		>&2 echo -n "$1"
	
		#temporarily disable stdout
		quiet && exec 4<&1
		quiet && exec 5<&2
		quiet && exec 1>${logFile}
		quiet && exec 2>${logFile}
	fi

return 0
}

function check_fail {
	# reenable stdout
	quiet && exec 1<&4
	quiet && exec 2<&5

	if [[ $1 -ne 0 ]]; then
		eval `envsubst < $VAR_f`
		if [ -n "$SKIP" ]; then
			sed -i '/^SKIP=/d' $VAR_f
			return 0;
		else
			>&2 echo "FAIL!"
			if [ -z "$(grep -e '^err_at=' $VAR_f )"  ]; then
				echo "err_at=$(($runner))" >> $VAR_f
			fi
			exit 1
		fi
	else
		>&2 echo -e "\e[32m\e[1mOK\e[0m"
		if [ -z "$(grep -e '^finished=' $VAR_f )"  ]; then
                	echo "finished=$runner" >> $VAR_f
		else
			sed -i "/^finished=/c\finished=$(($finished+1))" $VAR_f
                fi
	fi
}

fatalError() {
	echo "FATALE FOUT: $@"; read
	exit 1
}


updateGrub()
{
mkdir -p /mnt/SLICE-A; mkdir -p /mnt/SLICE-B
if [ -z "$(mount  | grep ${targetDisk}3)" ]; then mount ${targetDisk}3 /mnt/SLICE-A; fi
if [ -z "$(mount  | grep ${targetDisk}4)" ]; then mount ${targetDisk}4 /mnt/SLICE-B; fi

find /boot -name "*-fallback.img" -exec mv {} {}.disabled \;
find /mnt/SLICE-A/boot -name "*-fallback.img" -exec mv {} {}.disabled \;
find /mnt/SLICE-B/boot -name "*-fallback.img" -exec mv {} {}.disabled \;

grub-mkconfig -o /boot/grub/grub.cfg || fatalError

uuidBeheer=$(blkid -o value -s UUID ${targetDisk}2)
uuidSliceA=$(blkid -o value -s UUID ${targetDisk}3)
uuidSliceB=$(blkid -o value -s UUID ${targetDisk}4)


menuStringBeheer="$(cat /boot/grub/grub.cfg | grep -e $uuidBeheer | grep -e "menuentry" )"
menuStringSliceA="$(cat /boot/grub/grub.cfg | grep -e $uuidSliceA | grep -e "menuentry" )"
menuStringSliceB="$(cat /boot/grub/grub.cfg | grep -e $uuidSliceB | grep -e "menuentry" )"

menuNameStringBeheer="$(echo $menuStringBeheer | cut -f2 -d\')"
menuNameStringSliceA="$(echo $menuStringSliceA | cut -f2 -d\')"
menuNameStringSliceB="$(echo $menuStringSliceB | cut -f2 -d\')"

newMenuNameStringBeheer="Beheer en Updates"
newMenuNameStringSliceA="Installatie van $(cat /mnt/SLICE-A/install-date)"
newMenuNameStringSliceB="Installatie van $(cat /mnt/SLICE-B/install-date)"


newMenuStringBeheer="$(echo $menuStringBeheer | sed "s|$menuNameStringBeheer|$newMenuNameStringBeheer|g")"
newMenuStringSliceA="$(echo $menuStringSliceA | sed "s|$menuNameStringSliceA|$newMenuNameStringSliceA|g")"
newMenuStringSliceB="$(echo $menuStringSliceB | sed "s|$menuNameStringSliceB|$newMenuNameStringSliceB|g")"


if [ -n "$newMenuStringBeheer" ];then
	sed -i "s|$menuStringBeheer|$newMenuStringBeheer|g" /boot/grub/grub.cfg
fi

if [ -n "$newMenuStringSliceA" ];then
	sed -i "s|$menuStringSliceA|$newMenuStringSliceA|g" /boot/grub/grub.cfg
fi

if [ -n "$newMenuStringSliceB" ]; then
	sed -i "s|$menuStringSliceB|$newMenuStringSliceB|g" /boot/grub/grub.cfg
fi

}

cleanup()
{
umount /mnt/boot/efi 2>/dev/null
umount /mnt 2>/dev/null
}
trap cleanup INT TERM EXIT


# set error file so every 'announce' call below will call the appended scriptures just one time!
runner=0


announce "Setting up filesystems..." && \
mkfs.ext4 -F -L SLICE-A ${targetDisk}3 && mkfs.ext4 -F -L SLICE-B ${targetDisk}4
check_fail $?

announce "Mounting filesystems..." && \
mkdir -p /mnt/SLICE-A && mkdir -p /mnt/SLICE-B && mount ${targetDisk}3 /mnt/SLICE-A && mount ${targetDisk}4 /mnt/SLICE-B 
check_fail $?

announce "Setting package mirror..." && \
mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig && wget -O /etc/pacman.d/mirrorlist "https://www.archlinux.org/mirrorlist/?country=NL&protocol=https&ip_version=4&use_mirror_status=on" && sed -i '/ /s/^#//g' /etc/pacman.d/mirrorlist

announce "Installing packages to first slice..." && \
pacstrap /mnt/SLICE-A ${packages}
check_fail $?

announce "Setting package mirror..." && \
arch-chroot /mnt/SLICE-A mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig && arch-chroot /mnt/SLICE-A wget -O /etc/pacman.d/mirrorlist "https://www.archlinux.org/mirrorlist/?country=NL&protocol=https&ip_version=4&use_mirror_status=on" && arch-chroot /mnt/SLICE-A sed -i '/ /s/^#//g' /etc/pacman.d/mirrorlist

announce "Setting up networking..." && \
for i in networks/*; do cp $i /mnt/SLICE-A/etc/netctl; done && arch-chroot /mnt/SLICE-A systemctl enable netctl-auto@wlan0 && arch-chroot /mnt/SLICE-A systemctl enable systemd-resolved 
check_fail $?

announce "Setting legacy network card naming..." && \
ln -sf /dev/null /mnt/SLICE-A/etc/udev/rules.d/80-net-setup-link.rules
check_fail $?

announce "Setting hostname..." && \
echo ${targetHostname} > /mnt/SLICE-A/etc/hostname
check_fail $?

# als je dit wachtwoord leest ben je al zover gevorderd dat je 't wachtwoord van mij mag hebben :)
announce "Setting up users..." && \
arch-chroot /mnt/SLICE-A useradd -m "leerling" && arch-chroot /mnt/SLICE-A useradd -m "leraar" && arch-chroot /mnt/SLICE-A useradd -m "beheer" && arch-chroot /mnt/SLICE-A sh -c "echo -e \"r3pelsteeltje\nr3pelsteeltje\" | passwd leraar" && arch-chroot /mnt/SLICE-A sh -c "echo -e \"r3pelsteeltje\nr3pelsteeltje\" | passwd beheer" && arch-chroot /mnt/SLICE-A usermod beheer -a -G wheel
check_fail $?

announce "Setting root password..." && \
arch-chroot /mnt/SLICE-A sh -c "echo -e \"${targetRootPw}\n${targetRootPw}\" |  passwd root"
check_fail $?

announce "Setting root shell.." && \
arch-chroot /mnt/SLICE-A chsh -s /usr/bin/zsh 
check_fail $?

#announce "Enabling services..." && \
#arch-chroot /mnt/SLICE-A systemctl enable gdm.service
#check_fail $?

announce "Setting languages..." && \
arch-chroot /mnt/SLICE-A echo "nl_NL.UTF-8 UTF-8" > /etc/locale.gen && locale-gen
check_fail $?

announce "Setting timezone..." && \
rm -f /mnt/SLICE-A/etc/localtime; arch-chroot /mnt/SLICE-A ln -s /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime
check_fail $?

announce "Preparing runner scripts for next boot..." && \
cp /srv/skLinux/skLinux.service /mnt/SLICE-A/etc/systemd/system/ && arch-chroot /mnt/SLICE-A systemctl enable skLinux.service
check_fail $?

announce "Copying service files over..." && \
cp -a /srv/skLinux /mnt/SLICE-A/srv/
check_fail $?

announce "Copying over initial configuration from slice A to slice B..." && \
rsync -aAxXv --progress -W /mnt/SLICE-A/* /mnt/SLICE-B
check_fail $?

announce "Setting installation date" && \
echo "$(date '+%F')" > /mnt/SLICE-A/install-date && echo "$(date '+%F') (backup)" > /mnt/SLICE-B/install-date
check_fail $?

announce "Setting up fstab..." && \
genfstab -U -p /mnt/SLICE-A > /mnt/SLICE-A/etc/fstab && genfstab -U -p /mnt/SLICE-B > /mnt/SLICE-B/etc/fstab
check_fail $?

announce "Updating bootloader..." && \
updateGrub
check_fail $?

announce "Set option to boot from first slice on reboot..."
grub-reboot 2
check_fail $?

exit 0











mkdir -p /mnt/SLICE-A; mkdir -p /mnt/SLICE-B
mkfs.ext4 -F -L SLICE-A /dev/sda3 && mkfs.ext4 -F -L SLICE-B /dev/sda4 && mount /dev/sda3 /mnt/SLICE-A && mount /dev/sda4 /mnt/SLICE-B && pacstrap /mnt/SLICE-A base && pacstrap /mnt/SLICE-B base && sync && umount  /mnt/SLICE-A &&  umount /mnt/SLICE-B && updateGrub && poweroff



pacstrap /mnt gnome firefox remmina chromium libreoffice-fresh-nl

pacstrap /mnt base-devel fakeroot jshon expac git wget

arch-chroot /mnt bash -c "useradd builder;echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers; usermod builder -a -G wheel"

arch-chroot /mnt bash -c "cd /tmp; sudo -u builder wget https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=packer; mv PKGBUILD\?h\=packer PKGBUILD; sudo -u builder makepkg; pacman -U packer-*.pkg.tar.xz --noconfirm"

arch-chroot /mnt sudo -u builder packer -S --noconfirm ssvnc python2-pycha-hg bsdmainutils epoptes-bzr epoptes-client-bzr


