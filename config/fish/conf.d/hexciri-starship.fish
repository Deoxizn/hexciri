# hexciri fish: starship prompt (theme-generated colors; falls back to user config)
if test -f "$HOME/.local/state/hexciri/current/theme/starship.toml"
  set -gx STARSHIP_CONFIG "$HOME/.local/state/hexciri/current/theme/starship.toml"
else
  set -gx STARSHIP_CONFIG "$HOME/.config/starship.toml"
end
set -g fish_greeting ""
starship init fish | source
