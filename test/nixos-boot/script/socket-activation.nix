# 実機が宣言した`nixos/native-linux/container-socket-activation.nix`のproxyが、
# コンテナの宣言と噛み合っていることを確認します。
# proxy自体の振る舞い(待ち受けるアドレスと中継)は、
# モジュールのテスト(`nixos/native-linux/container-socket-activation.test.nix`)で見ています。
#
# proxyを宣言したコンテナは、ブート時には起動しない設定になります。
# その設定は`container-template.nix`の既定値との優先度の組み合わせで決まるので、
# どちらかを書き換えると、GPUを掴むコンテナがブート時に起動するようになります。
# テストVMではコンテナが起動できないので、それでも評価とブートは通ったまま退行します。
#
# 以下を見ます。
#
# - proxyを宣言したコンテナの`autoStart`が切れていること。評価時に見ます
# - 転送先のアドレスとポートが、コンテナの宣言と一致していること。評価時に見ます
# - socketが宣言した全てのアドレスで実際に待ち受けていること。
#   他のユニットとポートが衝突すると、評価は通ったまま待ち受けだけが失敗します。
#   接続すると起動の引き金になってテストVMの中でコンテナが起き上がるので、`ss`で見ます
{ lib, config, ... }:
let
  proxies = lib.filterAttrs (
    name: _: lib.hasSuffix "-proxy" name && config.systemd.services ? ${name}
  ) config.systemd.sockets;
in
lib.concatStrings (
  lib.mapAttrsToList (
    name: socket:
    let
      execStart = config.systemd.services.${name}.serviceConfig.ExecStart;
      # `<アドレス>:<ポート>`の最後の`:`で分けます。
      target = lib.last (lib.splitString " " execStart);
      targetParts = lib.splitString ":" target;
      targetPort = lib.last targetParts;
      targetAddress = lib.concatStringsSep ":" (lib.init targetParts);
      # ポートはホスト側とコンテナ側で共通です。
      container = config.containers.${lib.removeSuffix "-proxy" name};
      expectedAddress = container.localAddress6;
      expectedPort = lib.last (lib.splitString ":" (lib.head socket.listenStreams));
    in
    assert lib.assertMsg (
      targetAddress == expectedAddress
    ) "${name}: ExecStartから読んだ転送先のアドレス${targetAddress}がコンテナのアドレス${expectedAddress}と一致しません";
    assert lib.assertMsg (
      targetPort == expectedPort
    ) "${name}: ExecStartから読んだ転送先のポート${targetPort}が待ち受けのポート${expectedPort}と一致しません";
    assert lib.assertMsg (!container.autoStart) "${name}: socketで起動するコンテナが`autoStart`でブート時にも起動します";
    lib.concatMapStrings (
      stream: # python
      ''
        machine.wait_until_succeeds(
            "ss -Hltn | grep -qF ' ${stream} '"
        )
      '') socket.listenStreams
  ) proxies
)
