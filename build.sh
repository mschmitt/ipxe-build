#!/bin/bash

MAKEOPTS="-j 4"
builddir="$(dirname "$(readlink -f "$0")")"
srcdir="${builddir}/../ipxe/src/"
embed="${builddir}/stage1_embed.cfg"
hddimg="${builddir}/images/ipxe.hdd.img"
mount="${builddir}/mnt"

build_host=$(hostname --fqdn)
build_date=$(date '+%F %T')
build_rev=$(git rev-parse HEAD)

# Replicate our own customizations into ipxe compile environment
cp -v "${builddir}/config/general.h" "${srcdir}/config/local/general.h"
cp -v "${builddir}/config/branding.h" "${srcdir}/config/local/branding.h"
sed -i "s/_buildinfo_/${build_date} ${build_host}\\\n${build_rev}/" \
	"${srcdir}/config/local/branding.h"
set -e

# Build the PXE binary
make -C "${srcdir}" clean
make -C "${srcdir}" bin/ipxe.pxe EMBED="${embed}"
cp -v "${srcdir}/bin/ipxe.pxe" "${builddir}/images/ipxe.pxe"
sudo cp -v "${builddir}/images/ipxe.pxe" /srv/tftp/

# Build the UNDI pxe binary
make -C "${srcdir}" clean
make -C "${srcdir}" bin/undionly.kpxe EMBED="${embed}"
cp -v "${srcdir}/bin/undionly.kpxe" "${builddir}/images/undionly.kpxe"
sudo cp -v "${builddir}/images/undionly.kpxe" /srv/tftp/

# Build the Linux Kernel type image
make -C "${srcdir}" clean
make -C "${srcdir}" bin/ipxe.lkrn EMBED="${embed}"
cp -v "${srcdir}/bin/ipxe.lkrn" "${builddir}/images/ipxe.lkrn"
cp -v "${builddir}/images/ipxe.lkrn" /var/www/html/ipxe/

# Build the ISO image
make -C "${srcdir}" clean
make -C "${srcdir}" bin/ipxe.iso EMBED="${embed}"
cp -v "${srcdir}/bin/ipxe.iso" "${builddir}/images/ipxe-cdrom.iso"
cp -v "${builddir}/images/ipxe-cdrom.iso" /var/www/html/ipxe/

# Build the USB image
make -C "${srcdir}" clean
make -C "${srcdir}" bin/ipxe.usb EMBED="${embed}"
cp -v "${srcdir}/bin/ipxe.iso" "${builddir}/images/ipxe-usb.img"
cp -v "${builddir}/images/ipxe-usb.img" /var/www/html/ipxe/

# Disable Linux Kernel type image so we can build the EFI image
sed -i '/IMAGE_BZIMAGE/d' "${srcdir}/config/local/general.h"

# Build EFI image
make -C "${srcdir}" clean
make -C "${srcdir}" bin-x86_64-efi/ipxe.efi EMBED="${embed}"
cp -v "${srcdir}/bin-x86_64-efi/ipxe.efi" "${builddir}/images/ipxe.efi"
cp -v "${builddir}/images/ipxe.efi" /var/www/html/ipxe/ipxe.efi

set +e

# Assemble hybrid EFI/BIOS bootable harddisk image

function cleanup(){
	echo "cleanup mount point ${mount}"
	mount | grep ${loopdev}
	if [[ $? -eq 0 ]]
	then
		sudo umount "${mount}" && rmdir "${mount}"
		if [[ $? -ne 0 ]]
		then
			echo "Failed to cleanup temp mount point ${mount}"
			exit 1
		fi
	fi

	echo "cleanup loop device ${loopdev}"
	sudo losetup -l | grep ${loopdev}
	if [[ $? -eq 0 ]]
	then
		sudo losetup -d ${loopdev}
		if [[ $? -ne 0 ]]
		then
			echo "Failed to cleanup loop device ${loopdev}"
			exit 1
		fi
	fi
}
trap cleanup INT QUIT TERM EXIT

echo "create file ${hddimg}"
if [[ -e "${hddimg}" ]]
then
	chmod 644 "${hddimg}"
