# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
let
  # nix-fast-buildのラッパー: SQLiteキャッシュの競合のエラーを回避するために評価キャッシュを無効化しています。
  nix-fast-build-wrapper = pkgs.writeShellApplication {
    name = "nix-fast-build";
    runtimeInputs = [ pkgs.nix-fast-build ];
    text = ''
      exec nix-fast-build --option eval-cache false "$@"
    '';
  };
in
{
  home.packages = with pkgs; [
    nil
    nix-diff
    nix-fast-build-wrapper
    nix-init
    nix-update
    nixfmt
    update-nix-fetchgit
  ];
}
