# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
let
  # nix-fast-buildのラッパー。
  # 設定ファイル機能がないので引数を上書きするラッパーを作ることでカスタマイズしています。
  # SQLiteキャッシュの競合のエラー表示を回避するために評価キャッシュを無効化しています。
  # resultリンクが大量に作成されるのが嫌なので作成を無効化しています。
  # 更に高速にするためにキャッシュがビルド済みのものはスキップします。
  nix-fast-build-wrapper = pkgs.writeShellApplication {
    name = "nix-fast-build";
    text = ''
      exec ${pkgs.lib.getExe pkgs.nix-fast-build} \
        --option eval-cache false \
        --no-link \
        --skip-cached \
        "$@"
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
