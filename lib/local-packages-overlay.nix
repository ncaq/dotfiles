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
*/
{ lib, inputs }:
final: _prev:
lib.packagesFromDirectoryRecursive {
  callPackage = lib.callPackageWith (
    final
    // {
      inherit (inputs) himari-src;
      inherit (inputs.niks3.packages.${final.stdenv.hostPlatform.system}) niks3;
    }
  );
  directory = ../pkgs;
}
