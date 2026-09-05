# hexciri fish: starship prompt (pairs with ~/.config/starship.toml)
set -gx STARSHIP_CONFIG $HOME/.config/starship.toml
set -g fish_greeting ""
starship init fish | source
