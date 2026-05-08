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

### Android

私の持っているモバイル端末のOSは基本的にAndroid OSです。

## webブラウザ

webブラウザにはFirefoxを使っています。

Android環境でもFirefox for Androidを使っています。

## メールクライアント

メールクライアントにはThunderbirdを使っています。

Android環境でもThunderbird for Android(中身はK-9 Mailだけど)を使っています。

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

## ターミナルエミュレータ

ネイティブNixOS環境ではAlacrittyを使っています。

Windows上のWSL2環境ではWindows Terminalを使っています。
本当はこちらもAlacrittynに移行したいのですが、
Claude Code上の日本語変換のウィンドウ表示が崩れてしまうため、
Windows Terminalをまだ使い続けています。

## ウィンドウマネージャ

NixOS環境では[XMonad](https://xmonad.org/)を使っています。
設定は、
[ncaq/.xmonad](https://github.com/ncaq/.xmonad)
管理されています。
`~/.xmonad`に`git clone`されています。

## パスワードマネージャ

PCでは[KeePassXC](https://keepassxc.org/)を使っています。

Androidでは[KeePassDX](https://github.com/Kunzisoft/KeePassDX)を使っています。

KeePassのデータベースファイルはマスターデータです。

Firefoxのパスワードマネージャはキャッシュとして使っていて、
そのまま入力できる簡単なフォームならFirefoxに入力を任せています。

## オフィススイート

私はあまり積極的にオフィススイートを使うことはありません。
内部構造が見えにくいツールは苦手なので。

印刷やプレゼンテーションが必要な時は、
Markdownで書いて、
[ncaq/pppset: pandoc-page-preset](https://github.com/ncaq/pppset)
のような自分のPandocの設定を使ってTeXファイルに変換して、
[LuaTeX-ja](https://texwiki.texjp.org/?LuaTeX-ja)を使ってPDFに変換するほうが好みです。

しかし既に何かしらのツールが吐き出したスプレッドシート向けデータを手っ取り早く軽く編集したいときとか、
本当にちょっとした印刷データを作りたい時などはわざわざTeXを持ち出すのは大がかりすぎます。

そういう時はローカルではLibreOfficeを使っています。

既にそこにあるドキュメントではGoogle WorkspaceのGoogle DocsやGoogle Sheetsを使うことがあります。

Microsoft Officeは自分は契約していないので基本的には使いません。

## 画像編集

GIMPかInkscapeを使っています。

## コマンドラインファイルアーカイバ

[patool - Wikipedia](https://ja.wikipedia.org/wiki/Patool)を使っています。
`patool extract`で大抵の圧縮ファイルを解凍できます。

`unzip`コマンドが見つからなくても諦めずに`patool`を試してみてください。
