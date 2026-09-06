#!/usr/bin/env bash
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

output_file="$THPM_CURRENT_THEME_DIR/gtk.css"
light_file="$THPM_LIGHT_MODE_FILE"
gtk3_dir="$HOME/.config/gtk-3.0"
gtk4_dir="$HOME/.config/gtk-4.0"
gtk3_file="$gtk3_dir/gtk.css"
gtk4_file="$gtk4_dir/gtk.css"

# Live system font, stripped of its size ("Adwaita Sans 11" -> Adwaita Sans).
# omarchy-nautilus-theme stamps it into gtk-4.0/gtk.css so libadwaita apps
# match the desktop; refresh stays off the gsettings bare value so a missing
# font falls back to Sans instead of aborting.
system_font() {
    local font
    if command -v gsettings >/dev/null 2>&1; then
        font="$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | sed -e "s/^'//" -e "s/'$//" -e 's/ [0-9.]*$//')"
    fi
    printf '%s\n' "${font:-Sans}"
}

create_dynamic_theme() {
cat > "$output_file" << EOF
    @define-color background     #${primary_background};
    @define-color foreground     #${primary_foreground};
    @define-color black          #${primary_background};
    @define-color red            #${normal_red};
    @define-color green          #${normal_green};
    @define-color yellow         #${normal_yellow};
    @define-color blue           #${normal_blue};
    @define-color magenta        #${normal_magenta};
    @define-color cyan           #${normal_cyan};
    @define-color white          #${normal_white};
    @define-color bright_black   #${bright_black};
    @define-color bright_red     #${bright_red};
    @define-color bright_green   #${bright_green};
    @define-color bright_yellow  #${bright_yellow};
    @define-color bright_blue    #${bright_blue};
    @define-color bright_magenta #${bright_magenta};
    @define-color bright_cyan    #${bright_cyan};
    @define-color bright_white   #${bright_white};

    @define-color accent_bg_color @blue;
    @define-color accent_fg_color @background;
    @define-color accent_color @cyan;

    @define-color window_bg_color @background;
    @define-color window_fg_color @foreground;

    @define-color view_bg_color @black;
    @define-color view_fg_color @foreground;
    @define-color sidebar_bg_color @black;
    @define-color sidebar_fg_color @foreground;
    @define-color sidebar_backdrop_color @black;
    @define-color sidebar_shade_color @black;

    @define-color headerbar_bg_color @background;
    @define-color headerbar_fg_color @foreground;
    @define-color headerbar_border_color @bright_black;
    @define-color headerbar_backdrop_color @black;
    @define-color headerbar_shade_color @black;
    @define-color card_bg_color @background;
    @define-color card_fg_color @foreground;

    @define-color popover_bg_color @black;
    @define-color popover_fg_color @foreground;

    @define-color destructive_bg_color @red;
    @define-color destructive_fg_color @background;

    @define-color success_bg_color @green;
    @define-color success_fg_color @background;

    @define-color warning_bg_color @yellow;
    @define-color warning_fg_color @background;

    @define-color error_bg_color @red;
    @define-color error_fg_color @background;

    @define-color dialog_bg_color @background;
    @define-color dialog_fg_color @foreground;

    @define-color borders alpha(@foreground, 0.1);

    @define-color theme_fg_color @foreground;
    @define-color theme_text_color @foreground;
    @define-color theme_bg_color @background;
    @define-color theme_base_color @black;
    @define-color theme_selected_bg_color @blue;
    @define-color theme_selected_fg_color @background;
    @define-color insensitive_bg_color @background;
    @define-color insensitive_fg_color @bright_black;
    @define-color insensitive_base_color @black;
    @define-color theme_unfocused_fg_color @foreground;
    @define-color theme_unfocused_text_color @foreground;
    @define-color theme_unfocused_bg_color @background;
    @define-color theme_unfocused_base_color @black;
    @define-color theme_unfocused_selected_bg_color @blue;
    @define-color theme_unfocused_selected_fg_color @background;
    @define-color unfocused_insensitive_color @bright_black;
    @define-color unfocused_borders alpha(@foreground, 0.1);
    @define-color warning_color @yellow;
    @define-color error_color @red;
    @define-color success_color @green;
    @define-color destructive_color @red;

    @define-color content_view_bg @black;
    @define-color text_view_bg @black;

    messagedialog {
        background-color: @dialog_bg_color;
    }

    messagedialog label {
        color: @dialog_fg_color;
        font-size: 14pt;
        font-weight: bold;
    }

    messagedialog .secondary-text {
        font-size: 10pt;
        font-style: italic;
    }

    messagedialog button {
        background-color: @black;
        color: @foreground;
        border: 1px solid @bright_black;
        padding: 10px;
    }

    messagedialog button:hover {
        background-color: @blue;
    }

    banner revealer widget {
        background: @bright_black;
        padding: 5px;
        color: @foreground;
    }

    alertdialog.background {
        background-color: @dialog_bg_color;
        color: @dialog_fg_color;
    }

    alertdialog .titlebar {
        background-color: @headerbar_bg_color;
        color: @headerbar_fg_color;
    }

    alertdialog box {
        background-color: @dialog_bg_color;
    }

    alertdialog label {
        color: @dialog_fg_color;
    }

    filechooser .dialog-action-box {
        border-top: 1px solid @bright_black;
    }

    filechooser .dialog-action-box:backdrop {
        border-top-color: @black;
    }

    filechooser #pathbarbox {
        border-bottom: 1px solid @bright_black;
    }

    filechooserbutton:drop(active) {
        box-shadow: none;
        border-color: transparent;
    }

    toast {
        background-color: @black;
        color: @foreground;
    }

    toast button.circular.flat.image-button:hover {
        color: @background;
        background-color: @red;
    }

    window {
        font-family: '@SYSTEM_FONT@', monospace;
        font-size: 85%;
    }

    /* ── Nautilus / libadwaita overrides (omarchy-nautilus-theme) ─────────── */
    window undershoot.top {
        background-image: none;
        background-color: transparent;
        box-shadow: none;
    }

    window separator {
        background-color: @headerbar_border_color;
        min-width: 1px;
    }

    window,
    window base,
    notebook,
    view {
        background-color: @view_bg_color;
        color: @view_fg_color;
    }

    window headerbar,
    window .titlebar {
        background-color: @headerbar_bg_color;
        color: @headerbar_fg_color;
        border: none;
        box-shadow: none;
    }

    .nautilus-path-bar button {
        background-color: transparent;
        color: @window_fg_color;
        font-weight: normal;
        border-radius: 0;
    }
    .nautilus-path-bar button:hover {
        background-color: @card_bg_color;
        color: @accent_color;
        border-radius: 0;
    }

    window placessidebar {
        background-color: @sidebar_bg_color;
        color: @sidebar_fg_color;
    }
    window placessidebar row {
        border-radius: 0;
    }
    window placessidebar row:selected {
        background-color: alpha(@accent_bg_color, 0.15);
        color: @accent_color;
        font-weight: normal;
        border-radius: 0;
    }
    window placessidebar row:hover:not(:selected) {
        background-color: alpha(@headerbar_border_color, 0.2);
        border-radius: 0;
    }

    window flowboxchild,
    window .card,
    window gridview child,
    window columnview row,
    window listview row,
    window .view item {
        border-radius: 0;
    }

    window flowboxchild:hover,
    window gridview child:hover,
    window columnview row:hover,
    window listview row:hover,
    window .view item:hover {
        background-color: alpha(@headerbar_border_color, 0.2);
        border-radius: 0;
    }

    window flowboxchild:selected,
    window gridview child:selected,
    window treeview:selected,
    window columnview row:selected,
    window listview row:selected,
    window .view item:selected {
        background-color: alpha(@accent_bg_color, 0.15);
        color: @window_fg_color;
        border-radius: 0;
        outline: none;
        box-shadow: none;
    }

    rubberband, .rubberband {
        background-color: alpha(@accent_bg_color, 0.20);
        border: 1px solid @accent_bg_color;
        border-radius: 0;
    }

    window button:not(.flat):not(.suggested-action):not(.destructive-action) {
        background-color: @card_bg_color;
        color: @window_fg_color;
        border: 1px solid @headerbar_border_color;
        border-radius: 0;
    }
    window button:hover:not(.flat) {
        background-color: shade(@card_bg_color, 1.5);
        color: @window_fg_color;
        border-radius: 0;
    }
    window button:checked,
    window button:active {
        background-color: @accent_bg_color;
        color: @accent_fg_color;
        border-radius: 0;
    }

    window entry {
        background-color: @sidebar_bg_color;
        color: @window_fg_color;
        border: 1px solid @headerbar_border_color;
        border-radius: 0;
    }
    window entry:focus {
        border-color: @accent_color;
        box-shadow: 0 0 0 2px alpha(@accent_color, 0.3);
        border-radius: 0;
    }

    scrollbar slider {
        background-color: @headerbar_border_color;
        border-radius: 0;
    }
    scrollbar slider:hover,
    scrollbar slider:active {
        background-color: @accent_color;
        border-radius: 0;
    }

    box {
        border-radius: 0px;
    }

    /* .svg-icon {
        filter: invert(79%) sepia(18%) saturate(611%) hue-rotate(192deg)
            brightness(103%) contrast(94%);
    } */
