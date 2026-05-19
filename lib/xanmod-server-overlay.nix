/**
  `linux_xanmod`をサーバ向けにチューニングし直した、
  `linux_xanmod_server`カーネルを`pkgs.linuxKernel`配下に追加するoverlay。

  パッケージ定義本体は`pkgs/linux-xanmod-server.nix`に置き、
  ここではoverlay経由で`linuxKernel.kernels`と`linuxKernel.packages`に登録するだけ。
  これにより`boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_server`、
  という標準的なNixOSの書き方でサーバ向けカーネルを参照できる。

  CPU最適化は別の`cpu-optimized-kernel-overlay.nix`が担当する。
*/
_final: prev:
let
  # `callPackage`は使わない。
  # `callPackage`は結果を`makeOverridable`で再ラップするため、
  # `.override`が`{ lib, linuxKernel }`という外側の引数だけを対象にしてしまい、
  # 内部の`linux_xanmod.override`チェーンに届かなくなる。
  # `cpu-optimized-kernel-overlay.nix`が`linux_xanmod_server`に対しても、
  # `kernelPatches`を追加する形で`.override`を呼ぶ必要があるため、
  # 直接`import`して内部の`override`をそのまま露出させる。
  serverKernel = import ../pkgs/linux-xanmod-server.nix {
    inherit (prev) lib linuxKernel;
  };
in
{
  linuxKernel = prev.linuxKernel // {
    kernels = prev.linuxKernel.kernels // {
      linux_xanmod_server = serverKernel;
    };
    packages = prev.linuxKernel.packages // {
      linux_xanmod_server = prev.linuxKernel.packagesFor serverKernel;
    };
  };
}
