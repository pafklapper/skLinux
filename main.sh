#/bin/sh

# bash run options
set -o pipefail

initVars()
{
installationDirectory="$(dirname $(realpath "$0"))"
. $installationDirectory/globalVariables
. $installationDirectory/globalFunctions
logFile=/var/log/skLinux.log
}

main()
{
initVars;cd $installationDirectory

clear
logp beginsection
logp info  "wachten op de netwerkverbinding... " && waitForNetwork


mountEnv=""
# check which platform 
if [ -n "$(mount | grep "${targetDisk}${partPrefix}2 on / type" )" ]; then
	# dit is de beheer partitie
	mountEnv="be"
elif [ -n "$(mount | grep "${targetDisk}${partPrefix}3 on / type")" ];then
	# dit is SLICE A
	if [ -f /install-date ]; then
		mountEnv="A"
	fi
elif [ -n "$(mount | grep "${targetDisk}${partPrefix}4 on / type")" ];then
	# dit is SLICE B
	if [ -f /install-date ]; then
		mountEnv="B"
	fi
fi

# update
if ! isGitRepoUptodate;then
	git pull

	#run update magic
fi

# check if this is an install env


if [ "$mountEnv" = "be" ]; then
	logp info "BEHEER omgeving geladen.."

	mkdir -p /mnt/SLICE-A && mkdir -p /mnt/SLICE-B
	if mount ${targetDisk}${partPrefix}3 /mnt/SLICE-A && [ -f /mnt/SLICE-A/install-date ] && mount ${targetDisk}${partPrefix}4 /mnt/SLICE-B && [ -f /mnt/SLICE-B/install-date ]; then
		logp info "SLICES succesvol gemount.."
	else
		if [ -f /skLinuxGoooo ]; then
			logp info "Installatie zal worden hervat!"
			if cat /dev/null > /srv/skLinux/stage1.runnerFile && sh $installationDirectory/stage1.sh; then
				rm -f /skLinuxGoooo
				logp endsection
				logp info "Installatie succesvol! De computer is nu klaar voor gebruik en zal over vijf seconde vanzelf opnieuw opstarten!"
				sleep 5 reboot
			else
				logp fatal "Installatie helaas mislukt! :("
			fi
		fi
	fi
elif [ "$mountEnv" = "A" ]; then
	logp info "SLICE-A omgeving geladen.."
elif [ "$mountEnv" = "B" ]; then
	logp info "SLICE-B omgeving geladen.."
else
	logp info "USBINSTALL omgeving geladen.."
	logp info "Installatie zal worden gestart.."
	logp middlesection
	if cat /dev/null > /srv/skLinux/stage0.runnerFile && sh $installationDirectory/stage0.sh; then
		logp endsection
		logp info "Installatie succesvol! Druk op een knop om de computer opnieuw op te starten en verder te gaan met de installatie!"
		read; reboot
	else
		logp fatal "Installatie helaas mislukt! :("
	fi
fi

}
main $@
