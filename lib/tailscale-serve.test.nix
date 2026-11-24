# `tailscale-serve.nix`が立てるHTTPSリダイレクタの振る舞いを確認します。
# Hostを透過させてリダイレクト先を組み立てる、
# 308でメソッドを保存する、
# tailnet外のHostを弾く、
# というどれもが設定の書き換えで静かに壊れます。
#
# systemd-nspawnのコンテナの中で、`tailscale-serve.nix`だけを読み込んでServiceを1つ宣言したマシンを動かします。
# リダイレクタはServiceを公開するホストの全てで同じなので、ホストをブートするテストではなくここに置いています。
# 実機のServiceの転送先が待ち受けていることは、ホストをブートするテストで見ています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# tailscaledは動かさないので、
# Tailscale Serve経由ではなくリダイレクタのポートへ直接投げます。
# Serviceを登録するユニットは起動に失敗しますが、リダイレクタには関わりません。
{ testers }:
let
  tailnet = import ./tailnet.nix;
in
testers.runNixOSTest {
  name = "tailscale-serve";

  node.specialArgs.hardening = import ./systemd-hardening.nix;

  containers.machine =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [ ./tailscale-serve.nix ];
      # `nixos/core/tailscale.nix`が定義するオプションのうち、リダイレクタが読むものだけを用意します。
      # モジュールごと読み込むとtailscaledが有効になり、認証できずに起動を粘ります。
      options.local.tailscale.tailnet = lib.mkOption {
        type = lib.types.str;
        default = tailnet;
      };
      config = {
        local.tailscaleServe.services.example = {
          service = "svc:example";
          label = "Example";
          port = 8000;
        };
        environment = {
          systemPackages = [ pkgs.curl ];
          # テストスクリプトがリダイレクタのポートを読みます。
          etc."tailscale-serve-redirect-port".text = toString config.local.tailscaleServe.redirectPort;
        };
      };
    };

  testScript = # python
    ''
      machine.wait_for_unit("caddy.service")
      redirect_port = int(machine.succeed("cat /etc/tailscale-serve-redirect-port"))
      machine.wait_for_open_port(redirect_port, "::1")

      tailnet = "${tailnet}"


      def assert_response(host, expected, method="GET", path="/foo?a=1"):
          """リダイレクタへ1つ投げて`<ステータス> <リダイレクト先>`が期待通りか見ます。

          `grep`へ繋ぐとパイプの終了コードが`grep`のものになり、
          curl自身の失敗が握り潰されて原因が読めなくなるので、
          判定はPython側で行います。
          400を期待するケースがあるので`--fail`は付けません。
          """
          actual = machine.succeed(
              "curl --silent --show-error --output /dev/null"
              f" --request {method} --header 'Host: {host}'"
              " --write-out '%{http_code} %{redirect_url}'"
              f" 'http://[::1]:{redirect_port}{path}'"
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

      # IPv4のloopbackでは待ち受けていないことを見ます。
      machine.fail(f"curl --silent --max-time 3 http://127.0.0.1:{redirect_port}/")
    '';
}