EOF
}

if [ ! -d "$gtk3_dir" ]; then
    mkdir -p "$gtk3_dir"
fi
if [ ! -d "$gtk4_dir" ]; then
    mkdir -p "$gtk4_dir"
fi

# Always render a fresh template, then stamp in the live system font before
# deploying. This keeps @SYSTEM_FONT@ a placeholder in $output_file so the
# font-set hook can re-stamp just the font into gtk4 without touching color.
create_dynamic_theme

render_css() {  # render_css <font> -> writes stamped CSS to stdout
    sed "s/@SYSTEM_FONT@/$1/g" "$output_file"
}

system="$(system_font)"
tmp_css="$(mktemp)"

if [ -f "$gtk3_file" ] && [ ! -f "$gtk3_dir/gtk.css.backup" ]; then
    cp "$gtk3_file" "$gtk3_dir/gtk.css.backup"
fi
render_css "$system" > "$tmp_css"
install -m 644 "$tmp_css" "$gtk3_file"

if [ -f "$gtk4_file" ] && [ ! -f "$gtk4_dir/gtk.css.backup" ]; then
    cp "$gtk4_file" "$gtk4_dir/gtk.css.backup"
fi
render_css "$system" > "$tmp_css"
install -m 644 "$tmp_css" "$gtk4_file"
rm -f "$tmp_css"

if command -v gsettings >/dev/null 2>&1; then
    if [ -f "$light_file" ]; then
        gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-tmp
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3
    else
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-tmp-dark
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    fi
fi

if command -v pkill >/dev/null 2>&1; then
    pkill -f xdg-desktop-portal-gtk
fi

if command -v nautilus >/dev/null 2>&1; then
    # libadwaita reads ~/.config/gtk-4.0/gtk.css only at process startup, and
    # Nautilus runs as a D-Bus-activatable --gapplication-service daemon that
    # survives closed windows. `nautilus -q` kills the daemon; it respawns on
    # demand and re-reads the fresh stylesheet.
    nautilus -q 2>/dev/null || true
fi
require_restart "nautilus"
success "GTK theme updated!"
exit 0
