#!/bin/bash

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
targetRootPw="r3pelsteeltje"
targetHostname="skLinuxClient"
packages="base grub os-prober vim net-tools arch-install-scripts wget curl dialog wpa_supplicant wpa_actiond grml-zsh-config openssh git rsync"

# variables initialisation
# do not change this line! 
VAR_f=$installationDirectory/stage0.runnerFile

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

# set error file so every 'announce' call below will call the appended scriptures just one time!
runner=0

announce "Setting up harddisk..." && \
sgdisk -Z ${targetDisk} && sync && \
parted --script ${targetDisk} mklabel gpt mkpart ESP fat32 1MiB 200MiB mkpart primary ext4 200MiB 8% mkpart primary ext4 8% 54% mkpart primary ext4 54% 100% set 1 boot on &&  mkfs.vfat -F32 -n ESP ${targetDisk}1 && mkfs.ext4 -F -L BEHEER ${targetDisk}2 
check_fail $?

announce "Setting package mirror..." && \
mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig && wget -O /etc/pacman.d/mirrorlist "https://www.archlinux.org/mirrorlist/?country=NL&protocol=https&ip_version=4&use_mirror_status=on" && sed -i '/ /s/^#//g' /etc/pacman.d/mirrorlist
check_fail $?

announce "Installing base packages..." && \
mount ${targetDisk}2 /mnt && mkdir -p /mnt/boot/efi && mount ${targetDisk}1 /mnt/boot/efi && pacstrap /mnt ${packages} 
check_fail $?

announce "Setting up fstab..." && \
genfstab -U -p /mnt > /mnt/etc/fstab
check_fail $?

announce "Setting up bootloader (GRUB)..." && \
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck --removable && \
arch-chroot /mnt sed -i '/GRUB_TERMINAL/c\GRUB_TERMINAL=console' /etc/default/grub && \
arch-chroot /mnt sed -i '/GRUB_DEFAULT=/c\GRUB_DEFAULT=saved' /etc/default/grub && \
arch-chroot /mnt sed -i '/GRUB_HIDDEN_TIMEOUT=/c\GRUB_HIDDEN_TIMEOUT=5' /etc/default/grub && \
arch-chroot /mnt sed -i '/GRUB_SAVEDEFAULT=/c\GRUB_SAVEDEFAULT=\"true\"' /etc/default/grub && \
arch-chroot /mnt sed -i '/GRUB_DISABLE_SUBMENU=/c\GRUB_DISABLE_SUBMENU=y' /etc/default/grub && \
arch-chroot /mnt echo -e "## Uncomment to disable submenu\nGRUB_DISABLE_SUBMENU=y" >> /etc/default/grub && \
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
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

announce "Preparing runner scripts for next boot..." && \
cp /srv/skLinux/skLinux.service /mnt/etc/systemd/system/ && arch-chroot /mnt systemctl enable skLinux.service
check_fail $?

announce "Copying service files over..." && \
cp -a /srv/skLinux /mnt/srv/
check_fail $?

announce "Marking BEHEER for first install..." && \
arch-chroot /mnt touch /skLinuxGoooo
check_fail $?

announce "Setting EFI file to reboot to the internal harddisk on next boot ..." && \
sleep 1 # EFIBOOTMGR
check_fail $?

# reboot / warning / telegram hier
exit 0
