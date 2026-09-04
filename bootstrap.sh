#!/bin/bash
# hexciri bootstrap — Arch ISO → fully automatic hexciri install.
#
#   curl -fsSL https://hexciri.dirty.pizza/bootstrap.sh | sudo bash
#   curl -fsSL https://hexciri.dirty.pizza/bootstrap.sh | sudo bash -s -- --kernel bore
#
# Only 9 things are ever typed (everything else is automatic):
#   disk, full-disk-vs-free-space, filesystem, channel, hostname,
#   username, user password, timezone, LUKS yes/no.
# --kernel preselects the GPU kernel (else auto). Run as root on the
# Arch ISO live environment. DESTRUCTIVE: wipes $DISK (full mode).
set -euo pipefail

SITE="https://hexciri.dirty.pizza"
REPO="https://github.com/Deoxizn/hexciri.git"
CHANNEL="stable"
KERNEL_PICK=""         # --kernel=stock|lts|omarchy|bore|muqss preselects the GPU kernel (else auto)
LUKS_ASK=true
for arg in "$@"; do
  case "$arg" in
    --kernel=*) KERNEL_PICK="${arg#*=}" ;;
    --no-luks) LUKS_ASK=false; LUKS=no ;;
  esac
done
[[ -z $KERNEL_PICK || $KERNEL_PICK =~ ^(stock|lts|omarchy|bore|muqss)$ ]] || { echo "kernel must be stock|lts|omarchy|bore|muqss"; exit 1; }

info() { echo -e "\e[0;36m[hexciri:bootstrap]\e[0m $*"; }
ok()   { echo -e "\e[0;32m[hexciri:bootstrap]\e[0m $*"; }
err()  { echo -e "\e[0;31m[hexciri:bootstrap]\e[0m $*" >&2; }

(( EUID == 0 )) || { err "run as root on the Arch ISO (curl ... | sudo bash)"; exit 1; }
command -v pacstrap &>/dev/null || { err "not an Arch ISO (no pacstrap)"; exit 1; }
for cmd in sfdisk parted mkfs.fat mkfs.ext4 blkid findmnt arch-chroot git curl; do
  command -v "$cmd" &>/dev/null && continue
  case "$cmd" in
    sfdisk|findmnt|blkid) pkg=util-linux ;;
    mkfs.fat) pkg=dosfstools ;;
    mkfs.ext4) pkg=e2fsprogs ;;
    arch-chroot) pkg=arch-install-scripts ;;
    *) pkg="$cmd" ;;
  esac
  info "ISO is missing $cmd — installing $pkg..."
  pacman -Sy --noconfirm "$pkg" || { err "cannot install $pkg (network up?)"; exit 1; }
done

info "site: $SITE"

# ── the only 9 typed things ──
info "disks:"; lsblk -d -n -o NAME,SIZE,MODEL | sed 's/^/  \/dev\//'
read -rp "disk to WIPE (e.g. nvme0n1, sda — bare name): " DISK </dev/tty
[[ -b /dev/$DISK ]] || { err "no such disk: /dev/$DISK"; exit 1; }
if [[ $DISK == nvme* ]]; then P=p; else P=""; fi
read -rp "type the disk name again to confirm WIPE of /dev/$DISK: " CONFIRM </dev/tty
[[ $CONFIRM == "$DISK" ]] || { err "mismatch — aborting, disk untouched"; exit 1; }
read -rp "hostname [hexciri]: " HOSTNAME </dev/tty; HOSTNAME="${HOSTNAME:-hexciri}"
read -rp "username [hex]: " USERNAME </dev/tty; USERNAME="${USERNAME:-hex}"
for _try in 1 2 3; do
  read -rsp "password for $USERNAME: " USERPASS </dev/tty; echo
  read -rsp "confirm password: " USERPASS2 </dev/tty; echo
  if [[ -z $USERPASS ]]; then err "empty password — aborting"; exit 1; fi
  [[ $USERPASS == "$USERPASS2" ]] && break
  err "passwords do not match — try again"
  USERPASS=""
  (( _try == 3 )) && { err "3 mismatches — aborting"; exit 1; }
done
unset USERPASS2
# timezone defaults to GeoIP-detected (Enter accepts); typed override always works
DETECTED_TZ="$(curl -fsSL --max-time 8 https://ipapi.co/timezone 2>/dev/null || true)"
[[ -f /usr/share/zoneinfo/$DETECTED_TZ ]] || DETECTED_TZ="UTC"
read -rp "timezone [$DETECTED_TZ]: " TIMEZONE </dev/tty; TIMEZONE="${TIMEZONE:-$DETECTED_TZ}"
[[ $TIMEZONE != *".."* && -f /usr/share/zoneinfo/"$TIMEZONE" ]] || { err "unknown timezone: $TIMEZONE"; exit 1; }
LUKS="${LUKS:-no}"
if $LUKS_ASK; then
  read -rp "encrypt disk with LUKS? [y/N]: " luks_ans </dev/tty
  [[ $luks_ans =~ ^[Yy]$ ]] && LUKS=yes || LUKS=no
