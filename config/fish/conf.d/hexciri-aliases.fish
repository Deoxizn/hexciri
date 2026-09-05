# hexciri fish: vanilla aliases + env (no third-party tools like eza/fzf/zoxide)

# File system
alias ls='ls -lhF --color=auto'
alias lsa='ls -a'
alias llt='ls -lhFt'        # time-sorted
alias ll='ls -lhF --color=auto'

# Directories
alias ..='cd ..'

# Git / misc
alias omup='hexciri-update-run'
alias ga='git add .'
alias gp='git push'
alias gpl='git pull'
alias clr='clear'
alias ff='hexciri-fastfetch'
alias c='opencode'
alias mkdir='mkdir -pv'
alias rp='readlink -e'
alias abspath='readlink -e'
alias rmm='rm -rvI'
alias cpp='cp -R'
alias cp='cp -i'
alias mv='mv -i'
alias connect=nmtui

# Network
alias myip='ip -brief addr'
alias myroute='ip route'

# System monitoring (vanilla tools only)
alias df='df -h'
alias du='du -ch'
alias free='free -m'
alias fs='df -h -x squashfs -x tmpfs -x devtmpfs'
alias disks='lsblk -o HOTPLUG,NAME,SIZE,MODEL,TYPE | awk "NR == 1 || /disk/"'
alias partitions='lsblk -o HOTPLUG,NAME,LABEL,MOUNTPOINT,SIZE,MODEL,PARTLABEL,TYPE,UUID | grep -v loop | cut -c1-$COLUMNS'
alias sizeof="du -hs"

# Networking downloads
alias wget='wget --content-disposition'

# Init
set -gx STARSHIP_CONFIG $HOME/.config/starship.toml
set -U fish_greeting
set -gx ZED_ALLOW_ROOT true
starship init fish | source