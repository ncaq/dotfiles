/**
  `pkgs/`に置いた自作のパッケージを、nixpkgsのトップレベルに生やすoverlay。

  `lib.packagesFromDirectoryRecursive`で`pkgs/`を走査するので、
  `pkgs/<名前>.nix`か`pkgs/<名前>/package.nix`を置くだけで`pkgs.<名前>`として使えるようになる。
  flakeの`packages`と`checks`もここから集めるので、
  パッケージを足す時に`flake.nix`やモジュールを書き換える必要は無い。

  パッケージ同士の依存は普通の引数として書けば、
  overlayの不動点を通して他の自作パッケージも受け取れる。
  nixpkgsに無いflakeのinputから取るものは、
  `callPackage`が自動で渡す引数にここで足す。

  パッケージの他に`localPackagesInfo`を1つ生やす。
  パッケージではなく、flakeが`packages`と`checks`を集めるための情報である。
  - `names`: 走査したパッケージの名前
  - `collisions`: そのうちoverlayを当てる前のnixpkgsにもある名前。
    このoverlayは`prev`を見ずに上書きするので、
    重なるとnixpkgsの中でそれに依存するパッケージまで自作の版に差し替わる。
    共通のoverlaysの先頭に置くので`prev`は素のnixpkgsで、
    メモ化済みのインスタンスのまま調べられる。
*/
{ lib, inputs }:
final: prev:
let
  packages = lib.packagesFromDirectoryRecursive {
    callPackage = lib.callPackageWith (
      final
      // {
        inherit (inputs) himari-src;
        inherit (inputs.niks3.packages.${final.stdenv.hostPlatform.system}) niks3;
      }
    );
    directory = ../pkgs;
  };
  names = builtins.attrNames packages;
in
packages
// {
  localPackagesInfo = {
    inherit names;
    collisions = lib.filter (name: prev ? ${name}) names;
  };
}
