# cdn.ncaq.netのランナーのジョブが書くステージングから、
# 配信ディレクトリへ写す同期を確認します。
# ジョブが置いたシンボリックリンクがそのまま写ると、
# Caddyがリンクを辿ってホストのファイルを配信してしまいます。
# 同期のオプションや隔離が外れても、評価とブートは通ったまま退行します。
#
# 以下を見ます。
#
# - ツリーの中のリンクは捨てられ、通常のファイルだけが同期のユーザの所有の644で写ること
# - ジョブのユーザがステージングの`public`自体を動かせないこと
# - それでも`public`が`/etc`へのリンクになった時に、`/etc`の中身が写らないこと
# - 写したファイルを、Cloudflare Tunnelの転送先にしているコンテナの中のCaddyが配信すること。
#   コンテナのbind mountやCaddyの設定やハードニングが崩れると、
#   ホストの同期は通ったまま配信だけが失敗します。
#   テストVMではコンテナを`privateUsers = "identity"`で動かします(`test/nixos-boot/vm/container.nix`)
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
  cdnDeploy = config.local.cdnDeploy or null;
  curl = lib.getExe pkgs.curl;
in
lib.optionalString (cdnDeploy != null) # python
  ''
    machine.wait_for_unit("${cdnDeploy.syncService}.path")
    deploy_root = "${cdnDeploy.deployRoot}"
    deploy_public = f"{deploy_root}/public"
    cdn_root = "${cdnDeploy.cdnRoot}"


    def as_runner(command):
        return f"runuser -u github-runner -- sh -c '{command}'"


    machine.succeed(as_runner(
        f"mkdir -p {deploy_public}/sub"
        f" && echo hello > {deploy_public}/a.txt"
        f" && echo nested > {deploy_public}/sub/b.txt"
        f" && ln -s /etc/shadow {deploy_public}/shadow-link"
        f" && ln -s /etc {deploy_public}/sub/etc-link"
        " && touch ${cdnDeploy.deployStamp}"
    ))
    machine.wait_until_succeeds(f"test -f {cdn_root}/sub/b.txt")
    machine.fail(f"test -e {cdn_root}/shadow-link -o -L {cdn_root}/shadow-link")
    machine.fail(f"test -e {cdn_root}/sub/etc-link -o -L {cdn_root}/sub/etc-link")
    served = machine.succeed(f"stat -c '%U %a' {cdn_root}/a.txt").strip()
    assert served == "${cdnDeploy.syncUser} 644", served
    # コンテナの中のCaddyが待ち受けを始めるまで待ちます。
    served_body = machine.wait_until_succeeds(
        "${curl} --fail --silent --show-error --max-time 3 ${cdnDeploy.origin}/sub/b.txt"
    )
    assert served_body == "nested\n", served_body

    machine.fail(as_runner(f"mv {deploy_public} {deploy_public}.moved"))
    machine.fail(as_runner(f"touch {deploy_root}/new-entry"))

    machine.succeed(f"mv {deploy_public} {deploy_public}.orig && ln -s /etc {deploy_public}")
    machine.fail("systemctl start ${cdnDeploy.syncService}.service")
    machine.fail(f"test -e {cdn_root}/passwd")
    # 写す前に止まるので、`--delete`で配信中の中身が消えることもありません。
    machine.succeed(f"test -f {cdn_root}/a.txt")
    machine.succeed(
        f"rm {deploy_public} && mv {deploy_public}.orig {deploy_public}"
        " && systemctl reset-failed ${cdnDeploy.syncService}.service"
    )
  ''
