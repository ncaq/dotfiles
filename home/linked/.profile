PATH="$HOME/.local/bin:$PATH"
export PATH

if [ -r /proc/sys/kernel/osrelease ]; then
  read -r _osrelease < /proc/sys/kernel/osrelease
  case $_osrelease in
    *Microsoft*|*WSL*) ;;  # WSL1/WSL2 をカバー
    *) return ;;
  esac
else
  return
fi

if command -v xrdb >/dev/null 2>&1 && [ -f "$HOME/.Xresources" ]; then
  xrdb -merge "$HOME/.Xresources"
fi
