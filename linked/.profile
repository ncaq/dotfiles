# shellcheck disable=SC1090
export EDITOR='emacsclient -a emacs'
export LESS='--ignore-case --long-prompt --RAW-CONTROL-CHARS'
export LESSHISTFILE='-'
export VISUAL=$EDITOR

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  PATH=/opt/homebrew/opt/coreutils/libexec/gnubin/:$PATH
fi

if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then
  source ~/.nix-profile/etc/profile.d/nix.sh
elif [ -e /etc/profile.d/nix.sh ]; then
  source /etc/profile.d/nix.sh
fi

if [[ -f ~/.ghcup/env ]]; then
  source ~/.ghcup/env
fi

if [[ -f ~/.opam/opam-init/init.sh ]]; then
  source ~/.opam/opam-init/init.sh > /dev/null 2> /dev/null
fi

if [[ -f ~/.cargo/env ]]; then
  source ~/.cargo/env
fi

PATH=~/.local/bin:~/.pyenv/shims:~/.pyenv/bin:~/.local/share/coursier/bin:~/.yarn/bin:$PATH
export PATH

# If the execution environment is not WSL, skip subsequent executions.
if [ ! -e "/proc/sys/kernel/osrelease" ] || ! grep -q "WSL" "/proc/sys/kernel/osrelease"; then
  return
fi

if hash xrdb 2>/dev/null && [[ -f ~/.Xresources ]]; then
  xrdb -merge ~/.Xresources
fi
