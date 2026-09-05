# hexciri fish: vanilla helper functions (no third-party tools)

function compress
  set dir $argv[1]
  set dir (string replace -r '/$' '' -- $dir)
  tar -czf "$dir.tar.gz" "$dir"
end

function decompress
  tar -xzf $argv
end

function mkcd --description "Create and cd into a directory"
  command mkdir -p $argv
  and cd $argv
end

function copy --description "Copy pipe or argument (wl-copy)"
  if test -z "$argv"
    wl-copy
  else
    printf "%s" "$argv" | wl-copy
  end
end

function copypath --description "Copy full file path"
  readlink -e $argv | wl-copy
  echo "copied to clipboard"
end

function color --description "Print a color block"
  echo (set_color (string trim -c '#' "$argv"))"██"
end

function run --description "Make file executable, then run it"
  chmod +x "$argv"
  eval "./$argv"
end

function b --description "Exec a command in bash"
  bash -c "$argv"
end

function m --description "Math using Python"
  python -c "print($argv)"
end

function gc
  git commit -m "$argv"
end

function co --description "Remove orphaned packages"
  set orphans (pacman -Qdtq)
  if test -n "$orphans"
    echo "$orphans" | sudo pacman -Rns -
  else
    echo "No orphans to remove."
  end
end

function qr --description "Print a QR code as unicode blocks"
  if test -z "$argv"
    qrencode -t ANSIUTF8
  else
    printf "%s" "$argv" | qrencode -t ANSIUTF8
  end
end