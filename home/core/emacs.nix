{
  pkgs,
  lib,
  config,
  isWSL,
  osConfig ? null,
  inputs,
  ...
}:
let
  # NixOS環境では`osConfig.local.cpuTarget`からCPUモデルを取得します。
  cpuTarget = osConfig.local.cpuTarget or null;
  # CPUモデルが登録済みならば、
  # CPUモデル向けの最適化overlayを利用します。
  # 非NixOS環境や非登録ホストでは`osConfig`が無いので、
  # overlayは使いません。
  extraOverlays = lib.optional (cpuTarget != null) (
    import ../../lib/cpu-optimized-overlay.nix cpuTarget
  );
  # `programs.emacs.enable`を使うとhome-managerが`emacsWithPackages`で二重ラップし、
  # `.emacs.d/flake.nix`の`extraEmacsPackages`でリンクしたバイナリが消えるため、
  # `.emacs.d`由来の定義を`service.emacs`や`home.packages`で参照するようにします。
  emacsPackage = inputs.dot-emacs.lib.mkEmacs {
    inherit (pkgs.stdenv.hostPlatform) system;
    # WSLgはWaylandで動作するためWSL環境では`"pgtk"`を指定します。
    # 別にデフォルトパッケージを使ってXWaylandを経由しても動きますが、
    # 少し動作が良好なのでWaylandで動作させます。
    # それ以外のつまりLinuxネイティブの環境ではXMonadでX11を使っているため、
    # デフォルトのEmacsを指定します。
    basePackage = if isWSL then pkgs.emacs-pgtk else pkgs.emacs;
    # `cpu-optimized-overlay`を`mkEmacs`に渡してEmacs本体まで最適化を反映します。
    # `nixpkgs.overlays`の設定はdot-emacs flake内部のpkgsには伝播しないため、
    # ここで明示的にoverlayを連結する必要があります。
    inherit extraOverlays;
  };
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
    # `git clone`したものを直接参照します。
    # `inputs.dot-emacs`も利用していますが、
    # それは外部依存ライブラリを解決したり、
    # Nixの設定をスマートに解決するためのものです。
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
