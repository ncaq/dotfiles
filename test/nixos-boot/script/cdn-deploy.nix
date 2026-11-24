# cdn.ncaq.netのランナのジョブが書いたファイルを、
# Cloudflare Tunnelの転送先にしているコンテナの中のCaddyが配信することを確認します。
# コンテナのbind mountやCaddyの設定やハードニングが崩れると、
# ホストの同期は通ったまま配信だけが失敗します。
# テストVMではコンテナを`privateUsers = "identity"`で動かします(`test/nixos-boot/vm/container.nix`)
#
# 同期がリンクを捨てることや隔離は、同期のパッケージのテスト(`pkgs/cdn-ncaq-net-sync`)で見ています。
# ここで見るのは、実機の置き場所とユーザで、ステージングから配信までが繋がっていることです。
#
# `nixos/host/seminar/cdn.nix`をimportしていないホストにはオプション自体が生えないので、
# `or`で無いものとして扱います。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cdnSync = config.services.cdn-ncaq-net-sync or null;
  origin = config.services.cloudflared.tunnels.seminar.ingress."cdn.ncaq.net";
  curl = lib.getExe pkgs.curl;
in
lib.optionalString (cdnSync != null && cdnSync.enable) # python
  ''
    machine.wait_for_unit("cdn-ncaq-net-sync.path")
    machine.succeed(
        "runuser -u ${cdnSync.stagingUser} -- sh -c '"
        "mkdir -p ${cdnSync.deployPublic}/sub"
        " && echo nested > ${cdnSync.deployPublic}/sub/b.txt"
        " && touch ${cdnSync.deployStamp}"
        "'"
    )
    # 同期が写して、コンテナの中のCaddyが待ち受けを始めるまで待ちます。
    served_body = machine.wait_until_succeeds(
        "${curl} --fail --silent --show-error --max-time 3 ${origin}/sub/b.txt"
    )
    assert served_body == "nested\n", served_body
  ''
