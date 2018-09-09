#!/bin/bash -xe

# android-tools-fsutils should be installed as
# "sudo apt-get install android-tools-fsutils"

help() {

bn=`basename $0`
cat << EOF
usage $bn <option> device_node

options:
  -h				displays this help message
  -s				only get partition size
  -np 				not partition.
  -f soc_name			flash android image file with soc_name
  -F soc_name			determine the device_node's offset to flash bootloader and flash default android image file
					 soc     				offset(KB)
					default					   1
					imx8dv					  16
					imx8qm/imx8qxp/imx8mq			  33
  -a				only flash image to slot_a
  -b				only flash image to slot_b
  -c card_size			optional setting: 7 / 14 / 28
					If not set, use partition-table.img
					If set to 7, use partition-table-7GB.img for 7GB SD card
EOF

}

# parse command line
moreoptions=1
node="na"
soc_name=""
cal_only=0
card_size=0
bootloader_offset=1
vaild_gpt_size=17
not_partition=0
not_format_fs=0
slot=""
systemimage_file="system.img"
systemimage_raw_file="system_raw.img"
vendor_file="vendor.img"
vendor_raw_file="vendor_raw.img"
partition_file="partition-table.img"
g_sizes=0
append_soc_name=0
while [ "$moreoptions" = 1 -a $# -gt 0 ]; do
	case $1 in
	    -h) help; exit ;;
	    -s) cal_only=1 ;;
	    -f) append_soc_name=1 ; soc_name=$2; shift;;
	    -F) soc_name=$2; shift;;
	    -c) card_size=$2; shift;;
	    -np) not_partition=1 ;;
	    -nf) not_format_fs=1 ;;
	    -a) slot="_a" ;;
	    -b) slot="_b" ;;
	    *)  moreoptions=0; node=$1 ;;
	esac
	[ "$moreoptions" = 0 ] && [ $# -gt 1 ] && help && exit
	[ "$moreoptions" = 1 ] && shift
done

if [ ${card_size} -ne 0 ] && [ ${card_size} -ne 7 ] && [ ${card_size} -ne 14 ] && [ ${card_size} -ne 28 ]; then
    help; exit;
fi

if [ "${soc_name}" = "imx8dv" ]; then
    bootloader_offset=16
fi


if [ "${soc_name}" = "imx8qm" -o "${soc_name}" = "imx8qxp" -o "${soc_name}" = "imx8mq" ]; then
    bootloader_offset=33
fi

echo "${soc_name} bootloader offset is: ${bootloader_offset}"

if [ "${soc_name}" != "" ] && [ "${append_soc_name}" -eq 1 ]; then
    soc_name="-${soc_name}"
else
    soc_name=""
fi

if [ ! -e ${node} ]; then
	help
	exit
fi

SUFFIX=""
[[ ${node} =~ "loop" ]] && SUFFIX="p"

# dump partitions
if [ "${cal_only}" -eq "1" ]; then
gdisk -l ${node} 2>/dev/null | grep -A 20 "Number  "
exit
fi

function get_partition_size
{
    eval $(gdisk -l ${node} | awk -v name=$1 '($0~name)&&($0="start_sector="$2";end_sector="$3)')
    # 1 sector = 512 bytes. This will change unit from sector to MBytes.
    let g_size=$(( $(($end_sector - $start_sector + 1)) >> 11 ))
}

function format_partition
{
    num=$(gdisk -l ${node} | awk -v name=$1 '($0~name)&&($0=$1)')
    if [ ${num} -gt 0 ] 2>/dev/null; then
        echo "format_partition: $1:${node}${SUFFIX}${num} ext4"
        mkfs.ext4 -F ${node}${SUFFIX}${num} -L$1
    fi
}

function erase_partition
{
    num=$(gdisk -l ${node} | awk -v name=$1 '($0~name)&&($0=$1)')
    if [ ${num} -gt 0 ] 2>/dev/null; then
        get_partition_size $1
        echo "erase_partition: $1 : ${node}${SUFFIX}${num} $2M"
        #dd if=/dev/zero of=${node}${SUFFIX}${num} bs=1k conv=fsync
    fi
}

function flash_partition
{
    for num in $(gdisk -l ${node} | awk -v name=$1 '($0~name)&&($0=$1)' ORS=" ")
    do
        if [ $? -eq 0 ]; then
            if [ $(echo ${1} | grep "system") != "" ] 2>/dev/null; then
                img_name=${systemimage_raw_file}
            elif [ $(echo ${1} | grep "vendor") != "" ] 2>/dev/null; then
                img_name=${vendor_raw_file}
            else
                img_name="${1%_*}${soc_name}.img"
            fi
            echo "flash_partition: ${img_name} ---> ${node}${SUFFIX}${num}"
            dd if=${img_name} of=${node}${SUFFIX}${num} conv=fsync
        fi
    done
}

function format_android
{
    echo "formating android images"
    format_partition userdata
    format_partition cache
    erase_partition presistdata
    erase_partition fbmisc
    erase_partition misc
}

function loop_partscan
{
    file=$(losetup -a | awk -v node=${node} '($0~node)&&($0=$NF)' |  tr -d "()")
    losetup -d ${node}
    losetup ${node} --partscan ${file}
}

function make_partition
{
    if [ ${card_size} -gt 0 ]; then
        partition_file="partition-table-${card_size}GB.img"
    fi
    echo "make gpt partition for android: ${partition_file}"
    dd if=${partition_file} of=${node} bs=1k count=${vaild_gpt_size} conv=fsync
    [[ ${SUFFIX} == 'p' ]] && loop_partscan
}

function flash_android
{
    boot_partition="boot"${slot}
    recovery_partition="recovery"${slot}
    system_partition="system"${slot}
    vendor_partition="vendor"${slot}
    vbmeta_partition="vbmeta"${slot}

    bootloader_file="u-boot${soc_name}.imx"
    flash_partition ${boot_partition}
    flash_partition ${recovery_partition}
    simg2img ${systemimage_file} ${systemimage_raw_file}
    flash_partition ${system_partition}
    rm ${systemimage_raw_file}
    simg2img ${vendor_file} ${vendor_raw_file}
    flash_partition ${vendor_partition}
    rm ${vendor_raw_file}
    flash_partition ${vbmeta_partition}
    echo "erase_partition: uboot : ${node}"
    echo "flash_partition: ${bootloader_file} ---> ${node}"
    first_partition_offset=`gdisk -l ${node} | grep ' 1 ' | awk '{print $2}'`
    # the unit of first_partition_offset is sector size which is 512 Byte.
    count_bootloader=`expr ${first_partition_offset} / 2 - ${bootloader_offset}`
    echo "the bootloader partition size: ${count_bootloader}"
    dd if=/dev/zero of=${node} bs=1k seek=${bootloader_offset} conv=fsync count=${count_bootloader}
    dd if=${bootloader_file} of=${node} bs=1k seek=${bootloader_offset} conv=fsync
}

if [ "${not_partition}" -eq "1" ] ; then
    flash_android
    exit
fi

make_partition
sleep 3
for i in `cat /proc/mounts | grep "${node}" | awk '{print $2}'`; do umount $i; done
hdparm -z ${node}

# backup the GPT table to last LBA for sd card.
echo -e 'r\ne\nY\nw\nY\nY' |  gdisk ${node}

format_android
flash_android
