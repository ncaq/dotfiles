{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacsWithPackagesFromUsePackage {
      config = "${inputs.dot-emacs}/init.el"; # init.elが依存しているパッケージをインストールします。
    };
  };

  services.emacs = {
    enable = true;
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
    # Emacsが必要とするネイティブパッケージ。
    packages = with pkgs; [
      copilot-language-server
    ];

    # Emacsの設定はEmacs Lispで行うのがDSLとして最適化されていて楽なので、
    # Nix言語ではなく`.emacs.d`で基本的に管理します。
    # またEmacsの設定は即座に反映したいため、
    # currentとしてはinputs頼りではなくcloneしたものを直接参照します。
    # inputsにも入れていますが、
    # それは外部ライブラリを自動的に入れるためのもので、
    # あくまでショートカットです。
    activation.cloneEmacsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.home.homeDirectory}/.emacs.d" ]; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
          https://github.com/ncaq/.emacs.d.git \
          "${config.home.homeDirectory}/.emacs.d"
      fi
    '';
  };
}
