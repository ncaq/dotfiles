# shellcheck disable=SC1090
export EDITOR='emacsclient -a emacs'
export GOPATH=~/.go
export LESS='--ignore-case --long-prompt --RAW-CONTROL-CHARS'
export LESSHISTFILE='-'
export VISUAL=$EDITOR

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  PATH=/opt/homebrew/opt/coreutils/libexec/gnubin/:$PATH
fi

if [[ -d $GOPATH ]]; then
  PATH=$GOPATH/bin:$PATH
fi

if [[ -f ~/.ghcup/env ]]; then
  source ~/.ghcup/env
fi

if [[ -f ~/.opam/opam-init/init.sh ]]; then
  source ~/.opam/opam-init/init.sh > /dev/null 2> /dev/null
fi

if [[ -d ~/.pyenv/ ]]; then
  PATH=$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH
fi

if [[ -x ~/.rbenv/bin/rbenv ]]; then
  PATH=$HOME/.rbenv/bin:$PATH
  eval "$(rbenv init - zsh)"
fi

if hash ruby 2>/dev/null; then
  PATH=$(ruby -e 'print Gem.user_dir')/bin:$PATH
fi

if [[ -f ~/.cargo/env ]]; then
  source ~/.cargo/env
fi

if [[ -d ~/.local/share/coursier/bin ]]; then
  PATH=$HOME/.local/share/coursier/bin:$PATH
fi

if hash yarn 2>/dev/null; then
  # For example, in the case of Windows (like MSYS2), it may be in AppData, so it is necessary to inquire.
  yarn_global_bin=$(yarn --offline global bin)
else
  # when yarn is not found, use linux standard yarn path.
  yarn_global_bin=$HOME/.yarn/bin
fi

if hash cygpath 2>/dev/null; then
  PATH=$(cygpath "$yarn_global_bin"):$PATH
else
  PATH=$yarn_global_bin:$PATH
fi

PATH=$HOME/.local/bin:$PATH
export PATH

# If the execution environment is not WSL, skip subsequent executions.
if [ ! -e "/proc/sys/kernel/osrelease" ] || ! grep -q "WSL" "/proc/sys/kernel/osrelease"; then
  return
fi

if hash xrdb 2>/dev/null && [[ -f ~/.Xresources ]]; then
  xrdb -merge ~/.Xresources
fi