fi
dd if=/dev/zero of="${hddimg}" bs=1M count=16
if [[ $? -ne 0 ]]
then
	echo "Failed at disk image creation."
	exit 1
fi

echo "partitioning ${hddimg}"
/sbin/parted "${hddimg}" <<End
mklabel gpt 
mkpart primary fat32 2048s 4095s
mkpart primary fat32 4096s 100%
set 2 legacy_boot on
set 2 esp on
set 2 boot on
End
if [[ $? -ne 0 ]]
then
	echo "Failed at disk image partitioning."
	exit 1
fi


echo "create loop device"
loopdev=$(sudo losetup --find --show --partscan "${hddimg}")
if [[ $? -ne 0 ]]
then
	echo "Failed at loop device creation."
	exit 1
fi

echo "create filesystem on ${loopdev}p2"
sudo mkfs.vfat -n ESP ${loopdev}p2
if [[ $? -ne 0 ]]
then
	print "Failed at creating loop device filesystem."
	exit 1
fi

echo "mount ${loopdev}p2 to ${mount}"
mkdir -p "${mount}"
sudo mount ${loopdev}p2 "${mount}" -o uid=$UID
if [[ $? -ne 0 ]]
then
	echo "Failed mount ${loopdev}p2 to ${mount}."
	exit 1
fi

echo "create directory structure"
mkdir -p "${mount}/EFI/BOOT" && mkdir "${mount}/syslinux"
if [[ $? -ne 0 ]]
then
	echo "Failed at create directory structure."
	exit 1
fi

echo "copy ${builddir}/images/ipxe.efi firmware"
cp -v "${builddir}/images/ipxe.efi" "${mount}/EFI/BOOT/BOOTX64.EFI" &&
  echo "FS0:\EFI\BOOT\BOOTX64.EFI" > "${mount}/startup.nsh"
if [[ $? -ne 0 ]]
then
	echo "Failed at copy ipxe.efi firmware."
	exit 1
fi

echo "copy ${builddir}/images/ipxe.lkrn firmware"
cp -v "${builddir}/images/ipxe.lkrn" "${mount}/syslinux/"
if [[ $? -ne 0 ]]
then
	print "Failed at copy ipxe.lkrn firmware."
	exit 1
fi

echo "writing syslinux configuration"
cat > "${mount}/syslinux/syslinux.cfg" <<-End
DEFAULT ipxe
LABEL ipxe
 SAY Now booting the ipxe kernel from SYSLINUX...
 KERNEL ipxe.lkrn
End

echo "install syslinux"
sudo extlinux --install "${mount}/syslinux/" 
if [[ $? -ne 0 ]]
then
	echo "Failed at installing syslinux."
	exit 1
fi

echo "locate syslinux MBR"
if [[ -s /usr/lib/syslinux/mbr/gptmbr.bin ]]
then
	mbr='/usr/lib/syslinux/mbr/gptmbr.bin'
elif [[ -s /usr/lib/syslinux/bios/gptmbr.bin ]]
then
	mbr='/usr/lib/syslinux/bios/gptmbr.bin'
else
	echo "couldn't find gptmbr.bin - Install syslinux-common?"
	exit 1
fi

echo "copy syslinux MBR from $mbr to ${loopdev}"
sudo dd bs=440 count=1 conv=notrunc if="${mbr}" of=${loopdev}

sudo umount "${mount}"
sudo rmdir "${mount}"
sudo losetup -d ${loopdev}
chmod 444 "${hddimg}"

# Done assembling hybrid EFI/BIOS bootable harddisk image

# Additionally convert to qcow2 for Vbox/Qemu EFI booting
if [[ -e "$(dirname "${hddimg}")/ipxe.hdd.qcow2" ]]
then
	chmod 644 "$(dirname "${hddimg}")/ipxe.hdd.qcow2"
fi
qemu-img convert -f raw -O qcow2 "${hddimg}" "$(dirname "${hddimg}")/ipxe.hdd.qcow2"
chmod 444 "$(dirname "${hddimg}")/ipxe.hdd.qcow2"

# Copy to my synced folder
if [[ -d  "${HOME}/Sync/Workdocs/iPXE" ]]
then
	cp -r -v "${builddir}/images" "${HOME}/Sync/Workdocs/iPXE"
fi
