{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  # programs.emacs.enableを使うとhome-managerがemacsWithPackagesで二重ラップし、
  # .emacs.d/flake.nixのextraEmacsPackagesでリンクしたバイナリが消えるため、
  # .emacs.dのパッケージを指定します。
  emacsPackage = inputs.dot-emacs.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
