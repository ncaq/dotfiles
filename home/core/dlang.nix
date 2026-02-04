{ pkgs, lib, ... }:
{
  # 現状nixが提供するdmdコンパイラはARMをサポートしていないため、
  # x86_64でのみインストールします。
  home.packages =
    with pkgs;
    lib.optionals stdenv.hostPlatform.isx86_64 [
      dmd
    ];
}
