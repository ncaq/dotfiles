# `flake.nix`の`hostInfo`に書いた静的な情報が、実際の構成と食い違っていないかを確かめる。
#
# `hostInfo`は構成を評価せずに読むためのもので、構成から導かれるわけではない。
# 片方だけを書き換えると黙ってずれるので、評価を止めて気付けるようにする。
{
  config,
  hostName,
  hostInfo,
  ...
}:
{
  assertions = [
    {
      assertion = (hostInfo.${hostName}.wsl or false) == (config.wsl.enable or false);
      message = "`flake.nix`の`hostInfo.${hostName}.wsl`が、構成の`wsl.enable`と食い違っています。";
    }
  ];
}
