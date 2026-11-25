#!/usr/bin/env bash
# sim31: Devi desktop 2026-11-24 20:09 MST, dokoz, RTX 4080 Super + AMD
# Granite Ridge Radeon 610M iGPU. Installer ran AMD path then Nvidia path,
# which unconditionally installed nvidia-open-dkms while EndeavourOS base
# already had nvidia-open installed; the two conflict, pacman prompted
# [y/N], --noconfirm answered No, installer died at line 1104.
# Extracts the GPU block verbatim from a given install.sh and runs it
# with stubbed lspci/pacman/yay/run_pacman, in 5 scenarios + negative
# control on the unpatched file.
set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
BASE=/tmp/gpu-fix
HYBRID_LSPCI='00:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD103 [GeForce RTX 4080 SUPER] [10de:2702] (rev a1)
00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Granite Ridge [Radeon 610M] [1002:13c0] (rev cb)'

run_gpu() { # $1=install.sh $2=installed pkgs (space list) $3=lspci text
  local file="$1" installed="$2" lspci_text="$3" block="$BASE/gpu-block.sh" log="$BASE/gpu-run.log"
  local start end
  start=$(grep -n '^# --- GPU detection and drivers ---' "$file" | cut -d: -f1)
  end=$(grep -n '^# --- Hyprland version trap ---' "$file" | cut -d: -f1); end=$((end-1))
  sed -n "${start},${end}p" "$file" > "$block"
  : > "$log"
  INSTALLED="$installed" LSPCI_TEXT="$lspci_text" GPU_LOG="$log" bash -c '
    set -eu
    step() { printf "STEP: %s\n" "$1" >> "$GPU_LOG"; }
    info() { printf "INFO: %s\n" "$1" >> "$GPU_LOG"; }
    warn() { printf "WARN: %s\n" "$1" >> "$GPU_LOG"; }
    die()  { printf "ERROR: %s\n" "$1" >> "$GPU_LOG"; exit 1; }
    lspci() { printf "%s\n" "$LSPCI_TEXT"; }
    pacman() {
      if [ "$1" = "-Q" ]; then
        case " $INSTALLED " in *" $2 "*) return 0;; *) return 1;; esac
      fi
      return 0
    }
    sudo() {
      # Pascal removal path: sudo pacman -R --noconfirm <pkg>
      if [ "${1:-}" = "pacman" ] && [ "${2:-}" = "-R" ]; then
        printf "SUDO-REMOVE: %s\n" "${@: -1}" >> "$GPU_LOG"; return 0
      fi
      printf "SUDO: %s\n" "$*" >> "$GPU_LOG"; return 0
    }
    yay() { printf "YAY: %s\n" "$*" >> "$GPU_LOG"; return 0; }
    install_kernel_headers() { printf "HEADERS\n" >> "$GPU_LOG"; return 0; }
    run_pacman() {
      local label="$1"; shift
      # reproduce the real conflict: installing nvidia-open-dkms while
      # nvidia-open is installed fails, exactly as on Devi desktop.
      case " $* " in
        *" nvidia-open-dkms "*)
          case " $INSTALLED " in *" nvidia-open "*) printf "PACMAN-FAIL: nvidia-open-dkms conflicts nvidia-open\n" >> "$GPU_LOG"; return 1;; esac
          ;;
      esac
      printf "PACMAN: %s\n" "$*" >> "$GPU_LOG"; return 0
    }
    source "$0"
  ' "$block"
  return $?
}

# --- 0. preconditions ---
bash -n "$BASE/install-new.sh" && ok "bash -n patched install.sh" || bad "bash -n patched install.sh"
grep -q 'install_nvidia_open()' "$BASE/install-new.sh" && ok "helper install_nvidia_open present" || bad "helper missing"
grep -q 'run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open-dkms' "$BASE/install-new.sh" && bad "unconditional nvidia-open-dkms install still present" || ok "no unconditional nvidia-open-dkms install"

# --- 1. negative control: unpatched, Devi exact scenario ---
if run_gpu "$BASE/install-old.sh" "nvidia-open" "$HYBRID_LSPCI"; then
  bad "unpatched hybrid run unexpectedly succeeded (bug not reproduced)"
else
  grep -q 'PACMAN-FAIL: nvidia-open-dkms conflicts nvidia-open' "$BASE/gpu-run.log" && ok "unpatched dies on Devi exact conflict (bug reproduced)" || bad "unpatched died, not on the conflict"
fi

