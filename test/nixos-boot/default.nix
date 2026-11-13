/**
  ホストごとにNixOSの構成をVMでブートして、実際に動くかを確かめるテスト。

  型: { lib, importPkgsStable, importDirModules, hostDefs } -> AttrSet Derivation

  構成:
    `vm/`はテストVMで動かないものを無効化したりモックにしたりするNixOSのモジュール。
    `script/`はブートした後にテストVMの中で確かめることを、トピックごとに分けたもの。
    `script/`の各ファイルは`{ lib, pkgs, config, startsInTestVm }`を受け取り、
    テストドライバが実行するPythonを返す。
    `config`はテストVMではなく実機の構成で、確かめる対象をそこから集める。
    そのホストに確かめる対象が無ければ空文字列を返す。
    どちらもファイルを足すだけで全ホストのテストに加わる。

  なぜトピックごとにVMを分けないか:
    1回のテストの時間の大半はブートで、ブートした後の確認は全部で十数秒しかかからない。
    トピックごとにVMを分けてもブートの回数が増えるだけになる。
    ホストごとのテストは別のderivationなので、ホスト同士は並列に走る。
*/
{
  lib,
  importPkgsStable,
  importDirModules,
  hostDefs,
}:
let
  scripts = importDirModules ./script;

  # トピックの確認を`subtest`のブロックへ入れるために各行を字下げする。
  # ログにトピックの名前と所要時間が出る。
  indent =
    text:
    lib.concatMapStrings (line: if line == "" then "\n" else "    ${line}\n") (
      lib.splitString "\n" (lib.removeSuffix "\n" text)
    );
  renderTopic = topic: "with subtest(${builtins.toJSON topic.name}):\n" + indent topic.script;
in
lib.mapAttrs (
  name: hostDef:
  let
    pkgs = importPkgsStable hostDef.system;
    inherit (hostDef.nixosSystem) config;
    args = {
      inherit lib pkgs config;
      # テストVMでも起動するmicroVMかどうか。
      # ホスト側のユニットが他のユニットを`requires`しているmicroVMは、
      # 秘密情報から作るものを待っていてテストVMでは起動しない。
      # GitHub ActionsのランナーのVMがそうで、登録トークンを発行できないと起動しない。
      startsInTestVm =
        vmName: ((config.systemd.services."microvm@${vmName}" or { }).requires or [ ]) == [ ];
    };
    topics = lib.filter (topic: topic.script != "") (
      map (path: {
        name = lib.removeSuffix ".nix" (baseNameOf path);
        script = import path args;
      }) scripts
    );
  in
  pkgs.testers.runNixOSTest {
    name = "test-nixos-boot-${name}";
    node = {
      # `runNixOSTest`が追加する`nixpkgs`の読み込み専用設定を無効化します。
      # `hardware-configuration.nix`が存在する時、
      # `nixpkgs.hostPlatform`を設定しているので、
      # 読み込み専用にされた`nixpkgs`オプションへの設定がエラーになります。
      # 基本的にモジュール単位のテスト機構であり、
      # 全体のブートを想定していないゆえの挙動でしょう。
      # 自動生成ファイルである`hardware-configuration.nix`を編集したくないため、
      # 上書きを有効にしてしまいます。
      # ブートのテストの場合ではあまり問題にならないはずです。
      pkgsReadOnly = false;
      inherit (hostDef) specialArgs;
    };
    nodes.machine = {
      imports = hostDef.modules ++ [ ./vm ];
    };
    # テスト環境はネットワークに繋がっていないため、
    # ネットワーク依存のユニットは失敗します。
    # よって全体成功を期待することはできません。
    # multi-user.targetに到達すればひとまず成功とみなしています。
    testScript = ''
      machine.wait_for_unit("multi-user.target")
    ''
    + lib.concatMapStrings renderTopic topics;
  }
) (lib.filterAttrs (_: def: !(def.nixosSystem.config.wsl.enable or false)) hostDefs)
