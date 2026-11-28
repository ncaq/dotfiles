# Tailscale Serviceを公開するホストで、Serveの転送先がホストのIPv6のloopbackで待ち受けているかを確認します。
# Serveは`[::1]`へ転送するので、127.0.0.1だけで待ち受けていても繋がりません。
# 転送先はsocket activationのproxyだったり常時起動のCaddyのvhostだったりしますが、
# どちらもwants関係で引き込まれるだけなので、
# ポートの衝突やbindの書き間違いで上がらなくてもboot自体は成功してしまいます。
# 名前は引けるのに接続だけができない状態になり、
# tailnet経由でアクセスして初めて気付く壊れ方をします。
# ホストごとの分岐を書かずに済むように、実際の設定から転送先のポートを集めます。
#
# HTTPSリダイレクタの振る舞いは、モジュールのテスト(`nixos/core/tailscale-serve.test.nix`)で見ています。
#
# 判定に`wait_for_open_port`を使わないのは、
# あれがTCP接続で確かめるためです。
# 転送先がsocket activationのproxyだと接続がそのまま起動の引き金になり、
# テストVMの中でコンテナが起き上がってしまいます。
# 接続せずに待ち受けだけを見たいので`ss`で確かめます。
{ lib, config, ... }:
lib.concatMapStrings (
  serveCfg: # python
  ''
    machine.wait_until_succeeds(
        "ss -Hltn 'sport = :${toString serveCfg.port}'"
        " | grep -qF '[::1]:${toString serveCfg.port}'"
    )
  '') (lib.attrValues config.local.tailscaleServe.services)
