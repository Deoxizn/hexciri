#!/bin/bash
# hexciri bootstrap — Arch ISO → fully automatic hexciri install.
#
#   curl -LO https://hexciri.dirty.pizza/hexciri
#   sh hexciri
#
# 10 things are typed, everything else is automatic: username, hostname,
# timezone, filesystem, encryption, channel, mode (full/free), disk
# (+wipe confirm), and a final reboot prompt.
# Run as root on the Arch ISO live environment. DESTRUCTIVE: wipes $DISK (full mode).
set -euo pipefail

SITE="https://hexciri.dirty.pizza"
REPO="https://github.com/Deoxizn/hexciri.git"
BOOTSTRAP_REV=14   # bump on every bootstrap.sh change; printed first so reports are unambiguous
CHANNEL="stable"
KERNEL_PICK=""      # always: installer auto-picks (stock; LTS pinned on legacy NVIDIA). Custom kernels are post-install via hexciri-kernel.
START_EPOCH=$(date +%s)   # for the "install took Xm Ys" banner before the reboot prompt

info() { echo -e "\e[0;36m[hexciri:bootstrap]\e[0m $*"; }
ok()   { echo -e "\e[0;32m[hexciri:bootstrap]\e[0m $*"; }
err()  { echo -e "\e[0;31m[hexciri:bootstrap]\e[0m $*" >&2; }

(( EUID == 0 )) || { err "run as root on the Arch ISO (curl ... | bash)"; exit 1; }
command -v pacstrap &>/dev/null || { err "not an Arch ISO (no pacstrap)"; exit 1; }
for cmd in sfdisk parted mkfs.fat mkfs.ext4 blkid findmnt cryptsetup arch-chroot git curl; do
  command -v "$cmd" &>/dev/null && continue
  case "$cmd" in
    sfdisk|findmnt|blkid) pkg=util-linux ;;
    mkfs.fat) pkg=dosfstools ;;
    mkfs.ext4) pkg=e2fsprogs ;;
    cryptsetup) pkg=cryptsetup ;;
    arch-chroot) pkg=arch-install-scripts ;;
    *) pkg="$cmd" ;;
  esac
  info "ISO is missing $cmd — installing $pkg..."
  pacman -Sy --noconfirm "$pkg" || { err "cannot install $pkg (network up?)"; exit 1; }
done

# ── optional pre-flight: prove the exact cryptsetup command chain on a
#    throwaway file BEFORE any disk is touched (no reboot needed) ──
if [[ ${1:-} == --test-luks ]]; then
  command -v cryptsetup &>/dev/null || { err "cryptsetup not available at all — cannot test"; exit 1; }
  info "LUKS self-test on a throwaway file (no real disks touched)..."
  IMG=/tmp/hexciri-luks-test.img
  rm -f "$IMG"
  dd if=/dev/zero of="$IMG" bs=1M count=64 status=none
  PASS="hexciri-luks-selftest"
  printf '%s' "$PASS" | cryptsetup luksFormat --batch-mode --type luks2 "$IMG" - \
    || { err "luksFormat failed on test image"; exit 1; }
  printf '%s' "$PASS" | cryptsetup open "$IMG" crypttest - \
    || { err "luksOpen failed on test image"; exit 1; }
  [[ -b /dev/mapper/crypttest ]] || { err "mapper crypttest did not appear"; exit 1; }
  cryptsetup close crypttest || { err "luksClose failed on test image"; exit 1; }
  rm -f "$IMG"
  ok "LUKS self-test passed — luksFormat/open/close round-trip works"
  exit 0
fi

info "site: $SITE"
info "hexciri bootstrap rev $BOOTSTRAP_REV"

# ── the only 9 typed things: identity first, disk choices last ──
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
read -rp "hostname [hexciri]: " HOSTNAME </dev/tty; HOSTNAME="${HOSTNAME:-hexciri}"
# timezone defaults to GeoIP-detected (Enter accepts); typed override always works
DETECTED_TZ=""
DETECTED_TZ="$(curl -fsSL --max-time 8 https://ipapi.co/timezone 2>/dev/null | tr -d '[:space:]' || true)"
[[ -f /usr/share/zoneinfo/$DETECTED_TZ ]] || DETECTED_TZ="$(curl -fsSL --max-time 8 https://ipinfo.io/timezone 2>/dev/null | tr -d '[:space:]' || true)"
[[ -f /usr/share/zoneinfo/$DETECTED_TZ ]] || DETECTED_TZ="$(curl -fsSL --max-time 8 'http://ip-api.com/line?fields=timezone' 2>/dev/null | tr -d '[:space:]' || true)"
if [[ ! -f /usr/share/zoneinfo/$DETECTED_TZ ]]; then
  DETECTED_TZ="$(curl -fsSL --max-time 8 https://worldtimeapi.org/api/ip 2>/dev/null | grep -oE '"timezone":"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)"
