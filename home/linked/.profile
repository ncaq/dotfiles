PATH="$HOME/.local/bin:$PATH"
export PATH

if [ ! -f '/proc/sys/kernel/osrelease' ]; then
  return
fi

case "$(</proc/sys/kernel/osrelease 2>/dev/null)" in
  *Microsoft*|*WSL*) ;;    # WSL1/WSL2 をカバー
  *) return ;;             # それ以外は .profile を抜ける
esac

if command -v xrdb >/dev/null 2>&1 && [ -f "$HOME/.Xresources" ]; then
  xrdb -merge "$HOME/.Xresources"
fi
