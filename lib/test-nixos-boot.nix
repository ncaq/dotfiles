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

    # `nixos/core/caddy.nix`がadmin APIをUNIXソケットへ移せているかを確認します。
    # 設定が外れてもCaddyは既定の`127.0.0.1:2019`で普通に起動してしまうので、
    # 他のテストは全て通ったまま無言で退行します。
    #
    # 判定条件をTailscale Serviceの有無ではなくCaddyの有無にしているのは、
    # `nixos/core/caddy.nix`がCaddyを有効にした全ホストに効くからです。
    caddyAdminTest =
      lib.optionalString hostDef.nixosSystem.config.services.caddy.enable # python
        ''
          machine.wait_for_unit("caddy.service")
          machine.succeed("test -S /run/caddy/admin.sock")
          machine.fail("${curl} --fail --silent --max-time 3 http://127.0.0.1:2019/config/")
        '';

    # `nixos/core/caddy.nix`が立てる死活監視用のエンドポイントを確認します。
    # 監視エージェントがここを叩いているので、
    # パスやポートが変わると監視だけが静かに落ちます。
    # 127.0.0.1に限定できているかも合わせて見ます。
    caddyHealthTest =
      lib.optionalString hostDef.nixosSystem.config.services.caddy.enable # python
        ''
          machine.wait_for_open_port(2020, "127.0.0.1")
          machine.succeed("${curl} --fail --silent --max-time 3 http://127.0.0.1:2020/health")
          machine.fail("${curl} --fail --silent --max-time 3 http://[::1]:2020/health")
        '';

    redirectTest =
      # 文字列の中身は`runNixOSTest`のテストドライバが実行するPythonです。
      # 直前の`# python`はtree-sitterなどに埋め込み言語を伝えてハイライトさせる、
      # nixpkgsでも使われている注入ヒントのコメントです。
      lib.optionalString (tailscaleServe != null && tailscaleServe.services != { }) # python
        ''
          machine.wait_for_unit("caddy.service")
          machine.wait_for_open_port(${toString tailscaleServe.redirectPort}, "127.0.0.1")

          tailnet = "${hostDef.nixosSystem.config.local.tailscale.tailnet}"
          redirect_port = ${toString tailscaleServe.redirectPort}


          def assert_response(host, expected, method="GET", path="/foo?a=1"):
              """リダイレクタへ1つ投げて`<ステータス> <リダイレクト先>`が期待通りか見ます。

              `grep`へ繋ぐとパイプの終了コードが`grep`のものになり、
              curl自身の失敗が握り潰されて原因が読めなくなるので、
              判定はPython側で行います。
              400を期待するケースがあるので`--fail`は付けません。
              """
              actual = machine.succeed(
                  "${curl} --silent --show-error --output /dev/null"
                  f" --request {method} --header 'Host: {host}'"
                  " --write-out '%{http_code} %{redirect_url}'"
                  f" 'http://127.0.0.1:{redirect_port}{path}'"
              )
              assert actual == expected, f"Host: {host} ({method}) -> {actual}"


          redirected = f"308 https://example.{tailnet}/foo?a=1"
          # 弾かれた時はリダイレクト先が空なので末尾に区切りの空白だけが残ります。
          rejected = "400 "

          assert_response(f"example.{tailnet}", redirected)

          # `{host}`はHostヘッダからポートを除いた値なので、
          # ポート付きで来てもリダイレクト先にポートは付きません。
          # 別のプレースホルダへ書き換えると`:80`が混入して壊れます。
          assert_response(f"example.{tailnet}:80", redirected)

          # 301ではなく308を選んでいるのはメソッドを保存するためなので、
          # 非冪等なメソッドでもリダイレクトされることまで見ます。
          assert_response(f"example.{tailnet}", redirected, method="POST")

          assert_response("evil.example.com", rejected)
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
    + caddyAdminTest
    + caddyHealthTest
    + redirectTest;
  }
) (lib.filterAttrs (_: def: !(def.nixosSystem.config.wsl.enable or false)) hostDefs)