# --- 2. patched, Devi exact scenario: nvidia-open already installed ---
if run_gpu "$BASE/install-new.sh" "nvidia-open" "$HYBRID_LSPCI"; then
  ok "patched hybrid run succeeds with nvidia-open preinstalled"
else bad "patched hybrid run failed"; tail -5 "$BASE/gpu-run.log"; fi
grep -q 'PACMAN: -S --needed --noconfirm nvidia-open nvidia-utils' "$BASE/gpu-run.log" && ok "patched installs nvidia-open (not dkms) when it is already present" || bad "patched did not install nvidia-open"
grep -q 'PACMAN:.*nvidia-open-dkms' "$BASE/gpu-run.log" && bad "patched still tried to install nvidia-open-dkms in Devi scenario" || ok "patched never installs nvidia-open-dkms in Devi scenario"
grep -q 'PACMAN: -S --needed --noconfirm mesa vulkan-radeon' "$BASE/gpu-run.log" && ok "patched still installs Mesa/Vulkan for AMD iGPU" || bad "AMD Mesa step missing"
grep -q 'Hybrid AMD iGPU' "$BASE/gpu-run.log" && ok "hybrid wording present" || bad "hybrid wording missing"

# --- 3. clean Turing system: neither driver installed ---
if run_gpu "$BASE/install-new.sh" "" "$HYBRID_LSPCI"; then ok "clean Turing run succeeds"; else bad "clean Turing run failed"; fi
grep -q 'PACMAN: -S --needed --noconfirm nvidia-open nvidia-utils' "$BASE/gpu-run.log" && ok "clean system defaults to prebuilt nvidia-open" || bad "clean system did not default to nvidia-open"
grep -q 'HEADERS' "$BASE/gpu-run.log" && bad "clean nvidia-open run needlessly installed kernel headers" || ok "clean nvidia-open run skips dkms headers"

# --- 4. dkms already installed: keep dkms ---
if run_gpu "$BASE/install-new.sh" "nvidia-open-dkms" "$HYBRID_LSPCI"; then ok "dkms-preinstalled run succeeds"; else bad "dkms run failed"; fi
grep -q 'PACMAN: -S --needed --noconfirm nvidia-open-dkms nvidia-utils' "$BASE/gpu-run.log" && ok "dkms variant kept when already installed" || bad "dkms variant not kept"
grep -q 'HEADERS' "$BASE/gpu-run.log" && ok "dkms path installs kernel headers" || bad "dkms path skipped headers"

# --- 5. AMD-only laptop (Framework): no Nvidia at all ---
AMD_ONLY='00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1 [1002:15bf]'
if run_gpu "$BASE/install-new.sh" "" "$AMD_ONLY"; then ok "AMD-only run succeeds"; else bad "AMD-only run failed"; fi
grep -q 'nvidia' "$BASE/gpu-run.log" && bad "AMD-only run touched nvidia" || ok "AMD-only run never touches nvidia"

# --- 6. Pascal with nvidia-open preinstalled: remove first, then 580xx ---
PASCAL='00:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP102 [GeForce GTX 1080 Ti] [10de:1b06]'
if run_gpu "$BASE/install-new.sh" "nvidia-open" "$PASCAL"; then ok "Pascal run succeeds"; else bad "Pascal run failed"; tail -5 "$BASE/gpu-run.log"; fi
grep -q 'SUDO-REMOVE: nvidia-open' "$BASE/gpu-run.log" && ok "Pascal removes conflicting nvidia-open first" || bad "Pascal did not remove nvidia-open"
grep -q 'YAY: -S --needed --noconfirm nvidia-580xx-dkms' "$BASE/gpu-run.log" && ok "Pascal installs nvidia-580xx from AUR" || bad "Pascal did not install 580xx"

# --- 7. fingerprints (same dir, so absolute paths agree) ---
cp "$BASE/install-old.sh" "$BASE/same/install.sh"; bash "$BASE/same/install.sh" --print-fingerprints > "$BASE/fp-old.txt"
cp "$BASE/install-new.sh" "$BASE/same/install.sh"; bash "$BASE/same/install.sh" --print-fingerprints > "$BASE/fp-new.txt"
for k in upstream patch provision; do
  [ "$(grep "^$k=" "$BASE/fp-old.txt")" = "$(grep "^$k=" "$BASE/fp-new.txt")" ] && ok "$k fingerprint stable" || bad "$k fingerprint moved"
done
[ "$(grep '^system=' "$BASE/fp-old.txt")" != "$(grep '^system=' "$BASE/fp-new.txt")" ] && ok "system fingerprint moved (one full installer re-run on next update)" || bad "system fingerprint did not move"

echo "sim31: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
