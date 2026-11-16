#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the UAPI headers of the out-of-tree vendor modules next to the
# kernel's own. Userspace HALs include these headers (drm/sde_drm.h,
# linux/msm_kgsl.h, ...), and on 6.6 they only exist in the modules tree.
#
# usage: garnet_install_module_uapi.sh <modules root> <header include dir>

set -eu

modules_root=$1
dst=$2

if [ ! -d "$modules_root" ]; then
	echo "WARNING: $modules_root not found, not installing its UAPI headers" >&2
	exit 0
fi

# The trailing slash makes find follow a symlinked modules root.
find "$modules_root/" -type d -name uapi | LC_ALL=C sort | while read -r uapi; do
	cp -rf "$uapi"/* "$dst"/

	# These are laid out as uapi/<component>/<header path>, but userspace
	# includes them by header path alone.
	for component in audio display camera vidc; do
		if [ -d "$uapi/$component" ]; then
			cp -rf "$uapi/$component"/* "$dst"/
		fi
	done

	if [ -f "$uapi/ubwcp_ioctl.h" ]; then
		mkdir -p "$dst/linux"
		cp -f "$uapi/ubwcp_ioctl.h" "$dst/linux/"
	fi
done

find "$dst" \( -name Kbuild -o -name Android.mk \) -delete
