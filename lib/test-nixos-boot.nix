{
  lib,
  importPkgsStable,
  hostDefs,
  ...
}:
lib.mapAttrs (
  name: hostDef:
  let
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
    serveTargetTest = lib.concatMapStrings (
      serveCfg: # python
      ''
        machine.wait_until_succeeds(
            "ss -Hltn 'sport = :${toString serveCfg.port}'"
            " | grep -qF '127.0.0.1:${toString serveCfg.port}'"
        )
      '') (if tailscaleServe == null then [ ] else lib.attrValues tailscaleServe.services);

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

    # `postgresExtension`で宣言した拡張が実際に作られることを確認します。
    # `CREATE EXTENSION`は`postgresql-setup`がsuperuserで実行しますが、
    # CIの評価チェックはtoplevelの評価だけなので、
    # `lib.mkAfter`で継ぎ足したスクリプトの構文やpsqlの呼び出しの誤りを検出できず、
    # 実機へ適用して初めて失敗します。
    #
    # `postgresql-ready.service`は接続の受け付けまでしか保証せず、
    # setupの完了をホスト側から観測するunitも無いため、
    # 拡張が現れるまでリトライで待ちます。
    #
    # ホストにはpsqlが無いので、
    # コンテナへ入れてあるPostgreSQLパッケージのpsqlをホスト側から直接使います。
    postgresExtensions = hostDef.nixosSystem.config.postgresExtension or { };
    postgresPsql = lib.getExe' hostDef.nixosSystem.config.containers.postgresql.config.services.postgresql.finalPackage "psql";
    postgresExtensionTest = lib.optionalString (postgresExtensions != { }) (
      # python
      ''
        machine.wait_for_unit("postgresql-ready.service")
      ''
      + lib.concatStrings (
        lib.mapAttrsToList (
          db:
          lib.concatMapStrings (
            ext: # python
            ''
              machine.wait_until_succeeds(
                  "runuser -u postgres --"
                  " ${postgresPsql} -h /run/postgresql -d '${db}'"
                  " -tAc \"SELECT 1 FROM pg_extension WHERE extname='${ext}'\""
                  " | grep -q 1"
              )
            ''
          )
        ) postgresExtensions
      )
    );

    # コンテナとmicroVMからの転送の許可リスト(`nixos/native-linux/machine-egress.nix`)が、
    # 実際に読み込まれていて、宣言した通りの形になっていることを確認します。
    # この境界はテーブルが消えても残りのルールセットは問題なく読み込まれるので静かに消えます。
    #
    # 発火条件は守りたいもの(出口を絞るべきマシンがある)にして、
    # 守り方(テーブルの有無)には連動させません。
    # テーブル名は設定から直接参照するので、
    # テーブルが消えればこの検査ごと消えるのではなく、
    # 属性が無いという評価エラーで止まります。
    #
    # 独立したベースチェインなので他のチェインとの並び順は関係ありません。
    # 代わりに以下を見ます。
    #
    # - NATが転送を通すインターフェイスからのパケットが許可リストのチェインへ飛ぶこと
    # - `internet`から除く集合に、LANとDNAT後のコンテナを含む`192.168.0.0/16`とtailnetの範囲が入っていること
    # - IPv6で`internet`から除く集合に、tailnetと他のコンテナを含むULA全体とリンクローカルが入っていること
    # - 各マシンのacceptが宣言した宛先の数だけあり、`internet`はIPv4とIPv6の1つずつで除く集合の否定で書かれていること
    # - 各マシンのルールの末尾と、チェイン全体の末尾がdropであること
    nft = lib.getExe' (importPkgsStable hostDef.system).nftables "nft";
    machineEgress = hostDef.nixosSystem.config.local.machineEgress or { };
    machineEgressTest =
      lib.optionalString (machineEgress != { }) # python
        ''
          machine.wait_for_unit("nftables.service")
          egress_table = "${hostDef.nixosSystem.config.networking.nftables.tables.machine-egress.name}"

          egress_forward = machine.succeed(f"${nft} list chain inet {egress_table} forward")
          assert "jump egress" in egress_forward, egress_forward

          private_networks = machine.succeed(f"${nft} list set inet {egress_table} private-networks")
          for prefix in ["192.168.0.0/16", "${hostDef.nixosSystem.config.local.tailscale.ipv4Range}"]:
              assert prefix in private_networks, private_networks

          private_networks6 = machine.succeed(f"${nft} list set inet {egress_table} private-networks6")
          for prefix in ["fc00::/7", "fe80::/10"]:
              assert prefix in private_networks6, private_networks6

          egress = machine.succeed(f"${nft} list chain inet {egress_table} egress")
          # テーブルとチェインの枠を除いたルールの行だけにします。
          egress_rules = [
              line.strip()
              for line in egress.splitlines()
              if line.strip() and not line.strip().startswith(("table ", "chain ", "}"))
          ]
          assert "drop" in egress_rules[-1].split(), egress
        ''
      + lib.concatMapStrings (
        m: # python
        ''
          machine_rules = [r for r in egress_rules if 'iifname "${m.interface}"' in r]
          machine_accepts = [r for r in machine_rules if "accept" in r.split()]
          assert len(machine_accepts) == ${
            toString (lib.length m.destinations + (if m.internet then 2 else 0))
          }, machine_rules
          # 集合名は空白で区切られたトークンとして照合します。
          # 部分文字列で見ると`@private-networks`が`@private-networks6`にも一致します。
          assert ${if m.internet then "" else "not "}any(
              "@private-networks" in r.split() for r in machine_accepts
          ), machine_rules
          assert ${if m.internet then "" else "not "}any(
              "@private-networks6" in r.split() and "nexthop fe80::/10" in r for r in machine_accepts
          ), machine_rules
          assert "drop" in machine_rules[-1].split(), machine_rules
        '') (lib.attrValues machineEgress);

    # コンテナとmicroVMがIPv6で外へ出るための土台が、
    # `machine-egress`の許可リストとは別に揃っていることを確認します。
    # 許可リストはfilterテーブルのルールの形しか見ないので、
    # NATモジュールの`enableIPv6`が外れてIPv6のmasqueradeが消えても、
    # vethやTAPへのULAの付与が設定から抜けても通ってしまいます。
    #
    # 以下を見ます。
    #
    # - IPv6のNATテーブルにmasqueradeがあること
    # - IPv6アドレスを持つコンテナの設定ファイルに、ホスト側とコンテナ側のIPv6アドレスが書かれていること。
    #   コンテナのinitとホスト側のpostStartはこのファイルを読んでアドレスと経路を付けます
    # - ホスト側のsystemd-networkdの設定ファイルに、宣言したIPv6アドレスが書かれていること。
    #   `lib/container-veth.nix`とmicroVMのTAPはpostStartではなくこちらで付けます
    # - microVMのTAPに実際にIPv6アドレスが付くこと
    #
    # コンテナのvethは実際のインターフェイスを見ません。
    # テストVMでは秘密情報が無いので大半のコンテナが起動に失敗して、
    # vethが作られないからです。
    # microVMは秘密情報を要らないものだけなのでテストVMでも起動します。
    hostConfig = hostDef.nixosSystem.config;
    nat = hostConfig.networking.nat;
    ipv6Containers = lib.filterAttrs (_: c: c.hostAddress6 != null) hostConfig.containers;
    isIpv6 = address: lib.hasInfix ":" address;
    ipv6Networks = lib.filterAttrs (
      _: n: lib.any (a: isIpv6 a.Address) n.addresses
    ) hostConfig.systemd.network.networks;
    ipv6Vms = lib.filter (name: ipv6Networks ? "20-vm-${name}") (
      lib.attrNames (hostConfig.microvm.vms or { })
    );
    machineIpv6Test =
      lib.optionalString (nat.enable && nat.enableIPv6) # python
        ''
          machine.wait_for_unit("nftables.service")
          nat6 = machine.succeed("${nft} list table ip6 nixos-nat")
          assert "masquerade" in nat6, nat6
        ''
      + lib.concatStrings (
        lib.mapAttrsToList (
          name: c: # python
          ''
            container_conf = machine.succeed("cat /etc/nixos-containers/${name}.conf")
            assert "HOST_ADDRESS6=${c.hostAddress6}" in container_conf, container_conf
            assert "LOCAL_ADDRESS6=${c.localAddress6}" in container_conf, container_conf
          '') ipv6Containers
      )
      + lib.concatStrings (
        lib.mapAttrsToList (
          name: n:
          lib.concatMapStrings (
            a: # python
            ''
              machine.succeed("grep -qF 'Address=${a.Address}' /etc/systemd/network/${name}.network")
            '') (lib.filter (a: isIpv6 a.Address) n.addresses)
        ) ipv6Networks
      )
      + lib.concatMapStrings (
        name:
        lib.concatMapStrings (
          a: # python
          ''
            machine.wait_for_unit("microvm@${name}.service")
            machine.wait_until_succeeds("ip -6 addr show dev vm-${name} | grep -qF '${a.Address}'")
          '') (lib.filter (a: isIpv6 a.Address) ipv6Networks."20-vm-${name}".addresses)
      ) ipv6Vms;

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
    + caddyAdminTest
    + caddyHealthTest
    + redirectTest
    + serveTargetTest
    + postgresExtensionTest
    + machineEgressTest
    + machineIpv6Test;
  }
) (lib.filterAttrs (_: def: !(def.nixosSystem.config.wsl.enable or false)) hostDefs)
