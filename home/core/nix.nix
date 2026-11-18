# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cachix
    # `secrets/cachix.yaml`から認証トークンを復号して`cachix push ncaq`するラッパ。
    cachix-push-ncaq
    hydra-check # Hydraでのビルド状況を調べます。
    # `secrets/niks3-{public,private}.yaml`から認証トークンを復号して、
    # 自分のniks3サーバに`niks3 push`するラッパ。
    niks3-push-ncaq
    nix-diff
    # メモリに合わせて評価のワーカ数を抑える`nix-fast-build`のラッパ。
    nix-fast-build-wrapper
    nix-init
    nix-output-monitor # ビルドの進捗を見やすく表示します。
    nix-tree # 依存関係とクロージャのサイズを対話的に調べます。
    nix-update
    nixfmt
    nixpkgs-review # nixpkgsのPRの影響を受けるパッケージをまとめてビルドします。
    nvd
    update-nix-fetchgit
  ];
}
