/**
  importDirModules: ディレクトリ内の.nixファイルを自動的にモジュールをimportするためのパスのリストとして返す関数。

  型: Path -> [Path]

  引数:
    dir - スキャン対象のディレクトリパス(例: ./.)

  動作:
    1. builtins.readDirで指定ディレクトリ内のエントリ一覧を取得する
       (結果は `{ "foo.nix" = "regular"; "bar" = "directory"; ... }` のようなattrset)
    2. 以下の3条件を全て満たすエントリだけに絞り込む:
       - ファイルタイプが"regular"(通常ファイルでありディレクトリではない)
       - ファイル名が".nix"で終わる
       - ファイル名が"default.nix"ではない(呼び出し元自身を再帰importしないため)
    3. 絞り込んだファイル名にディレクトリパスを結合してフルパスのリストにして返す

  戻り値:
    NixOSモジュールやhome-managerモジュールのimportsに直接渡せるパスのリスト。
    例: `[ ./networking.nix ./nix.nix ... ]`

  使用パターン:
    各ディレクトリのdefault.nixから以下のように呼び出す:
    ```
    { importDirModules, ... }:
    { imports = importDirModules ./.; }
    ```
    これにより同ディレクトリ内のdefault.nix以外の全.nixファイルが自動的にimportされる。
    新しい.nixファイルを追加するだけでモジュールが有効になり、
    default.nixのimportsリストを手動で更新する必要がない。

  制約:
    - サブディレクトリは走査しない(1階層のみ)。
      サブディレクトリのモジュールが必要な場合は手動でimportsに追加します。
      例: `imports = importDirModules ./. ++ [ ./github-runner ];`
*/
{ lib }:
dir:
let
  # ディレクトリ内の全エントリを `{ name = type; ... }` のattrsetとして取得する。
  dirEntries = builtins.readDir dir;
  # default.nixを除く通常の.nixファイルだけを抽出する。
  moduleFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) dirEntries;
in
# ファイル名をディレクトリパスと結合してフルパスのリストに変換する。
lib.mapAttrsToList (name: _: lib.path.append dir name) moduleFiles
