/**
  NixOS Containersの中の`pkgs`を、ホストの`pkgs`と同じインスタンスにするモジュール。

  コンテナは既定ではホストの`pkgs`を引き継がず、
  コンテナごとにnixpkgsを読み込み直す。
  同じパッケージのderivationをコンテナの数だけ評価し直すことになり、
  `nix-eval-jobs`のワーカは評価中にGCをしないので、その分がそのままメモリの使用量に積み上がる。
  コンテナを8つ持つseminarでは、
  ホストの構成の評価が確保する量がこれで約17%減った。

  ホストの`pkgs`を渡すので、
  コンテナの中のパッケージにもホストのoverlayとunfreeの許可が効く。
*/
{ lib, pkgs, ... }:
{
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.config.nixpkgs.pkgs = pkgs;
      }
    );
  };
}