fi
[[ -f /usr/share/zoneinfo/$DETECTED_TZ ]] || DETECTED_TZ=""
[[ -n $DETECTED_TZ ]] || DETECTED_TZ="UTC"
read -rp "timezone [$DETECTED_TZ]: " TIMEZONE </dev/tty; TIMEZONE="${TIMEZONE:-$DETECTED_TZ}"
[[ $TIMEZONE != *".."* && -f /usr/share/zoneinfo/"$TIMEZONE" ]] || { err "unknown timezone: $TIMEZONE"; exit 1; }
timedatectl set-ntp true 2>/dev/null || true

# ── filesystem: ext4 default (simplest, robust, no snapshot stack to feed);
#    btrfs optional (checksums + zstd transparent compression) ──
read -rp "filesystem [ext4/btrfs, default ext4]: " FS </dev/tty
FS="${FS,,}"; FS="${FS:-ext4}"
[[ $FS == ext4 || $FS == btrfs ]] || { err "filesystem must be ext4|btrfs"; exit 1; }
command -v "mkfs.$FS" &>/dev/null || { err "mkfs.$FS missing on this ISO"; exit 1; }
mkfs_root() { # $1 = device (force: re-runs must overwrite previous filesystems)
  if [[ $FS == btrfs ]]; then mkfs.btrfs -f -q -L hexciri "$1" >/dev/null
  else mkfs.ext4 -F -q -L hexciri "$1" >/dev/null; fi
  local want have
  [[ $FS == btrfs ]] && want=btrfs || want=ext4
  have="$(blkid -s TYPE -o value "$1" 2>/dev/null || true)"
  [[ $have == "$want" ]] || { err "format verification failed on $1 (want $want, got ${have:-nothing}) — aborting"; exit 1; }
}

# ── partition (mode chosen up top; free mode reuses the ESP, touches nothing else) ──
read -rp "channel [stable/bleeding, default stable]: " CHANNEL </dev/tty
CHANNEL="${CHANNEL,,}"; CHANNEL="${CHANNEL:-stable}"
[[ $CHANNEL == stable || $CHANNEL == bleeding ]] || { err "channel must be stable|bleeding"; exit 1; }
info "channel: $CHANNEL"

# ── encryption: LUKS2 on the root partition; passphrase = the user password ──
read -rp "encrypt the root filesystem with LUKS? [y/N]: " luks_ans </dev/tty
LUKS=no
[[ $luks_ans =~ ^[Yy]$ ]] && LUKS=yes
[[ $LUKS == yes ]] && LUKSPASS="$USERPASS"

info "kernel: auto (stock; LTS pinned on legacy NVIDIA by the installer)"



# ── disk goes last: destructive choices right before partitioning.
# full mode wipes; free mode shares (reuses the ESP, touches nothing else) ──
read -rp "full disk wipe or install into free space? [full/free, default full]: " MODE </dev/tty
MODE="${MODE,,}"; MODE="${MODE:-full}"
[[ $MODE == full || $MODE == free ]] || { err "mode must be full|free"; exit 1; }
if [[ $MODE == free ]]; then
  command -v parted &>/dev/null || { err "parted missing on this ISO — cannot map free space"; exit 1; }
fi
info "disks:"; lsblk -d -n -o NAME,SIZE,MODEL | sed 's/^/  \/dev\//'
if [[ $MODE == full ]]; then
  read -rp "disk to WIPE (e.g. nvme0n1, sda — bare name): " DISK </dev/tty
else
  read -rp "disk with unpartitioned free space (e.g. nvme0n1 — bare name): " DISK </dev/tty
