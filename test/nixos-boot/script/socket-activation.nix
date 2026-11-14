# `lib/container-socket-activation.nix`が作るproxyを確認します。
#
# 待ち受けは、IPv6のloopbackに加えて、
# 既定の接続先を`127.0.0.1`で持つ外部のツールのためにIPv4のloopbackでも意図して残しています。
# 片方が消えても、評価とブートは通ったまま退行します。
#
# 転送先のIPv6アドレスを角括弧で囲まずに書くのは、
# `systemd-socket-proxyd`が角括弧付きの書き方を名前として引いて失敗するからです。
# 直感に反するので、「直す」つもりで囲むと壊れます。
#
# 以下を見ます。
#
# - socketが宣言した全てのアドレスで待ち受けていること。
#   接続すると起動の引き金になってテストVMの中でコンテナが起き上がるので、`ss`で見ます
# - 実際の`ExecStart`をそのまま動かすと、転送先へ中継できること。
#   コンテナはテストVMではidmapの制約で起動できないので、
#   転送先のアドレスをloopbackに付けて、そこへ代わりのHTTPサーバを立てます
{
  lib,
  pkgs,
  config,
  ...
}:
let
  curl = lib.getExe pkgs.curl;
  python = lib.getExe pkgs.python3;
  socketActivate = lib.getExe' config.systemd.package "systemd-socket-activate";
  proxies = lib.filterAttrs (
    name: _: lib.hasSuffix "-proxy" name && config.systemd.services ? ${name}
  ) config.systemd.sockets;
  # 代わりに待ち受けるポートは、実際のsocketのポートと重ならない番号にします。
  checkPort = index: toString (47000 + index);
in
lib.concatStrings (
  lib.imap0 (
    index: name:
    let
      socket = proxies.${name};
      execStart = config.systemd.services.${name}.serviceConfig.ExecStart;
      # `<アドレス>:<ポート>`の最後の`:`で分けます。
      target = lib.last (lib.splitString " " execStart);
      targetParts = lib.splitString ":" target;
      targetPort = lib.last targetParts;
      targetAddress = lib.concatStringsSep ":" (lib.init targetParts);
      port = checkPort index;
    in
    lib.concatMapStrings (
      stream: # python
      ''
        machine.wait_until_succeeds(
            "ss -Hltn | grep -qF ' ${stream} '"
        )
      '') socket.listenStreams
    # python
    + ''
      machine.succeed("ip -6 addr add ${targetAddress}/128 dev lo nodad")
      machine.succeed("mkdir -p /tmp/${name} && echo ok > /tmp/${name}/index.html")
      machine.succeed(
          "systemd-run --unit=${name}-check-target"
          " ${python} -m http.server --bind ${targetAddress} --directory /tmp/${name} ${targetPort}"
      )
      machine.wait_until_succeeds("${curl} --fail --silent --max-time 3 'http://[${targetAddress}]:${targetPort}/'")
      machine.succeed(
          "systemd-run --unit=${name}-check-proxy"
          " ${socketActivate} --listen='[::1]:${port}' ${execStart}"
      )
      relayed = machine.wait_until_succeeds("${curl} --fail --silent --max-time 3 'http://[::1]:${port}/'")
      assert relayed.strip() == "ok", relayed
      machine.succeed("systemctl stop ${name}-check-proxy ${name}-check-target")
      machine.succeed("ip -6 addr del ${targetAddress}/128 dev lo")
    ''
  ) (lib.attrNames proxies)
)
