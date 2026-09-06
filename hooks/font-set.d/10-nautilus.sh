#!/usr/bin/env bash
# hexciri:summary=Re-stamp the system font into gtk-4.0/gtk.css and restart Nautilus
# shellcheck disable=SC1091
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

gtk4_file="$HOME/.config/gtk-4.0/gtk.css"
template_file="$THPM_CURRENT_THEME_DIR/gtk.css"

# Return the chosen system font minus its size, falling back to Sans when a
# bare gsettings read fails (matches 10-gtk.sh's system_font()).
system_font() {
    local font
    if command -v gsettings >/dev/null 2>&1; then
        font="$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | sed -e "s/^'//" -e "s/'$//" -e 's/ [0-9.]*$//')"
    fi
    printf '%s\n' "${font:-Sans}"
}

# hexciri-font calls: hexciri-hook font-set "<Family Name>". Prefer that
# explicit font when given, otherwise fall back to the gsettings value.
requested="${1:-}"
requested="$(printf '%s' "$requested" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/ [0-9.]*$//')"
font="${requested:-$(system_font)}"

# Nothing to do if no theme has rendered gtk.css yet.
if [[ ! -f $template_file ]]; then
    success "GTK - Nautilus (no theme yet)"
    exit 0
fi

mkdir -p "$(dirname "$gtk4_file")"

# Always rewrite from scratch via a temp + install: ~/.config/gtk-4.0/gtk.css
# may be a symlink, and editing in place would silently convert it into a
# disconnected regular file.
tmp_css="$(mktemp)"
sed "s/@SYSTEM_FONT@/$font/g" "$template_file" > "$tmp_css"
install -m 644 "$tmp_css" "$gtk4_file"
rm -f "$tmp_css"

if command -v nautilus >/dev/null 2>&1; then
    nautilus -q 2>/dev/null || true
fi
success "GTK font restamped + Nautilus refreshed"
exit 0