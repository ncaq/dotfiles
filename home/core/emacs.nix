{
  pkgs,
  lib,
  config,
  isWSL,
  inputs,
  ...
}:
let
  # `programs.emacs.enable`を使うとhome-managerが`emacsWithPackages`で二重ラップし、
  # `.emacs.d/flake.nix`の`extraEmacsPackages`でリンクしたバイナリが消えるため、
  # `.emacs.d`の定義を指定します。
  dotEmacsPackages = inputs.dot-emacs.packages.${pkgs.stdenv.hostPlatform.system};
  # WSLgはWaylandで動作するためWSL環境ではpgtkを指定します。
  # 別にXWaylandを経由してデフォルトパッケージでもそのまま動きますが、
  # せっかくなのでpgtkを使ってWaylandネイティブで動作させます。
  # Linuxネイティブの環境ではxmonadでX11をまだ使っているため、
  # デフォルトのEmacsを指定します。
  emacsPackage = if isWSL then dotEmacsPackages.pgtk else dotEmacsPackages.default;
in
{
  services.emacs = {
    enable = true;
    package = emacsPackage;
    client = {
      enable = true;
      arguments = [
        "--reuse-frame"
        "--alternate-editor=emacs"
      ];
    };
    defaultEditor = true;
  };

  home = {
    # Emacsの設定はEmacs Lispで行うのがDSLとして最適化されていて楽なので、
    # 基本的にNix言語ではなく`.emacs.d`に直接Emacs Lispを書いて管理します。
    # またEmacsの設定は即座に反映したいため、
    # git cloneしたものを直接参照します。
    # `inputs.dot-emacs`も利用していますが、
    # それは外部依存ライブラリを解決するためのものです。
    # Emacsの設定自体はローカルのファイルシステムで管理します。
    activation.cloneEmacsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.home.homeDirectory}/.emacs.d" ]; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
          https://github.com/ncaq/.emacs.d.git \
          "${config.home.homeDirectory}/.emacs.d"
      fi
    '';

    packages = [ emacsPackage ];
  };
}
