# shellcheck disable=SC1090,SC1091

if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then
  source ~/.nix-profile/etc/profile.d/nix.sh
elif [ -e /etc/profile.d/nix.sh ]; then
  source /etc/profile.d/nix.sh
fi

# If the execution environment is not WSL, skip subsequent executions.
if [ ! -e "/proc/sys/kernel/osrelease" ] || ! grep -q "WSL" "/proc/sys/kernel/osrelease"; then
  return
fi

if hash xrdb 2>/dev/null && [[ -f ~/.Xresources ]]; then
  xrdb -merge ~/.Xresources
fi
