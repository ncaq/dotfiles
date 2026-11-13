# Tailscale Serviceを公開するホストで、`lib/tailscale-serve.nix`の振る舞いを確認します。
#
# `lib/tailscale-serve.nix`をimportしていないホストにはオプション自体が生えないので、
# `or`で無いものとして扱います。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  tailscaleServe = config.local.tailscaleServe or null;
  services = if tailscaleServe == null then { } else tailscaleServe.services;
  curl = lib.getExe pkgs.curl;

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
  redirect = # python
    ''
      machine.wait_for_unit("caddy.service")
      machine.wait_for_open_port(${toString tailscaleServe.redirectPort}, "127.0.0.1")

      tailnet = "${config.local.tailscale.tailnet}"
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

  # Tailscale Serveの転送先がホストのloopbackで待ち受けているかを確認します。
  # 転送先はsocket activationのproxyだったり常時起動のCaddyのvhostだったりしますが、
  # どちらもwants関係で引き込まれるだけなので、
  # ポートの衝突やbindの書き間違いで上がらなくてもboot自体は成功してしまいます。
  # 名前は引けるのに接続だけができない状態になり、
  # tailnet経由でアクセスして初めて気付く壊れ方をします。
  # ホストごとの分岐を書かずに済むように、実際の設定から転送先のポートを集めます。
  #
  # 判定に`wait_for_open_port`を使わないのは、
  # あれがTCP接続で確かめるためです。
  # 転送先がsocket activationのproxyだと接続がそのまま起動の引き金になり、
  # テストVMの中でコンテナが起き上がってしまいます。
  # 接続せずに待ち受けだけを見たいので`ss`で確かめます。
  serveTarget = lib.concatMapStrings (
    serveCfg: # python
    ''
      machine.wait_until_succeeds(
          "ss -Hltn 'sport = :${toString serveCfg.port}'"
          " | grep -qF '127.0.0.1:${toString serveCfg.port}'"
      )
    '') (lib.attrValues services);
in
lib.optionalString (services != { }) (redirect + serveTarget)
