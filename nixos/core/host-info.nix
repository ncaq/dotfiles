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
{
  options.local.server = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      `server`層を読み込んだかどうか。
      `server`層が`true`にする。
      `hostInfo`の`server`と突き合わせるためだけに使う。
    '';
  };

  config.assertions = [
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
