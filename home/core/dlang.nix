{ pkgs, lib, ... }:
{
  # 現状nixのdmdコンパイラがARMをサポートしていないため、
  # 対応している場合のみインストールします。
  home.packages =
    with pkgs;
    lib.optional dmd.meta.isSupported [
      dmd
    ];
}
