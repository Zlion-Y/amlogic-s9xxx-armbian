#!/usr/bin/env bash
set -euo pipefail

image=$1
source_tree=$2
kernel_repo=${3:-Zlion-Y/kernel}
work=$(mktemp -d)
loop=
cleanup() {
    for path in "$work/root/boot" "$work/root"; do
        if mountpoint -q "$path"; then umount "$path" || return; fi
    done
    if [[ -n "$loop" ]]; then losetup -d "$loop" || return; fi
    rm -r -- "$work"
}
trap cleanup EXIT
mkdir -p "$work/root"
gzip -dc -- "$image" | dd of="$work/image.img" bs=4M iflag=fullblock conv=sparse status=none
loop=$(losetup --find --show --read-only --partscan "$work/image.img")
fsck.fat -n "${loop}p1"
e2fsck -fn "${loop}p2"
root="$work/root"
mount -o ro,noload "${loop}p2" "$root"
mount -o ro "${loop}p1" "$root/boot"
boot="$root/boot"

board="$source_tree/build-armbian/armbian-files/different-files/w152d"
cmp "$boot/aml_autoscript" "$board/bootfs/aml_autoscript"
test ! -e "$boot/u-boot.ext"
grep -Fx 'LINUX=/zImage' "$boot/uEnv.txt"
grep -Fx 'INITRD=/uInitrd' "$boot/uEnv.txt"
grep -Fx 'FDT=/dtb/amlogic/meson-gxlx4-w152d.dtb' "$boot/uEnv.txt"
test -s "$boot/dtb/amlogic/meson-gxlx4-w152d.dtb"
uuid=$(blkid -p -s UUID -o value "${loop}p2")
grep -E "^APPEND=.*root=UUID=$uuid .*console=ttyAML0,921600n8" "$boot/uEnv.txt"
grep -E "^UUID=$uuid[[:space:]]+/[[:space:]]+ext4" "$root/etc/fstab"
test "$(stat -c %s "$boot/zImage")" -le 52428800
test "$(stat -c %s "$boot/uInitrd")" -le 25165824
cmp "$boot/uInitrd" "$boot/uInitrd-6.12.118-ophub"
cmp "$boot/zImage" "$boot/vmlinuz-6.12.118-ophub"
grep -Fx "KERNEL_REPO='$kernel_repo'" "$root/etc/ophub-release"
grep -Fx "BOARD='w152d'" "$root/etc/ophub-release"
test "$(cat "$root/etc/modules-load.d/w152d.conf")" = sprdwl_ng
grep -Fx 'CONFIG_WCN_BSP_DRIVER_BUILDIN=y' "$boot/config-6.12.118-ophub"
grep -Fx 'CONFIG_DYNAMIC_DEBUG=y' "$boot/config-6.12.118-ophub"
sprdwl=$(find "$root/usr/lib/modules/6.12.118-ophub" -name 'sprdwl_ng.ko*' -type f -print -quit)
test -n "$sprdwl"
test "$(modinfo -F depends "$sprdwl")" = cfg80211
test "$(readlink "$root/etc/systemd/system/multi-user.target.wants/armbian-front-panel.service")" = ../armbian-front-panel.service
dash -n "$root/usr/libexec/armbian-front-panel"
grep -F armbian-tf "$root/etc/custom_service/start_service.sh"
printf '%s  %s\n' f77c4dfab1ff114113586cc9ff193869de8bab2c4205e4a0ce5a57be456a918d "$root/usr/lib/armbian/armbian-firstlogin" | sha256sum -c -
(
    cd "$root/usr/lib/firmware"
    for file in wcnmodem.bin wifi_56630001_3ant.ini; do
        test "$(readlink "$file")" = "uwe5622_sc3255/$file"
        cmp "$file" "uwe5622_sc3255/$file"
    done
    sha256sum -c <<'SUMS'
2515a0a09d8e94da63aa2769b6457eee3c56c300641675da3aeb5ede09dacfaf  wcnmodem.bin
4c95dac0bf3681e1af31e89d6bd54494ce183839cf4a2e19c5953e2b243398f7  wifi_56630001_3ant.ini
119b87ce30875734a67462f7293fb8fe85acf3270fe8b78c978ae24be7715a80  uwe5622/wcnmodem.bin
SUMS
)
echo W152D_FINAL_ACTION_IMAGE_VERIFIED
