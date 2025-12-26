# よく使うソフトウェア

## オペレーティングシステム

### NixOS

開発を行うPCのOSには基本的にNixOSを使っています。
直接NixOSをブートしているか、
WSL2の上でNixOSを使っています。

自分のNixOSの環境は、
[ncaq/dotfiles: dotfiles, NixOS and home-manager.](https://github.com/ncaq/dotfiles)
で管理されています。
`~/dotfiles`に`git clone`されています。

### Windows

ゲームをする時などはWindows 11をネイティブで使うことがあります。

## webブラウザ

webブラウザにはFirefoxを使っています。

## テキストエディタ

テキストエディタにはEmacsを使っています。
設定は、
[ncaq/.emacs.d: My Emacs config](https://github.com/ncaq/.emacs.d)
で管理されています。
`~/.emacs.d`に`git clone`されています。

## シェル

シェルにはZshを使っています。
設定は、
[ncaq/.zsh.d](https://github.com/ncaq/.zsh.d)
で管理されています。
`~/.zsh.d`に`git clone`されています。

## コマンドラインファイルアーカイバ

[patool - Wikipedia](https://ja.wikipedia.org/wiki/Patool)を使っています。
`patool extract`で大抵の圧縮ファイルを解凍できます。

`unzip`コマンドが見つからなくても諦めずに`patool`を試してみてください。
