targetDisk=/dev/sda

mkdir -p /mnt/SLICE-A; mkdir -p /mnt/SLICE-B
if [ -z "$(mount  | grep ${targetDisk}3)" ]; then mount ${targetDisk}3 /mnt/SLICE-A; fi
if [ -z "$(mount  | grep ${targetDisk}4)" ]; then mount ${targetDisk}4 /mnt/SLICE-B; fi

find /boot -name "*-fallback.img" -exec mv {} {}.disabled \;

grub-mkconfig -o /boot/grub/grub.cfg || fatalError

uuidSliceA=$(blkid -o value -s UUID ${targetDisk}3)
uuidSliceB=$(blkid -o value -s UUID ${targetDisk}4)

menuStringSliceA="$(grep -e $uuidSliceA -e "^menuentry" /boot/grub/grub.cfg)"
menuStringSliceB="$(grep -e $uuidSliceB -e "^menuentry" /boot/grub/grub.cfg)"

menuNameStringSliceA="$(echo $menuStringSliceA | cut -f2 -d\')"
menuNameStringSliceB="$(echo $menuStringSliceB | cut -f2 -d\')"

newMenuNameStringSliceA="Installatie van 19 juni 1948"
newMenuNameStringSliceA="Installatie van 25 aug 1949"

newMenuStringSliceA="$(echo $menuStringSliceA | sed "s/$menuNameStringSliceA/$newMenuNameStringSliceA/g\)"

exit 1
newMenuStringSliceB="$(echo $menuStringSliceB | sed \"s/$menuNameStringSliceB/$newMenuNameStringSliceB/g\")"

echo $newMenuStringSliceA
echo $newMenuStringSliceB

