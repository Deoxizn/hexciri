#!/usr/bin/env python3
"""Patch live nyx 4ad23827 install.sh: hybrid AMD iGPU + Nvidia dGPU.

Root cause (Devi desktop 2026-11-24 20:09 MST, dokoz, RTX 4080 Super +
AMD Granite Ridge Radeon 610M): installer ran the AMD path (Mesa/Vulkan,
correct for the iGPU) then the Nvidia path, which unconditionally
installed nvidia-open-dkms. EndeavourOS base already ships nvidia-open
on Nvidia systems, and nvidia-open / nvidia-open-dkms conflict, so
pacman prompted [y/N], --noconfirm answered No, transaction died,
installer failed at line 1104. Fix: keep whichever Nvidia driver
variant is already installed; on a clean system install prebuilt
nvidia-open (stock Arch kernel, no dkms build, no headers), never dkms.
Pascal branch: remove a conflicting nvidia-open* first, non-interactively,
before installing nvidia-580xx from AUR, same conflict otherwise.
AMD step wording was Framework-only; hybrid is now explicit.
"""
import sys
P = "/tmp/gpu-fix/install.sh"
s = open(P).read()

old_amd = '''if [ "$HAS_AMD" -eq 1 ]; then
  step "AMD GPU detected (Framework laptop path). Installing Mesa and Vulkan, no Nvidia packages."
  run_pacman "AMD GPU drivers" -S --needed --noconfirm mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon amd-ucode linux-firmware
fi
'''
new_amd = '''# install_nvidia_open (2026-11-24, desktop hybrid bug): nvidia-open and
# nvidia-open-dkms conflict with each other, and both conflict with the
# closed nvidia / nvidia-dkms. EndeavourOS base already ships nvidia-open
# on Nvidia systems, so unconditionally installing nvidia-open-dkms made
# pacman prompt [y/N], --noconfirm answered No, and the installer died
# at the Nvidia step (Devi desktop, RTX 4080 Super + AMD 610M iGPU).
# Keep whichever driver variant is already installed; on a clean system
# install prebuilt nvidia-open (stock Arch kernel, no dkms build, no
# headers needed), never dkms. Companion utils are safe under any variant.
install_nvidia_open() {
  if pacman -Q nvidia-open-dkms >/dev/null 2>&1; then
    info "nvidia-open-dkms already installed, keeping it (not installing conflicting nvidia-open)."
    install_kernel_headers
    run_pacman "Nvidia drivers (nvidia-open-dkms)" -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif pacman -Q nvidia-open >/dev/null 2>&1; then
    info "nvidia-open already installed (EndeavourOS base), keeping it (not installing conflicting nvidia-open-dkms)."
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif pacman -Q nvidia >/dev/null 2>&1 || pacman -Q nvidia-dkms >/dev/null 2>&1; then
    info "Closed Nvidia driver already installed, keeping it (not installing conflicting nvidia-open)."
    run_pacman "Nvidia drivers (closed, already installed)" -S --needed --noconfirm nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  else
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  fi
}

if [ "$HAS_AMD" -eq 1 ]; then
  step "AMD GPU detected. Installing Mesa and Vulkan for the AMD GPU."
  info "Hybrid AMD iGPU + Nvidia dGPU: Mesa/Vulkan for AMD here, Nvidia driver below, both install."
  run_pacman "AMD GPU drivers" -S --needed --noconfirm mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon amd-ucode linux-firmware
fi
'''
assert s.count(old_amd) == 1, "AMD block not found exactly once"
s = s.replace(old_amd, new_amd)

old_turing = '''  if echo "$GPU_INFO" | grep -qiE 'RTX|GTX 16|GTX 20|GTX 30|GTX 40'; then
    step "Nvidia Turing or newer detected (RTX 4080 Super path). Installing nvidia-open."
    install_kernel_headers
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  elif echo "$GPU_INFO" | grep -qiE 'GTX 10'; then
    step "Nvidia Pascal detected (GTX 1080 Ti, 10xx path). Installing nvidia-580xx from AUR."
    warn "Pascal is legacy. nvidia-580xx is the legacy branch, end of support is coming. Do NOT install nvidia-open on this card."
    install_kernel_headers
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils
  else
    warn "Nvidia GPU found but model not matched as Turing+ or Pascal 10xx. Check lspci output above."
    warn "Defaulting to nvidia-open. If this is a Pascal 10xx card, remove nvidia-open and install nvidia-580xx-dkms and nvidia-580xx-utils from AUR instead."
    install_kernel_headers
    run_pacman "Nvidia drivers (nvidia-open)" -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland
  fi
'''
new_turing = '''  if echo "$GPU_INFO" | grep -qiE 'RTX|GTX 16|GTX 20|GTX 30|GTX 40'; then
    step "Nvidia Turing or newer detected (RTX 4080 Super path). Installing nvidia-open."
    install_nvidia_open
  elif echo "$GPU_INFO" | grep -qiE 'GTX 10'; then
    step "Nvidia Pascal detected (GTX 1080 Ti, 10xx path). Installing nvidia-580xx from AUR."
    warn "Pascal is legacy. nvidia-580xx is the legacy branch, end of support is coming. Do NOT install nvidia-open on this card."
    # Same conflict as Turing: if the base shipped nvidia-open(*), the
    # 580xx install would die on the conflict prompt. Remove the
    # conflicting driver first, non-interactively, one package at a time.
    for _conf in nvidia-open nvidia-open-dkms nvidia nvidia-dkms; do
      if pacman -Q "$_conf" >/dev/null 2>&1; then
        info "Removing conflicting $_conf before installing nvidia-580xx (Pascal cannot use it)."
        sudo pacman -R --noconfirm "$_conf" >/dev/null 2>&1 || warn "Could not remove $_conf, nvidia-580xx install may conflict."
      fi
    done
    install_kernel_headers
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils
  else
    warn "Nvidia GPU found but model not matched as Turing+ or Pascal 10xx. Check lspci output above."
    warn "Defaulting to nvidia-open. If this is a Pascal 10xx card, remove nvidia-open and install nvidia-580xx-dkms and nvidia-580xx-utils from AUR instead."
    install_nvidia_open
  fi
'''
assert s.count(old_turing) == 1, "Nvidia block not found exactly once"
s = s.replace(old_turing, new_turing)

# No remaining unconditional nvidia-open-dkms install in the Nvidia step.
assert "nvidia-open-dkms nvidia-utils" in s  # only the keep-dkms branch
assert s.count("run_pacman \"Nvidia drivers (nvidia-open)\" -S --needed --noconfirm nvidia-open-dkms") == 0
open(P, "w").write(s)
print("patched ok, lines:", s.count("\n") + 1)
