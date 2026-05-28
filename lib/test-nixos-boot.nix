{
  top,
  lib,
  importPkgsStable,
  ...
}:
lib.mapAttrs
  (
    name: hostDef:
    (importPkgsStable hostDef.system).testers.runNixOSTest {
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
        imports = hostDef.modules ++ [
          ./nixos/test/vm-override.nix
        ];
      };
      # テスト環境はネットワークに繋がっていないため、
      # ネットワーク依存のユニットは失敗します。
      # よって全体成功を期待することはできません。
      # multi-user.targetに到達すればひとまず成功とみなしています。
      testScript = ''
        machine.wait_for_unit("multi-user.target")
      '';
    }
  )
  (lib.filterAttrs (_: def: !(def.nixosSystem.config.wsl.enable or false)) top.config.flake.hostDefs)
