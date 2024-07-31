#!/bin/bash

set -e

EXTRACT_OTA=../../../prebuilts/extract-tools/linux-x86/bin/ota_extractor
MKDTBOIMG=../../../system/libufdt/utils/src/mkdtboimg.py
UNPACKBOOTIMG=../../../system/tools/mkbootimg/unpack_bootimg.py
ROM_ZIP=$1

declare -a DTBO_PANEL_PATCHES=(
    "Garnet:dsi_n16_42_02_0b_dsc_vid"
    "Garnet:dsi_n16_36_0d_0a_dsc_vid"
    "Garnet:dsi_n16_41_02_0c_dsc_vid"
)

error_handler() {
    if [[ -d $extract_out ]]; then
        echo "Error detected, cleaning temporal working directory $extract_out"
        rm -rf $extract_out
    fi
}

trap error_handler ERR

function usage() {
	echo "Usage: ./extract-files.sh <rom-zip>"
	exit 1
}

function get_path() {
	echo "$extract_out/$1"
}

function mkdtboimg() {
	$MKDTBOIMG $@
}

function unpackbootimg() {
	$UNPACKBOOTIMG $@
}

function extract_ota() {
    $EXTRACT_OTA $@
}

if [[ ! -f $UNPACKBOOTIMG ]]; then
	echo "Missing $UNPACKBOOTIMG, are you on the correct directory?"
	exit 1
fi

if [[ ! -f $EXTRACT_OTA ]]; then
	echo "Missing $EXTRACT_OTA, are you on the correct directory and have built the ota_extractor target?"
	exit 1
fi

if [[ -z $ROM_ZIP ]] || [[ ! -f $ROM_ZIP ]]; then
	usage
fi

# Create needed directories
for dir in ./modules/dlkm ./modules/ramdisk ./images ./images/dtbs; do
    rm -rf $dir
    mkdir -p $dir
done

# Extract the OTA package
extract_out=$(mktemp -d)
echo "Using $extract_out as working directory"

echo "Extracting the payload from $ROM_ZIP"
unzip $ROM_ZIP payload.bin -d $extract_out

echo "Extracting OTA images"
extract_ota -payload $extract_out/payload.bin -output_dir $extract_out -partitions boot,dtbo,vendor_boot,vendor_dlkm

# BOOT
echo "Extracting the kernel image from boot.img"
out=$extract_out/boot-out
mkdir $out

echo "Extracting at $out"
unpackbootimg --boot_img $(get_path boot.img) --out $out --format mkbootimg

echo "Done. Copying the kernel"
cp $out/kernel ./images/kernel
echo "Done"

# VENDOR_BOOT
echo "Extracting the ramdisk kernel modules and DTB"
out=$extract_out/vendor_boot-out
mkdir $out

echo "Extracting at $out"
unpackbootimg --boot_img $(get_path vendor_boot.img) --out $out --format mkbootimg

echo "Done. Extracting the ramdisk"
mkdir $out/ramdisk
unlz4 $out/vendor_ramdisk00 $out/vendor_ramdisk
cpio -i -F $out/vendor_ramdisk -D $out/ramdisk

echo "Copying all ramdisk modules"
for module in $(find $out/ramdisk -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist"); do
	echo "Copying $(basename $module)"
	cp $module ./modules/ramdisk/
done

# VENDOR_DLKM
echo "Extracting the dlkm kernel modules"
out=$extract_out/vendor_dlkm

echo "Extracting at $out"
fsck.erofs --extract="$out" $(get_path vendor_dlkm.img)

echo "Done. Extracting the vendor dlkm"

echo "Copying all dlkm modules"
for module in $(find $out/lib -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist"); do
	echo "Copying $(basename $module)"
	cp $module ./modules/dlkm/
done

# Extract DTBO and DTBs
echo "Extracting DTBO and DTBs"

curl -sSL "https://raw.githubusercontent.com/PabloCastellano/extract-dtb/master/extract_dtb/extract_dtb.py" > ${extract_out}/extract_dtb.py

# Copy DTB
python3 "${extract_out}/extract_dtb.py" "${extract_out}/vendor_boot-out/dtb" -o "${extract_out}/dtbs" > /dev/null
find "${extract_out}/dtbs" -type f -name "*.dtb" \
    -exec cp {} ./images/dtbs/ \; \
    -exec printf "  - dtbs/" \; \
    -exec basename {} \;

python3 "${extract_out}/extract_dtb.py" "${extract_out}/dtbo.img" -o "${extract_out}/dtbo" > /dev/null
for DTBO_PANEL_PATCH in "${DTBO_PANEL_PATCHES[@]}"; do
    DTBO_PANEL_PATCH=(${DTBO_PANEL_PATCH//:/ })
    device=${DTBO_PANEL_PATCH[0]}
    panel=${DTBO_PANEL_PATCH[1]}
    find "${extract_out}/dtbo" -type f -name "*${device}*.dtb" -exec grep -q "${panel}" {} \; \
        -exec bash -c '
            dt_node="$(fdtget -t s "{}" /__symbols__ "'${panel}'")";
            panel_height="$(fdtget -t i "{}" $dt_node "qcom,mdss-pan-physical-height-dimension")";
            panel_width="$(fdtget -t i "{}" $dt_node "qcom,mdss-pan-physical-width-dimension")";
            fdtput -t li "{}" "$dt_node" qcom,mdss-pan-physical-height-dimension "$((panel_height / 10))";
            fdtput -t li "{}" "$dt_node" qcom,mdss-pan-physical-width-dimension "$((panel_width / 10))";
            fdtput -t i "{}" "$dt_node" qcom,dsi-supported-dfps-list 60 120 90;
            fdtput -t i "{}" "$dt_node" qcom,mdss-dsi-bl-min-level 8;
        ' \; \
        -exec printf "    + Fixed up panel dimensions and removed 30hz of ${panel} in dtbo/" \; \
        -exec basename {} \;
done
mkdtboimg \
    create "./images/dtbo.img" --page_size=4096 "${extract_out}/dtbo/"*.dtb
echo "    + Generated images/dtbo.img"

rm -rf $extract_out
echo "Extracted files successfully"
