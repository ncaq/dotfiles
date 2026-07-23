{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # flake input経由でkonokaプラグインを取得します。
  # marketplace経由ではなくビルド済みプラグインを直接読み込むことで、
  # ヘルパースクリプトまでnixで管理できます。
  konokaPlugins = inputs.konoka.packages.${pkgs.stdenv.hostPlatform.system};

  # konokaリポジトリの`plugins/`直下のディレクトリ名をそのままプラグイン名として使います。
  # konoka側のflake.nixがpluginsディレクトリの走査でパッケージ集合を導出しているのと同じ方針で、
  # プラグインの追加削除にこちら側の一覧を手動追随させる必要をなくします。
  # Claude Codeはこのリスト全てを`programs.claude-code.plugins`にリンクします。
  allPluginNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${inputs.konoka.outPath}/plugins")
  );

  # skillsを持つkonokaプラグインの名前リストです。
  # `skills/`ディレクトリの有無で判定するため、
  # hookのみで構成されるプラグイン(例: `rm-to-trash`)は自動的に除外されます。
  skillPluginNames = lib.filter (
    pluginName: builtins.pathExists "${inputs.konoka.outPath}/plugins/${pluginName}/skills"
  ) allPluginNames;

  # 各konokaプラグイン内のskillsサブディレクトリをフラットに展開します。
  # ソース側のskillsディレクトリで一覧を取り、
  # 実際のパスにはbin/やhooks/のビルド生成物まで揃ったパッケージ側を参照します。
  skillEntries = builtins.concatMap (
    pluginName:
    let
      pluginPkg = konokaPlugins.${pluginName};
      skillsSrcDir = "${inputs.konoka.outPath}/plugins/${pluginName}/skills";
      skillNames = builtins.attrNames (builtins.readDir skillsSrcDir);
    in
    map (skillName: {
      inherit pluginName skillName;
      path = "${pluginPkg}/skills/${skillName}";
    }) skillNames
  ) skillPluginNames;

  # スキル名からそれを提供するプラグイン名のリストへの辞書。
  # 複数プラグインが同名のスキルを持つとフラット展開時に片方が消えるため、
  # 検出できるようにここで所有者一覧を組み立てます。
  skillOwners = lib.foldl' (
    acc: entry:
    acc
    // {
      ${entry.skillName} = (acc.${entry.skillName} or [ ]) ++ [ entry.pluginName ];
    }
  ) { } skillEntries;

  skillNameConflicts = lib.filterAttrs (_: owners: lib.length owners > 1) skillOwners;

  skills =
    assert lib.assertMsg (
      skillNameConflicts == { }
    ) "konokaプラグイン間でスキル名が衝突しています: ${builtins.toJSON skillNameConflicts}";
    lib.listToAttrs (map (entry: lib.nameValuePair entry.skillName entry.path) skillEntries);
in
{
  # konoka関連の情報を他のhome-managerモジュールに公開します。
  # `konoka`引数として`programs.claude-code`や`programs.opencode`の設定モジュールから参照できます。
  _module.args.konoka = {
    plugins = konokaPlugins;
    inherit allPluginNames skillPluginNames skills;
  };
}