fi
if [[ $LUKS == yes ]]; then
  # disk unlock reuses the user password (one password to remember)
  LUKSPASS="$USERPASS"
fi

timedatectl set-ntp true 2>/dev/null || true

# ── filesystem: ext4 default (simplest, robust, no snapshot stack to feed);
#    btrfs optional (checksums + zstd transparent compression) ──
read -rp "filesystem [ext4/btrfs, default ext4]: " FS </dev/tty
FS="${FS,,}"; FS="${FS:-ext4}"
[[ $FS == ext4 || $FS == btrfs ]] || { err "filesystem must be ext4|btrfs"; exit 1; }
command -v "mkfs.$FS" &>/dev/null || { err "mkfs.$FS missing on this ISO"; exit 1; }
mkfs_root() { # $1 = device
  if [[ $FS == btrfs ]]; then mkfs.btrfs -q -L hexciri "$1" >/dev/null
  else mkfs.ext4 -q -L hexciri "$1" >/dev/null; fi
}

# ── full disk (wipe, like a fresh Arch) vs free space (dual-boot, untouched
#    existing partitions; reuses the existing ESP when there is one) ──
read -rp "full disk wipe or install into free space? [full/free, default full]: " MODE </dev/tty
MODE="${MODE,,}"; MODE="${MODE:-full}"
[[ $MODE == full || $MODE == free ]] || { err "mode must be full|free"; exit 1; }
if [[ $MODE == free ]]; then
  command -v parted &>/dev/null || { err "parted missing on this ISO — cannot map free space"; exit 1; }
fi

# ── channel is always asked ──
read -rp "channel [stable/bleeding, default stable]: " CHANNEL </dev/tty
CHANNEL="${CHANNEL,,}"; CHANNEL="${CHANNEL:-stable}"
[[ $CHANNEL == stable || $CHANNEL == bleeding ]] || { err "channel must be stable|bleeding"; exit 1; }
info "channel: $CHANNEL"

# ── partition ──
if [[ $MODE == full ]]; then
  info "partitioning /dev/$DISK (full wipe)..."
  wipefs -af "/dev/$DISK" >/dev/null
  sfdisk -q "/dev/$DISK" <<EOF
label: gpt
,1G,U
;
EOF
  partprobe "/dev/$DISK"; sleep 2
  ESP="/dev/$DISK$P""1"; ROOT="/dev/$DISK$P""2"
  mkfs.fat -F32 "$ESP" >/dev/null
  FORMAT_ESP=yes
else
  info "mapping free space on /dev/$DISK (existing partitions untouched)..."
  # reuse an existing ESP when present (dual-boot), else carve 1G for one
  ESP_EXIST="$(lsblk -rn -o NAME,PARTTYPE "/dev/$DISK" 2>/dev/null | awk '$2=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"{print "/dev/"$1}' | head -n 1)"
  # largest free region, in bytes
  read -r FREE_START FREE_SIZE < <(parted -m "/dev/$DISK" unit B print free 2>/dev/null \
    | awk -F: '$NF=="free;" || $NF=="free" {gsub(/B;?$/,"",$2); gsub(/B;?$/,"",$4); if ($4+0>max) {max=$4; s=$2}} END {print s+0, max+0}')
  NEED=$((30*1024*1024*1024))
  (( FREE_SIZE >= NEED )) || { err "need >=30G unpartitioned free space (found $((FREE_SIZE/1024/1024/1024))G)"; exit 1; }
  if [[ -n $ESP_EXIST ]]; then
    ESP="$ESP_EXIST"; FORMAT_ESP=no
    info "reusing existing ESP $ESP (not formatted)"
    ROOT_START=$FREE_START; ROOT_SIZE=$FREE_SIZE
  else
    (( FREE_SIZE >= NEED + 1024*1024*1024 )) || { err "need >=31G free (1G new ESP + 30G root)"; exit 1; }
    ESP_START=$FREE_START; ESP_SIZE=$((1024*1024*1024))
    ROOT_START=$((FREE_START + ESP_SIZE)); ROOT_SIZE=$((FREE_SIZE - ESP_SIZE))
    LASTNUM="$(lsblk -rn -o NAME "/dev/$DISK" | grep -oE '[0-9]+$' | sort -n | tail -n 1)"
    echo "start=$((ESP_START/512)), size=$((ESP_SIZE/512)), type=U" | sfdisk --append -q "/dev/$DISK"
    partprobe "/dev/$DISK"; sleep 2
    ESP="/dev/$DISK$P$((LASTNUM+1))"; FORMAT_ESP=yes
    info "created new ESP $ESP"
  fi
  LASTNUM="$(lsblk -rn -o NAME "/dev/$DISK" | grep -oE '[0-9]+$' | sort -n | tail -n 1)"
  echo "start=$((ROOT_START/512)), size=$((ROOT_SIZE/512)), type=83" | sfdisk --append -q "/dev/$DISK"
  partprobe "/dev/$DISK"; sleep 2
  ROOT="/dev/$DISK$P$((LASTNUM+1))"
  info "created root $ROOT ($((ROOT_SIZE/1024/1024/1024))G $FS)"
  [[ $FORMAT_ESP == yes ]] && mkfs.fat -F32 "$ESP" >/dev/null
