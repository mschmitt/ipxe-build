#!/bin/bash
builddir="$(dirname "$(readlink -f "$0")")"
qemu-system-x86_64 -curses -m 2G -enable-kvm \
	-smbios type=1,manufacturer=ipxe-build,serial=d155bd71 \
	-cdrom file="${builddir}/images/ipxe-cdrom.iso"
