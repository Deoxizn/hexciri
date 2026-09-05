#!/bin/bash
# hexciri recon — ISO-side boot-failure diagnosis. One password prompt, verdicts out.
#   curl -fsSL https://hexciri.dirty.pizza/recon.sh | bash
set -uo pipefail
say() { echo -e "\e[0;36m[recon]\e[0m $*"; }
verdict() { echo -e "\e[1;33m[verdict]\e[0m $*"; }

ESP="$(lsblk -rn -o NAME,FSTYPE | awk '$2=="vfat"{print "/dev/"$1}' | head -n 1)"
LUKSDEV="$(blkid -o device -t TYPE=crypto_LUKS 2>/dev/null | head -n 1)"
[[ -n ${ESP:-} ]] || { verdict "NO ESP FOUND (no vfat partition)"; exit 1; }
[[ -n ${LUKSDEV:-} ]] || { verdict "NO LUKS PARTITION FOUND"; exit 1; }
say "esp=$ESP luks=$LUKSDEV"
mkdir -p /mnt
mount "$ESP" /mnt 2>/dev/null || true

echo "--- entries ---"
cat /mnt/loader/entries/hexciri-*.conf 2>/dev/null || verdict "NO HEXCIRI ENTRIES"
# crypt UUID + hook presence need the open device:
read -rsp "luks password (once): " PW </dev/tty; echo
printf '%s' "$PW" | cryptsetup open "$LUKSDEV" cryptroot - || { verdict "LUKS OPEN FAILED (wrong password or device)"; exit 1; }
unset PW
mkdir -p /mnt/rootfs
mount /dev/mapper/cryptroot /mnt/rootfs
mount "$ESP" /mnt/rootfs/boot 2>/dev/null || true
echo "--- hooks ---"
grep HOOKS /mnt/rootfs/etc/mkinitcpio.conf 2>/dev/null || verdict "NO MKINITCPIO.CONF"
echo "--- encrypt in images ---"
for img in /mnt/rootfs/boot/initramfs-*.img; do
  [[ -f $img ]] || continue
  c=$(lsinitcpio "$img" 2>/dev/null | grep -icE "encrypt|plymouth" || true)
  echo "$(basename "$img"): encrypt-related files=$c"
  (( c > 0 )) || verdict "NO ENCRYPT HOOK in $(basename "$img")"
done
echo "--- uuid match ---"
want=$(grep -hoE 'cryptdevice=UUID=[^ :]+' /mnt/recon/loader/entries/hexciri-*.conf 2>/dev/null | head -n 1 | cut -d= -f3)
have=$(blkid -s UUID -o value "$LUKSDEV")
echo "entry=$want actual=$have"
[[ -n $want && $want == "$have" ]] || verdict "UUID MISMATCH (or missing cryptdevice=)"
echo "--- fstab ---"
cat /mnt/rootfs/etc/fstab 2>/dev/null | grep -v '^#' | grep -v '^$' || verdict "EMPTY FSTAB"
verdict "recon done"