fi
[[ -b /dev/$DISK ]] || { err "no such disk: /dev/$DISK"; exit 1; }
if [[ $DISK == nvme* ]]; then P=p; else P=""; fi
# ── clear stale state from previous runs (lingering mounts, open mappers) ──
umount -R /mnt 2>/dev/null || true
command -v cryptsetup &>/dev/null && cryptsetup close cryptroot 2>/dev/null || true

# ── summary + final confirm (nothing touched until this passes) ──
echo ""
info "your choices:"
printf '  %-10s %s\n' \
  "mode"     "$MODE" \
  "disk"     "/dev/$DISK" \
  "fs"       "$FS" \
  "encryption" "$LUKS" \
  "channel"  "$CHANNEL" \
  "kernel"   "auto" \
  "hostname" "$HOSTNAME" \
  "username" "$USERNAME" \
  "password" "(set, hidden)" \
  "timezone" "$TIMEZONE" \
echo ""
if [[ $MODE == full ]]; then
  read -rp "WIPE /dev/$DISK and install? [y/N]: " GO </dev/tty
else
  read -rp "Install into free space on /dev/$DISK? [y/N]: " GO </dev/tty
fi
[[ $GO =~ ^[Yy]$ ]] || { err "aborted — disk untouched"; exit 1; }
echo ""

# ── partition ──
if [[ $MODE == full ]]; then
  info "partitioning /dev/$DISK (full wipe)..."
  wipefs -af "/dev/$DISK" >/dev/null
  sfdisk -q "/dev/$DISK" <<EOF
label: gpt
,1G,U
;
EOF
  partprobe "/dev/$DISK"
  udevadm settle 2>/dev/null || sleep 2
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
    partprobe "/dev/$DISK"
  udevadm settle 2>/dev/null || sleep 2
    ESP="/dev/$DISK$P$((LASTNUM+1))"; FORMAT_ESP=yes
    info "created new ESP $ESP"
  fi
  LASTNUM="$(lsblk -rn -o NAME "/dev/$DISK" | grep -oE '[0-9]+$' | sort -n | tail -n 1)"
  echo "start=$((ROOT_START/512)), size=$((ROOT_SIZE/512)), type=83" | sfdisk --append -q "/dev/$DISK"
  partprobe "/dev/$DISK"
  udevadm settle 2>/dev/null || sleep 2
  ROOT="/dev/$DISK$P$((LASTNUM+1))"
  info "created root $ROOT ($((ROOT_SIZE/1024/1024/1024))G $FS)"
  [[ $FORMAT_ESP == yes ]] && mkfs.fat -F32 "$ESP" >/dev/null
fi

if [[ $LUKS == yes ]]; then
  info "encrypting $ROOT with LUKS2 (passphrase = the user password)..."
  printf '%s' "$LUKSPASS" | cryptsetup luksFormat --batch-mode --type luks2 "$ROOT" -
  printf '%s' "$LUKSPASS" | cryptsetup open "$ROOT" cryptroot -
  [[ -b /dev/mapper/cryptroot ]] || { err "cryptroot did not come up — aborting"; exit 1; }
  mkfs_root /dev/mapper/cryptroot
  mount /dev/mapper/cryptroot /mnt
else
  mkfs_root "$ROOT"
  mount "$ROOT" /mnt
fi
mkdir -p /mnt/boot
mount "$ESP" /mnt/boot

