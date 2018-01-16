#!/bin/bash

# sanity checks
if [ -z "$1" ] || ! [ -b "$1" ]; then
	echo "ARG not a blockdevice!"
	exit 0
fi

# constants initialisation
DEBUG="false"

targetRootPw="1234"
targetHostname="skLinuxClient"
targetDisk="$1"
packages="base grub os-prober vim net-tools arch-install-scripts wget curl dialog wpa_supplicant wpa_actiond grml-zsh-config openssh git"

# variables initialisation
# do not change this line! 
VAR_f=/tmp/./install.sh.vZn

function debug {
	if [ "$DEBUG" = "TRUE" ]; then
		return 0
	else
		return 1;
	fi
}

function set_error_f {
if [ "$VAR_f" = "FALSE" ]; then
	err_f=`mktemp /tmp/$0.XXX` || { echo couldnt make ERROR file; exit 1; }
	sed -i "/^VAR_f=FALSE/c\VAR_f=$err_f" $0
	debug && echo "setting error file: $err_f"
	VAR_f=$err_f
elif [ ! -f $VAR_f ]; then
	debug && echo "error file $VAR_f not found! creating new error file.."
	sed -i "/^VAR_f=/c\VAR_f=FALSE" $0
	sh $0
	exit 0;
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
	fi
}

function check_fail {
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
		>&2 echo "OK!"
		if [ -z "$(grep -e '^finished=' $VAR_f )"  ]; then
                	echo "finished=$runner" >> $VAR_f
		else
			sed -i "/^finished=/c\finished=$(($finished+1))" $VAR_f
                fi
	fi
}

fatalError()
{
	echo "FATALE FOUT: $@"; read
	exit 1
}

cleanup()
{
umount /mnt/boot/efi 2>/dev/null
umount /mnt 2>/dev/null
}
trap cleanup INT TERM EXIT

# functions

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

# set error file so every 'announce' call below will call the appended scriptures just one time!
set_error_f
runner=0

announce "Setting up harddisk..." && \
sgdisk -Z ${targetDisk} && sync && \
parted --script ${targetDisk} mklabel gpt mkpart ESP fat32 1MiB 200MiB mkpart primary ext4 200MiB 8% mkpart primary ext4 8% 54% mkpart primary ext4 54% 100% set 1 boot on &&  mkfs.vfat -F32 -n ESP ${targetDisk}1 && mkfs.ext4 -F -L BEHEER ${targetDisk}2 
check_fail $?

announce "Installing base packages..." && \
mount ${targetDisk}2 /mnt && mkdir -p /mnt/boot/efi && mount ${targetDisk}1 /mnt/boot/efi && pacstrap /mnt ${packages} 
check_fail $?

announce "Setting up mounts" && \
genfstab -U -p /mnt > /mnt/etc/fstab
check_fail $?

announce "Setting up bootloader (GRUB)..." && \
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck --removable && arch-chroot sed -i '/^GRUB_TERMINAL/c\GRUB_TERMINAL=console' /etc/default/grub && sed -i '/^GRUB_TIMEOUT=/c\GRUB_TIMEOUT=15' /etc/default/grub && sed -i '/^GRUB_DEFAULT=/c\GRUB_DEFAULT=saved' /etc/default/grub && sed -i '/^GRUB_DISABLE_SUBMENU=/c\GRUB_DISABLE_SUBMENU=y' && sed -i '/^GRUB_HIDDEN_TIMEOUT=/c\GRUB_HIDDEN_TIMEOUT=5' /etc/default/grub sed -i '/^GRUB_SAVEDEFAULT=/c\GRUB_SAVEDEFAULT=\"true\"' /etc/default/grub/etc/default/grub && echo "## Uncomment to disable submenu\nGRUB_DISABLE_SUBMENU=y" >> /etc/default/grub && arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
check_fail $?

announce "Setting legacy network card naming..." && \
ln -sf /dev/null /mnt/etc/udev/rules.d/80-net-setup-link.rules
check_fail $?

announce "Setting up networking..."  && \
arch-chroot /mnt systemctl enable dhcpcd@eth0 && systemctl enable netctl-auto@wlan0 && arch-chroot /mnt systemctl enable systemd-resolved 
check_fail $?

announce "Setting hostname..." && \
echo ${targetHostname} > /mnt/etc/hostname 
check_fail $?

announce "Setting root password..." && \ 
arch-chroot /mnt sh -c "echo -e \"${targetRootPw}\n${targetRootPw}\" |  passwd root"
check_fail $?

announce "Setting root shell.." && \
arch-chroot /mnt chsh -s /usr/bin/zsh 
check_fail $?

announce "Setting ready install scripts for next boot..." && \
sleep 2
check_fail $?


# reboot / warning / telegram hier
exit 0


mkdir -p /mnt/SLICE-A; mkdir -p /mnt/SLICE-B
mkfs.ext4 -F -L SLICE-A /dev/sda3 && mkfs.ext4 -F -L SLICE-B /dev/sda4 && mount /dev/sda3 /mnt/SLICE-A && mount /dev/sda4 /mnt/SLICE-B && pacstrap /mnt/SLICE-A base && pacstrap /mnt/SLICE-B base && sync && umount  /mnt/SLICE-A &&  umount /mnt/SLICE-B && updateGrub && poweroff



pacstrap /mnt gnome firefox remmina chromium libreoffice-fresh-nl

pacstrap /mnt base-devel fakeroot jshon expac git wget

arch-chroot /mnt bash -c "useradd builder;echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers; usermod builder -a -G wheel"

arch-chroot /mnt bash -c "cd /tmp; sudo -u builder wget https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=packer; mv PKGBUILD\?h\=packer PKGBUILD; sudo -u builder makepkg; pacman -U packer-*.pkg.tar.xz --noconfirm"

arch-chroot /mnt sudo -u builder packer -S --noconfirm ssvnc python2-pycha-hg bsdmainutils epoptes-bzr epoptes-client-bzr

