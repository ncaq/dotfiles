# `flake.nix`の`hostInfo`に書いた静的な情報が、実際の構成と食い違っていないかを確かめる。
#
# `hostInfo`は構成を評価せずに読むためのもので、構成から導かれるわけではない。
# 片方だけを書き換えると黙ってずれるので、評価を止めて気付けるようにする。
{
  lib,
  config,
  hostName,
  hostInfo,
  ...
}:
let
  # 層を読み込んだかどうかを示すoption。
  # 層の中のモジュールが`true`にして、`hostInfo`と突き合わせるためだけに使う。
  mkLayerOption =
    layer:
    lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "`${layer}`層を読み込んだかどうか。";
    };
in
{
  options.local = {
    client = mkLayerOption "client";
    server = mkLayerOption "server";
  };

  config.assertions = [
    {
      assertion = (hostInfo.${hostName}.client or false) == config.local.client;
      message = "`flake.nix`の`hostInfo.${hostName}.client`が、`client`層を読み込んだかどうかと食い違っています。";
    }
    {
      assertion = (hostInfo.${hostName}.wsl or false) == (config.wsl.enable or false);
      message = "`flake.nix`の`hostInfo.${hostName}.wsl`が、構成の`wsl.enable`と食い違っています。";
    }
    {
      assertion = (hostInfo.${hostName}.server or false) == config.local.server;
      message = "`flake.nix`の`hostInfo.${hostName}.server`が、`server`層を読み込んだかどうかと食い違っています。";
    }
  ];
}
