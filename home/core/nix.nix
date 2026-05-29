# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
let
  # `nix-fast-build`をカスタマイズします。
  # 設定ファイル機能がないので引数を上書きするラッパーを作ることでカスタマイズしています。
  # `--no-link`は、
  # チェックするだけで`result`リンクが作成されるのを回避するものです。
  # `--skip-cached`は、
  # ビルドキャッシュがあるものはスキップして高速化するものです。
  nix-fast-build-wrapper = pkgs.writeShellApplication {
    name = "nix-fast-build";
    text = ''
      exec ${pkgs.lib.getExe pkgs.nix-fast-build} \
        --no-link \
        --skip-cached \
        "$@"
    '';
  };
in
{
  home.packages = with pkgs; [
    cachix
    nil
    nix-diff
    nix-fast-build-wrapper
    nix-init
    nix-update
    nixfmt
    nvd
    update-nix-fetchgit
  ];
}