fi

if [[ $LUKS == yes ]]; then
  printf '%s' "$LUKSPASS" | cryptsetup luksFormat --batch-mode --type luks2 "$ROOT" -
  printf '%s' "$LUKSPASS" | cryptsetup open "$ROOT" cryptroot -
  ROOTMAP="/dev/mapper/cryptroot"
  mkfs_root "$ROOTMAP"
  mount "$ROOTMAP" /mnt
else
  mkfs_root "$ROOT"
  mount "$ROOT" /mnt
fi
mkdir -p /mnt/boot
mount "$ESP" /mnt/boot

# ── base system ──
UCODE="intel-ucode"
grep -qi "AuthenticAMD" /proc/cpuinfo && UCODE="amd-ucode"
info "base install ($UCODE)..."
pacstrap -K /mnt base linux linux-lts linux-firmware "$UCODE" \
  networkmanager sudo git base-devel power-profiles-daemon nano file procps-ng \
  $([[ $LUKS == yes ]] && echo cryptsetup) $([[ $FS == btrfs ]] && echo btrfs-progs) >/dev/null
genfstab -U /mnt >> /mnt/etc/fstab
[[ $FS == btrfs ]] && sed -i '\| / btrfs |s/relatime/relatime,compress=zstd/' /mnt/etc/fstab

# ── hexciri source at the pinned ref, into the new system ──
info "fetching hexciri..."
rm -rf /mnt/root/hexciri-install
git clone --depth 1 "$REPO" /mnt/root/hexciri-install

# ── stage 2 runs inside the new system ──
cat > /mnt/root/hexciri-stage2.sh <<STAGE2
set -euo pipefail
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc 2>/dev/null || true
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME
HOSTS

useradd -m -G wheel -s /bin/bash "$USERNAME"
printf '%s:%s' "$USERNAME" "$USERPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

bootctl install --esp-path=/boot >/dev/null
LUKSFLAG="$LUKS"
ROOTDEV="$ROOT"
if [[ "\$LUKSFLAG" == yes ]]; then
  LUKSUUID="\$(blkid -s UUID -o value $ROOT)"
  # encrypt/plymouth hooks are owned by install.sh (runs next, same chroot);
  # entries just need the cryptdevice line + splash here.
  ROOTOPTS="cryptdevice=UUID=\$LUKSUUID:cryptroot root=/dev/mapper/cryptroot rw quiet splash"
else
  ROOTUUID="\$(findmnt -no UUID /)"
  ROOTOPTS="root=UUID=\$ROOTUUID rw quiet splash"
fi
MICRO="\$(ls /boot/*-ucode.img 2>/dev/null | head -n 1 | xargs basename 2>/dev/null || true)"
for k in linux linux-lts; do
  {
    echo "title   Hexciri (\$k)"
    echo "linux   /vmlinuz-\$k"
    [[ -n "\$MICRO" ]] && echo "initrd  /\$MICRO"
    echo "initrd  /initramfs-\$k.img"
    echo "options \$ROOTOPTS"
  } > "/boot/loader/entries/hexciri-\$k.conf"
done
echo -e "default hexciri-linux.conf\ntimeout 3" > /boot/loader/loader.conf

systemctl enable NetworkManager.service power-profiles-daemon.service >/dev/null

cp -r /root/hexciri-install "/home/$USERNAME/hexciri"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/hexciri"
# su(1) sessions have no controlling TTY, so sudo(8) inside install.sh could
# never prompt (fatal "a terminal is required"). Open a passwordless window
# for the install only; install.sh closes it (plus an EXIT trap here).
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USERNAME" > /etc/sudoers.d/hexciri-install
chmod 440 /etc/sudoers.d/hexciri-install
trap 'rm -f /etc/sudoers.d/hexciri-install /root/hexciri-stage2.sh' EXIT
su - "$USERNAME" -c "export HEXCIRI_STAGE2=1; cd ~/hexciri && ./install.sh -y --channel $CHANNEL${KERNEL_PICK:+ --kernel $KERNEL_PICK}"
STAGE2

info "stage 2 (chroot)..."
arch-chroot /mnt bash /root/hexciri-stage2.sh </dev/tty
rm -f /mnt/root/hexciri-stage2.sh

umount -R /mnt
ok "done. reboot → autologin straight into Niri. ($HOSTNAME / $USERNAME / $CHANNEL)"
