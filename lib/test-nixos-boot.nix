{
  lib,
  importPkgsStable,
  hostDefs,
  ...
}:
lib.mapAttrs (
  name: hostDef:
  let
    # オンデマンド起動のproxyがlistenできたかを確認します。
    # `sockets.target`はwants関係なので、
    # ポートの衝突などでsocketユニットが起動に失敗してもtargetは到達してしまいます。
    # ホストごとの分岐を書かずに済むように、
    # 実際の設定から`-proxy`のsocketユニットを集めます。
    proxySockets = lib.filter (lib.hasSuffix "-proxy") (
      lib.attrNames hostDef.nixosSystem.config.systemd.sockets
    );

    # Tailscale Serviceを公開するホストだけで、
    # `lib/tailscale-serve.nix`が立てるHTTPSリダイレクタの振る舞いを確認します。
    # Hostを透過させてリダイレクト先を組み立てる、
    # 308でメソッドを保存する、
    # tailnet外のHostを弾く、
    # というどれもが設定の書き換えで静かに壊れます。
    # `caddy.service`の起動待ちも兼ねていて、
    # バインド失敗や設定エラーで上がらなければここで落ちます。
    #
    # テストVMはtailscaledを無効化しているので、
    # Tailscale Serve経由ではなくリダイレクタのポートへ直接投げます。
    #
    # `lib/tailscale-serve.nix`をimportしていないホストにはオプション自体が生えないので、
    # `or`で無いものとして扱います。
    tailscaleServe = hostDef.nixosSystem.config.local.tailscaleServe or null;
    curl = lib.getExe (importPkgsStable hostDef.system).curl;
    redirectTest =
      # 文字列の中身は`runNixOSTest`のテストドライバが実行するPythonです。
      # 直前の`# python`はtree-sitterなどに埋め込み言語を伝えてハイライトさせる、
      # nixpkgsでも使われている注入ヒントのコメントです。
      lib.optionalString (tailscaleServe != null && tailscaleServe.services != { }) # python
        ''
          machine.wait_for_unit("caddy.service")
          machine.wait_for_open_port(${toString tailscaleServe.redirectPort}, "127.0.0.1")
          machine.succeed(
              "${curl} --fail --silent --show-error --head"
              " --header 'Host: example.${hostDef.nixosSystem.config.local.tailscale.tailnet}'"
              " --write-out '%{http_code} %{redirect_url}' --output /dev/null"
              " 'http://127.0.0.1:${toString tailscaleServe.redirectPort}/foo?a=1'"
              " | grep --fixed-strings"
              " '308 https://example.${hostDef.nixosSystem.config.local.tailscale.tailnet}/foo?a=1'"
          )
          machine.succeed(
              "${curl} --silent --header 'Host: evil.example.com'"
              " --write-out '%{http_code}' --output /dev/null"
              " 'http://127.0.0.1:${toString tailscaleServe.redirectPort}/foo' | grep --fixed-strings 400"
          )
        '';
  in
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
        ../nixos/test/vm-override.nix
      ];
    };
    # テスト環境はネットワークに繋がっていないため、
    # ネットワーク依存のユニットは失敗します。
    # よって全体成功を期待することはできません。
    # multi-user.targetに到達すればひとまず成功とみなしています。
    testScript = ''
      machine.wait_for_unit("multi-user.target")
    ''
    + lib.concatMapStrings (socket: ''
      machine.wait_for_unit("${socket}.socket")
    '') proxySockets
    + redirectTest;
  }
) (lib.filterAttrs (_: def: !(def.nixosSystem.config.wsl.enable or false)) hostDefs)
