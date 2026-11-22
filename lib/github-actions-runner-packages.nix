/**
  全てのランナのPATHへ足すパッケージリスト。

  GitHubホステッドランナに入っているものに合わせて揃えることはしません。
  大量の依存が発生して本当にリポジトリが利用しているものが不透明になるからです。

  特定のジョブが使うものはワークフローの側でNixを使って用意します。

  何かがインストールされる前の全ての段階から入っていて欲しい物はあらかじめインストールします。

  nixpkgsの`services.github-runners`は何も足さなくても、
  以下をPATHに入れます。

  - bash
  - coreutils
  - git
  - gnutar
  - gzip
  - nix

  NixOSのsystemdのサービスが既定で持つPATHからも、
  以下が入ります。

  - coreutils
  - findutils
  - gnugrep
  - gnused
  - systemd

  これらは上流に任せて、
  このリストには書きません。

  バージョンはあまり気にしません。
  バージョンを気にするような用途の場合はワークフローの方で、
  NixなりActionsなりを使って用意することを想定しています。
*/
{ pkgs, ... }:
with pkgs;
let
  # 暗黙のうちに要求されることが多いランタイム。
  basicRuntime = [
    go
    nodejs
    perl
    python3
    sqlite
  ];

  cliTools = [
    # Version Control
    git-lfs

    # GitHub CLI
    gh

    # Data Processing
    jq
    yq-go

    # Compression
    _7zz # 7zip
    bzip2
    unzip
    xz
    zstd

    # Network
    curl
    iproute2
    iputils # ping
    rsync
    wget

    # Security
    gnupg
  ];
in
{
  all = builtins.concatLists [
    basicRuntime
    cliTools
  ];

  inherit
    basicRuntime
    cliTools
    ;
}
