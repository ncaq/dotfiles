/**
  `pkgs/`に置いた自作のパッケージを、nixpkgsのトップレベルに生やすoverlay。

  `lib.packagesFromDirectoryRecursive`で`pkgs/`を走査するので、
  `pkgs/<名前>.nix`か`pkgs/<名前>/package.nix`を置くだけで`pkgs.<名前>`として使えるようになる。
  flakeの`packages`と`checks`もここから集めるので、
  パッケージを足す時に`flake.nix`やモジュールを書き換える必要は無い。

  パッケージ同士の依存は普通の引数として書けば、
  overlayの不動点を通して他の自作パッケージも受け取れる。
  flakeのinputから取るものは、
  `callPackage`が自動で渡す引数にここで足す。
  nixpkgsに無いものの他に、
  `home-manager`のようにnixpkgsにあってもinputと版を揃えたいものも含む。

  パッケージの他に`localPackagesInfo`を1つ生やす。
  パッケージではなく、flakeが`packages`と`checks`を集めるための情報である。
  - `names`: 走査したパッケージの名前
  - `collisions`: そのうちoverlayを当てる前のnixpkgsにもある名前。
    このoverlayは`prev`を見ずに上書きするので、
    重なるとnixpkgsの中でそれに依存するパッケージまで自作の版に差し替わる。
    共通のoverlaysの先頭に置くので`prev`は素のnixpkgsで、
    メモ化済みのインスタンスのまま調べられる。
*/
{
  lib,
  inputs,
  localLib,
}:
final: prev:
let
  # 自作のHaskellパッケージが共有するパッケージセット。
  # パッケージごとに`haskellPackages.extend`すると、
  # できるセットは互いに別の不動点なので、
  # himariとその依存のderivationをパッケージの数だけ評価し直すことになる。
  localHaskellPackages = final.haskellPackages.extend (
    hself: _hsuper: {
      # himariはstableのnixpkgsではbrokenなので、上流のソースから組む。
      himari = hself.callCabal2nix "himari" inputs.himari-src { };
    }
  );
  packages = lib.packagesFromDirectoryRecursive {
    callPackage = lib.callPackageWith (
      final
      // {
        inherit localHaskellPackages;
        # `lib/`の定義。パッケージも相対パスで`import`せずに引数で受け取る。
        inherit localLib;
        inherit (inputs.niks3.packages.${final.stdenv.hostPlatform.system}) niks3;
        # nixpkgsの`home-manager`はmasterのスナップショットなので、
        # 構成の評価に使うinputと同じ版のCLIを渡す。
        inherit (inputs.home-manager.packages.${final.stdenv.hostPlatform.system}) home-manager;
        # home-managerのモジュールを隣に持つパッケージが、テストでそのモジュールを評価するためのもの。
        inherit (inputs.home-manager.lib) homeManagerConfiguration;
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
