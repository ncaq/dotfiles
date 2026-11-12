# Nix言語の編集・開発を補助するパッケージ。
{ pkgs, inputs, ... }:
let
  # メモリに合わせて評価のワーカー数を抑える`nix-fast-build`のラッパー。
  nix-fast-build-wrapper = import ../../lib/nix-fast-build-wrapper.nix { inherit pkgs; };
  # `secrets/cachix.yaml`から認証トークンを復号して`cachix push ncaq`するラッパー。
  cachix-push-ncaq = pkgs.callPackage ../../pkgs/cachix-push-ncaq { };
  # `secrets/niks3-{public,private}.yaml`から認証トークンを復号して、
  # 自分のniks3サーバに`niks3 push`するラッパー。
  # シークレットファイルはsops暗号化済みなのでNix storeに取り込んでビルド時に解決します。
  niks3-push-ncaq = pkgs.callPackage ../../pkgs/niks3-push-ncaq {
    niks3 = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3;
    publicSecretsFile = ../../secrets/niks3-public.yaml;
    privateSecretsFile = ../../secrets/niks3-private.yaml;
  };
in
{
  home.packages = with pkgs; [
    cachix
    cachix-push-ncaq
    niks3-push-ncaq
    nix-diff
    nix-fast-build-wrapper
    nix-init
    nix-update
    nixfmt
    nvd
    update-nix-fetchgit
  ];
}
