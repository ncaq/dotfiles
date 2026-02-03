{ pkgs, lib, ... }:
{
  # 現状nixのdmdコンパイラがARMをサポートしていないため、
  # 対応している場合のみインストールします。
  home.packages =
    with pkgs;
    lib.optionals stdenv.hostPlatform.isx86_64 [
      dmd
    ];
}
