{ pkgs, ... }:
{
  # stableのdmd 2.110.0はビルドに失敗するので、ldcだけをインストールします。
  # 直っている2.112.1はunstableにだけあり、stableが2.112.1以上になればdmdを戻せます。
  # <https://github.com/NixOS/nixpkgs/pull/479273>
  home.packages = with pkgs; [
    ldc
  ];
}
