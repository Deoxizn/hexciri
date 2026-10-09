#!/usr/bin/env bash
# 11-adapta.sh — retint the Adapta GTK theme from the active hexciri palette.
# Runs right after 10-gtk.sh. Opt-in only: [gtk] adapta = true in
# theme-hook.toml (default off). When off, exits quietly and the flat-sheet
# fallback in 10-gtk.sh owns GTK.
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

if ! thpm_truthy "$(thpm_config_value gtk adapta false)"; then
    exit 0
fi

adapta_dir="$HOME/.themes/Adapta"
build_py="$adapta_dir/build.py"
light_file="$THPM_LIGHT_MODE_FILE"
gtk4_dir="$HOME/.config/gtk-4.0"

if [[ ! -f "$build_py" ]]; then
    warning "Adapta not found at $adapta_dir (clone https://github.com/signaldirective/Adapta.git there first)"
    exit 0
fi

# 1. Retint Adapta from the resolved palette (dir or colors.toml both work).
python3 "$build_py" --omarchy "$THPM_COLORS_FILE_RESOLVED" || {
    warning "Adapta build failed (see above)"
    exit 1
}

# 2. Re-apply hexciri's Nautilus state rules. Every build regenerates gtk.css
# from src/, so append on every run — guarded by the marker so double-runs
# never stack the block. Scoped to nautilus-window and only when nautilus is
# installed, same as 10-gtk.sh.
if command -v nautilus >/dev/null 2>&1; then
    _fragment="$(dirname "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}")/nautilus-gtk4.fragment.css"
    adapta_gtk="$adapta_dir/gtk-4.0/gtk.css"
    if [[ -f "$_fragment" && -f "$adapta_gtk" ]]; then
        if ! grep -q "hexciri-nautilus-state" "$adapta_gtk" 2>/dev/null; then
            printf '\n' >> "$adapta_gtk"
            cat "$_fragment" >> "$adapta_gtk"
        fi
    fi
fi

# 3. Point ~/.config/gtk-4.0 at Adapta (symlinks, never copies — copies drift
# after the next theme switch). Back up a regular gtk.css once, like 10-gtk.sh.
mkdir -p "$gtk4_dir"
if [[ -f "$gtk4_dir/gtk.css" && ! -L "$gtk4_dir/gtk.css" && ! -f "$gtk4_dir/gtk.css.backup" ]]; then
    cp "$gtk4_dir/gtk.css" "$gtk4_dir/gtk.css.backup"
fi
ln -sfn "$adapta_dir/gtk-4.0/gtk.css" "$gtk4_dir/gtk.css"
ln -sfn "$adapta_dir/gtk-4.0/gtk-dark.css" "$gtk4_dir/gtk-dark.css"
if [[ -e "$gtk4_dir/assets" && ! -L "$gtk4_dir/assets" ]]; then
    rm -rf "$gtk4_dir/assets"
fi
ln -sfn "$adapta_dir/gtk-4.0/assets" "$gtk4_dir/assets"

# 4. Adapta has no light variant — gtk-theme stays Adapta in both modes.
# The -tmp toggle forces running apps to reload the theme.
if command -v gsettings >/dev/null 2>&1; then
    if [ -f "$light_file" ]; then
        gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-tmp
        gsettings set org.gnome.desktop.interface gtk-theme Adapta
    else
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-tmp-dark
        gsettings set org.gnome.desktop.interface gtk-theme Adapta
    fi
fi

if command -v pkill >/dev/null 2>&1; then
    pkill -f xdg-desktop-portal-gtk
fi

if command -v nautilus >/dev/null 2>&1; then
    # libadwaita reads the stylesheet only at startup and Nautilus survives
    # as a daemon — quit it so it respawns on the fresh theme.
    nautilus -q 2>/dev/null || true
fi
require_restart "nautilus"
success "Adapta theme updated!"
exit 0
