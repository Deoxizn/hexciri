#!/usr/bin/env bash
# hexciri:summary=Deploy the "Hexciri" ClearVision-based theme to Vencord/Vesktop
# shellcheck disable=SC1091,SC2154
# shellcheck source=../lib/theme-env.sh
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

output_file="$THPM_CURRENT_THEME_DIR/vencord-hexciri.theme.css"
theme_name_file="$THPM_THEME_NAME_FILE"
generated_file="$THPM_STATE_DIR/discord/vencord-hexciri.theme.css"
possible_paths=(
    "$HOME/.config/Vencord/themes"
    "$HOME/.config/vesktop/themes"
    "$HOME/.config/Equicord/themes"
    "$HOME/.config/equibop/themes"
    "$HOME/.var/app/com.discordapp.Discord/config/Vencord/themes"
    "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/themes"
    "$HOME/.var/app/io.github.equicord.equibop/config/equibop/themes"
)

theme_source_file() {
    local theme_name
    local source_dir

    [[ -f "$theme_name_file" ]] || return 1
    IFS= read -r theme_name < "$theme_name_file"
    [[ -n "$theme_name" ]] || return 1

    for source_dir in \
        "$HOME/.config/hexciri/themes/$theme_name" \
        "${HEXCIRI_PATH:-$HOME/.local/share/hexciri}/themes/$theme_name"; do
        if [[ -f "$source_dir/vencord.theme.css" ]]; then
            printf '%s\n' "$source_dir/vencord.theme.css"
            return 0
        fi
    done

    return 1
}

create_dynamic_theme() {
    local bg_base bg_raised bg_popout bg_input
    local rgb_bg_raised rgb_bg_popout rgb_bg_input

    # Vesktop is transparent again, but Hyprland blur is off. Keep the app
    # surface see-through and use slightly more opaque overlays so text stays
    # readable while the desktop shows through crisply.
    bg_base="$primary_background"
    bg_raised="$(change_shade "$bg_base" 12)"
    bg_popout="$(change_shade "$bg_base" 20)"
    bg_input="$(change_shade "$bg_base" 6)"
    rgb_bg_raised="$(hex2rgb "$bg_raised")"
    rgb_bg_popout="$(hex2rgb "$bg_popout")"
    rgb_bg_input="$(hex2rgb "$bg_input")"

    color_luma() {
        local hex_input="${1#\#}"
        # Non-colors score 0 (dark/unknown) instead of crashing arithmetic.
        if [[ ! $hex_input =~ ^[0-9a-fA-F]{6}$ ]]; then echo 0; return 0; fi
        local r=$((16#${hex_input:0:2}))
        local g=$((16#${hex_input:2:2}))
        local b=$((16#${hex_input:4:2}))
        echo $(((299 * r + 587 * g + 114 * b) / 1000))
    }

    # The selected channel sits on the main-color pill. ClearVision's white text
    # is unreadable on pastel accents, so flip to dark text when the accent is
    # light and keep white on dark accents.
    if (( $(color_luma "$bright_blue") >= 150 )); then
        channel_selected="$normal_black"
    else
        channel_selected="$bright_white"
    fi

    cat > "$output_file" << EOF
/**
 * @name Hexciri
 * @description ClearVision-based theme matching the current Hexciri palette.
 * @version 0.1.0
 * @source https://github.com/ClearVision/ClearVision-v7
 * @website https://clearvision.github.io
 */
@import url("https://clearvision.github.io/ClearVision-v7/main.css");
@import url("https://clearvision.github.io/ClearVision-v7/betterdiscord.css");

:root {
  /* ACCENT COLORS */
  --main-color: #${bright_blue};
  --hover-color: #${normal_blue};
  --success-color: #${normal_green};
  --danger-color: #${normal_red};
  /* STATUS COLORS */
  --online-color: #${normal_green};
  --idle-color: #${normal_yellow};
  --dnd-color: #${normal_red};
  --streaming-color: #${normal_magenta};
  --offline-color: #${bright_black};
  /* APP BACKGROUND: translucent palette surface, no internal wallpaper */
  --background-shading-percent: 100%;
  --background-image: none;
  /* HOME ICON */
  --home-icon: url(https://clearvision.github.io/icons/discord.svg);
  --home-size: cover;
  /* CHANNEL COLORS */
  --channel-normal: #${primary_foreground};
  --channel-muted: #${bright_black};
  --channel-hover: #${bright_white};
  --channel-selected: #${channel_selected};
  --channel-selected-bg: var(--main-color);
  --channel-unread: var(--main-color);
  --channel-unread-hover: var(--hover-color);
  /* ACCESSIBILITY */
  --focus-color: var(--main-color);
}

/* ClearVision sets these in :is(.theme-dark, .theme-light .theme-dark) and the
   sibling theme blocks. Match those elements at the same specificity from a
   later rule so the palette wins whether the theme class is on <html> or
   <body>, instead of the fixed black/white defaults. The alphas are the
   see-through level: lower them for more desktop, raise them for more text
   contrast. Overlays stay more opaque than the base surface. */
:root:root,
.theme-dark.theme-dark,
.theme-light.theme-light,
.theme-darker.theme-darker,
.theme-midnight.theme-midnight {
  --background-shading: rgba(${rgb_primary_background}, 0.50);
  --card-shading: rgba(${rgb_bg_raised}, 0.50);
  --popout-shading: rgba(${rgb_bg_popout}, 0.72);
  --modal-shading: rgba(${rgb_bg_popout}, 0.68);
  --input-shading: rgba(${rgb_bg_input}, 0.45);
  --normal-text: #${primary_foreground};
  --muted-text: #${bright_black};
}

/* Keep the wallpaper layer transparent: the see-through comes from the live
   desktop, not a bundled image. */
.bg__960e4 {
  background: none;
}

/* ClearVision colors the invite/action icons with --hsl-main-color, so on a
   selected channel the light icon stays light on the main-color pill. Keep it
   readable by tying it to the (already contrast-flipped) selected text. */
:is([class*="modeSelected_"]) [class*="addButtonIcon_"],
:is([class*="modeSelected_"]) [class*="actionIcon_"] {
  color: var(--channel-selected) !important;
}

/* Remove ClearVision branding (guild list header + settings About) */
:is(.theme-dark, .theme-light):not(.platform-osx) .leading_c38106::before,
:is(.theme-dark, .theme-light):not(.platform-osx) .leading_c38106::after,
:is(.theme-dark, .theme-light):not(.platform-osx) [class*="guilds_"] [class*="leading_"]::before,
:is(.theme-dark, .theme-light):not(.platform-osx) [class*="guilds_"] [class*="leading_"]::after {
  content: none !important;
}
.info__2debe::after {
  content: none !important;
}
EOF
}

install_theme() {
    local source="${1:-$output_file}"
    local path file

    for path in "${possible_paths[@]}"; do
        if [[ -d "$path" ]]; then
            cp -f "$source" "$path/vencord.theme.css"

            for file in "$path"/*.css; do
                if [[ -f "$file" ]]; then
                    touch "$file"
                fi
            done
        fi
    done
}

source_file="$(theme_source_file || true)"

if [[ -n $source_file ]]; then
    cp -f "$source_file" "$generated_file"
    install_theme "$source_file"
else
    create_dynamic_theme
    install_theme "$output_file"
fi
success "Discord theme updated (Hexciri)!"
exit 0
