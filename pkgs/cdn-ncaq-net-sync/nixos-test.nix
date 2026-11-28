# ジョブが書くステージングから配信ディレクトリへ写す同期(`module.nix`)を確認します。
# ジョブが置いたシンボリックリンクがそのまま写ると、
# 配信する側がリンクを辿ってホストのファイルを配信してしまいます。
# 同期のオプションや隔離が外れても、評価とブートは通ったまま退行します。
#
# systemd-nspawnのコンテナの中で`module.nix`の実際のユニットを、その隔離のまま動かして確かめます。
# ホストの構成には依らないので、ホストをブートするテストではなくここに置いています。
# 写したファイルをコンテナの中のCaddyが配信することは、seminarのブートテストで見ています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# 以下を見ます。
#
# - 印を更新すると、path unitが同期を起動すること
# - ツリーの中のリンクは捨てられ、通常のファイルだけが同期のユーザの所有の644で写ること
# - ステージングから消えたファイルが、配信ディレクトリからも消えること
# - ジョブのユーザがステージングの`public`自体を動かせないこと
# - それでも`public`が`/etc`へのリンクになった時に、`/etc`の中身が写らないこと
{ localLib, testers }:
let
  stagingUser = "runner";
  cdnRoot = "/srv/cdn";
  deployRoot = "/srv/cdn-deploy";
in
testers.runNixOSTest {
  name = "cdn-ncaq-net-sync";

  node.specialArgs.hardening = localLib.hardening;

  containers.machine = {
    imports = [ ./module.nix ];
    services.cdn-ncaq-net-sync = {
      enable = true;
      inherit cdnRoot deployRoot stagingUser;
    };
    users = {
      users.${stagingUser} = {
        isSystemUser = true;
        group = stagingUser;
      };
      groups.${stagingUser} = { };
    };
  };

  testScript = # python
    ''
      deploy_root = "${deployRoot}"
      # ジョブのワークフローが書き込む先と同じパスを、モジュールの値から引かずに直に書きます。
      # モジュールの側で名前が変わると、ワークフローが書いても同期されなくなるからです。
      deploy_public = f"{deploy_root}/public"
      deploy_stamp = f"{deploy_root}/deployed"
      cdn_root = "${cdnRoot}"


      def as_runner(command):
          return f"runuser -u ${stagingUser} -- sh -c '{command}'"


      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("cdn-ncaq-net-sync.path")

      with subtest("リンクを捨てて通常のファイルだけを写す"):
          machine.succeed(as_runner(
              f"mkdir -p {deploy_public}/sub"
              f" && echo hello > {deploy_public}/a.txt"
              f" && echo nested > {deploy_public}/sub/b.txt"
              f" && echo stale > {deploy_public}/stale.txt"
              f" && ln -s /etc/shadow {deploy_public}/shadow-link"
              f" && ln -s /etc {deploy_public}/sub/etc-link"
              f" && touch {deploy_stamp}"
          ))
          machine.wait_until_succeeds(f"test -f {cdn_root}/sub/b.txt")
          machine.fail(f"test -e {cdn_root}/shadow-link -o -L {cdn_root}/shadow-link")
          machine.fail(f"test -e {cdn_root}/sub/etc-link -o -L {cdn_root}/sub/etc-link")
          served = machine.succeed(f"stat -c '%U %a' {cdn_root}/a.txt").strip()
          assert served == "cdn-ncaq-net 644", served
          served_body = machine.succeed(f"cat {cdn_root}/sub/b.txt")
          assert served_body == "nested\n", served_body

      with subtest("ステージングから消えたファイルを消す"):
          machine.succeed(f"test -f {cdn_root}/stale.txt")
          machine.succeed(as_runner(f"rm {deploy_public}/stale.txt && touch {deploy_stamp}"))
          machine.wait_until_fails(f"test -e {cdn_root}/stale.txt")
          machine.succeed(f"test -f {cdn_root}/a.txt")

      with subtest("ジョブはpublic自体を動かせない"):
          machine.fail(as_runner(f"mv {deploy_public} {deploy_public}.moved"))
          machine.fail(as_runner(f"touch {deploy_root}/new-entry"))

      with subtest("publicがリンクになっても写さない"):
          machine.succeed(f"mv {deploy_public} {deploy_public}.orig && ln -s /etc {deploy_public}")
          machine.fail("systemctl start cdn-ncaq-net-sync.service")
          # 隔離の準備のような別の理由で失敗していないことを、コマンドが出す理由で確かめます。
          machine.wait_until_succeeds(
              "journalctl --unit=cdn-ncaq-net-sync.service --no-pager"
              " | grep --fixed-strings 'is not a real directory'"
          )
          machine.fail(f"test -e {cdn_root}/passwd")
          # 写す前に止まるので、`--delete`で配信中の中身が消えることもありません。
          machine.succeed(f"test -f {cdn_root}/a.txt")
    '';
}
