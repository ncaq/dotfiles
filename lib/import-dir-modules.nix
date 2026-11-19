/**
  importDirModules: ディレクトリ内のモジュールを自動的にimportするためのパスのリストとして返す関数。

  型: Path -> [Path]

  引数:
    dir - スキャン対象のディレクトリパス(例: ./.)

  動作:
    1. builtins.readDirで指定ディレクトリ内のエントリ一覧を取得する
      (結果は `{ "foo.nix" = "regular"; "bar" = "directory"; ... }` のようなattrset)
    2. 以下のどちらかを満たすエントリだけに絞り込む:
      - 通常ファイル("regular")で、
        名前が".nix"で終わり、
        "default.nix"ではなく(呼び出し元自身を再帰importしないため)、
        ".test.nix"で終わらない(モジュールの隣に置いた評価のテストで、`test/collect-nix-tests.nix`が集める)
      - ディレクトリで、直下にdefault.nixを持つ
        (default.nixを持たないディレクトリはモジュールではないので無視される)
    3. 絞り込んだ名前にディレクトリパスを結合してフルパスのリストにして返す

  戻り値:
    NixOSモジュールやhome-managerモジュールのimportsに直接渡せるパスのリスト。
    例: `[ ./networking.nix ./nix.nix ./github-runner ]`

  使用パターン:
    各ディレクトリのdefault.nixから以下のように呼び出す:
    ```
    { importDirModules, ... }:
    { imports = importDirModules ./.; }
    ```
    これにより同ディレクトリ内のdefault.nixとテスト以外の全.nixファイルと、
    default.nixを持つサブディレクトリが自動的にimportされる。
    新しい.nixファイルやモジュールディレクトリを追加するだけでモジュールが有効になり、
    default.nixのimportsリストを手動で更新する必要がない。
    `importDirModules`は`specialArgs`と`extraSpecialArgs`で全てのモジュールに渡している
    (`lib/mk-nixos-system.nix`と`lib/mk-linux-home-manager.nix`と`nix-on-droid/default.nix`)。

  制約:
    - サブディレクトリの走査は1階層のみ。
      サブディレクトリの中身はそのdefault.nixが自身で管理する。
*/
{ lib }:
dir:
let
  # ディレクトリ内の全エントリを `{ "foo.nix" = "regular"; "bar" = "directory"; ... }` のようなattrsetとして取得する。
  dirEntries = builtins.readDir dir;
  # default.nixとテストを除く通常の.nixファイルと、default.nixを持つサブディレクトリだけを抽出する。
  moduleEntries = lib.filterAttrs (
    name: type:
    (
      type == "regular"
      && lib.hasSuffix ".nix" name
      && name != "default.nix"
      && !(lib.hasSuffix ".test.nix" name)
    )
    || (type == "directory" && builtins.pathExists (lib.path.append dir "${name}/default.nix"))
  ) dirEntries;
in
# 名前をディレクトリパスと結合してフルパスのリストに変換する。
lib.mapAttrsToList (name: _: lib.path.append dir name) moduleEntries