# ── kernel set: exactly one bootable base kernel (+custom added later by the
# installer, which also flips the default). Legacy NVIDIA (GTX 1xxx or older)
# and custom picks stage on LTS; everything else stages on stock linux ──
is_legacy_nvidia() {
  local d id
  for d in /sys/bus/pci/devices/*; do
    [[ $(<"$d/vendor") == "0x10de" ]] || continue
    [[ $(<"$d/class") == 0x03* ]] || continue
    id=$(<"$d/device")
    (( id >= 0x1340 && id < 0x1e00 )) && return 0
  done
  return 1
}
STAGE1_KERNEL=linux
if is_legacy_nvidia || [[ $KERNEL_PICK == lts ]]; then
  STAGE1_KERNEL=linux-lts
fi
is_legacy_nvidia && info "legacy NVIDIA: base kernel linux-lts"
UCODE="intel-ucode"
grep -qi "AuthenticAMD" /proc/cpuinfo && UCODE="amd-ucode"
info "base install ($STAGE1_KERNEL, $UCODE)..."
pacstrap -K /mnt base "$STAGE1_KERNEL" linux-firmware "$UCODE" \
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
info() { echo -e "\\e[0;36m[hexciri:stage2]\\e[0m \$*"; }
ok()   { echo -e "\\e[0;32m[hexciri:stage2]\\e[0m \$*"; }
err()  { echo -e "\\e[0;31m[hexciri:stage2]\\e[0m \$*" >&2; }
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

useradd -m -G wheel,lp,scanner -s /bin/bash "$USERNAME"
printf '%s:%s' "$USERNAME" "$USERPASS" | chpasswd
# root shares the user password: single-user/emergency shells stay usable
printf 'root:%s' "$USERPASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

bootctl install --esp-path=/boot >/dev/null
ROOTUUID="\$(findmnt -no UUID /)"
if [[ $LUKS == yes ]]; then
  LUKSUUID="\$(blkid -s UUID -o value $ROOT)"
  if [[ \${#LUKSUUID} -ne 36 ]]; then
    err "LUKS partition UUID did not resolve — aborting before install"
    exit 1
  fi
  ROOTOPTS="cryptdevice=UUID=\$LUKSUUID:cryptroot root=/dev/mapper/cryptroot rw quiet splash"
else
  ROOTOPTS="root=UUID=\$ROOTUUID rw quiet splash"
fi
MICRO="\$(ls /boot/*-ucode.img 2>/dev/null | head -n 1 | xargs basename 2>/dev/null || true)"
# stale entries from previous installs carry dead UUIDs — remove our own first
rm -f /boot/loader/entries/hexciri-*.conf
for img in /boot/vmlinuz-*; do
  k="\${img#/boot/vmlinuz-}"
  {
    echo "title   Hexciri (\$k)"
    echo "linux   /vmlinuz-\$k"
    [[ -n "\$MICRO" ]] && echo "initrd  /\$MICRO"
    echo "initrd  /initramfs-\$k.img"
    echo "options \$ROOTOPTS"
  } > "/boot/loader/entries/hexciri-\$k.conf"
done
echo -e "default hexciri-$STAGE1_KERNEL.conf\ntimeout 3" > /boot/loader/loader.conf
# one-shot insurance: a malformed options line boots to a timeout with no
# useful error, so refuse to continue if spacing or an empty UUID slipped in
if grep -qE '(cryptdevice|root|options) +=' /boot/loader/entries/hexciri-*.conf; then
  err "boot entry malformed (spaced key=value) — aborting before install"
  grep -H . /boot/loader/entries/hexciri-*.conf >&2 || true
  exit 1
fi

systemctl enable NetworkManager.service power-profiles-daemon.service >/dev/null

mkdir -p "/home/$USERNAME/.local/opt"
cp -r /root/hexciri-install "/home/$USERNAME/.local/opt/hexciri"
# .local is created root-owned here — hand the whole tree to the user or the
# user phase (state/share subdirs) and fish's history dir fail with EACCES
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.local"
# Split phases: system runs as root (no sudo needed), user runs as the user
# with zero sudo calls — su(1) sessions have no controlling TTY, so nothing
# here may ever depend on sudo prompting.
trap 'rm -f /root/hexciri-stage2.sh' EXIT
HEXCIRI_USER="$USERNAME" HEXCIRI_LUKS="$LUKS" bash /root/hexciri-install/install.sh --system-only -y --channel $CHANNEL${KERNEL_PICK:+ --kernel $KERNEL_PICK}
command -v fish &>/dev/null && chsh -s /usr/bin/fish "$USERNAME" || true
su - "$USERNAME" -c "cd ~/.local/opt/hexciri && ./install.sh --user-only -y"
STAGE2

info "stage 2 (chroot)..."
arch-chroot /mnt bash /root/hexciri-stage2.sh </dev/tty
rm -f /mnt/root/hexciri-stage2.sh

umount -R /mnt
ok "install complete ($HOSTNAME / $USERNAME / $CHANNEL)"
elapsed=$(( $(date +%s) - START_EPOCH ))
ok "install took $(( elapsed / 60 ))m $(( elapsed % 60 ))s"
echo ""
read -rp "Reboot now? [Y/n]: " RB </dev/tty
if [[ $RB =~ ^[Nn]$ ]]; then
  info "not rebooting — run reboot whenever ready"
else
  systemctl reboot
fi
