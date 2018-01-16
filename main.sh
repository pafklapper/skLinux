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
initVars

cd $installationDirectory
logp beginsection
logp info  "wachten op de netwerkverbinding... " && waitForNetwork


mountEnv=""
# check which platform 
if [ -n "$(mount | grep "${targetDisk}2 on / type" )" ]; then
	# dit is de beheer partitie
	mountEnv="be"
elif [ -n "$(mount | grep "${targetDisk}3 on / type")" ];then
	# dit is SLICE A
	mountEnv="A"
elif [ -n "$(mount | grep "${targetDisk}4 on / type")" ];then
	# dit is SLICE B
	mountEnv="B"
fi

# update
if ! isGitRepoUptodate;then
	git pull

	#run update magic
fi

# check if this is an install env

if [ "$mountEnv" = "be" ]; then
	if [ -z "$(lsblk -f | grep SLICE-A) ] || [ -z "$(lsblk -f | grep SLICE-B) ]; then
		logp info "Installatie zal worden voorgezet!..."
		if sh /srv/skLinux/stage1.sh; then
			logp info "Installatie succesvol!"
			logp endsection
			read; reboot
		else
			logp fatal "Installatie mislukt! Zou je dit aan Annemieke of Stan willen doorgeven? Graag met een foto/beschrijving van de foutmelding erbij"
		fi
	else
		logp info "installatie al voltrokken ?? NIET AF"
		#installatie al voltrokken
		# checken voor fouten?
	fi
elif [ -n "$mountEnv" ]; then
	# check for device validity
	logp info "Installatie zal in gang worden gezet!"
	sh $installationDirectory/stage0.sh
elif [ "$mountEnv" = "A" ] || [ "$mountEnv" = "B" ]; then
	# checken voor desktop files update?
	logp info "dit is Slice $mountEnv"
	# checken voor updates?
	systemctl start gdm
fi

# set reboot options
# start login manager lastly 
}

main $@
