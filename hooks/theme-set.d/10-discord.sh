#!/usr/bin/env bash
# hexciri:summary=Deploy the "Hexciri" ClearVision-based theme to Vencord/Vesktop
# shellcheck disable=SC1091,SC2154
# shellcheck source=../lib/theme-env.sh
source "${HEXCIRI_THEME_ENV:-$HOME/.config/hexciri/hooks/lib/theme-env.sh}"

output_file="$THPM_CURRENT_THEME_DIR/vencord-hexciri.theme.css"
theme_name_file="$THPM_THEME_NAME_FILE"
generated_file="$THPM_STATE_DIR/discord/vencord-hexciri.theme.css"
background_link="$HOME/.local/state/hexciri/current/background"
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
    local bg_image="none"
    if [[ -L $background_link || -f $background_link ]]; then
        bg_image="url(\"file://$(readlink -f "$background_link" 2>/dev/null || printf '%s' "$background_link")\")"
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
  /* APP BACKGROUND: mirror the active hexciri wallpaper */
  --background-shading-percent: 80%;
  --background-image: ${bg_image};
  --background-position: center;
  --background-size: cover;
  --background-attachment: fixed;
  --background-filter: saturate(calc(var(--saturation-factor, 1) * 1));
  /* USER POPOUT BACKGROUND */
  --user-popout-image: var(--background-image);
  --user-popout-position: var(--background-position);
  --user-popout-size: var(--background-size);
  --user-popout-attachment: var(--background-attachment);
  --user-popout-filter: var(--background-filter);
  /* USER MODAL BACKGROUND */
  --user-modal-image: var(--background-image);
  --user-modal-position: var(--background-position);
  --user-modal-size: var(--background-size);
  --user-modal-attachment: var(--background-attachment);
  --user-modal-filter: var(--background-filter);
  /* HOME ICON */
  --home-icon: url(https://clearvision.github.io/icons/discord.svg);
  --home-size: cover;
  /* CHANNEL COLORS */
  --channel-normal: #${primary_foreground};
  --channel-muted: #${bright_black};
  --channel-hover: #${bright_white};
  --channel-selected: #${bright_white};
  --channel-selected-bg: var(--main-color);
  --channel-unread: var(--main-color);
  --channel-unread-hover: var(--hover-color);
  /* ACCESSIBILITY */
  --focus-color: var(--main-color);
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