# 探して見つけたゴミ箱が、所有者の権限で掃除されることを確認します。
#
# `trash-empty-stray.service`はrootで動き、ユーザが好きに作れる場所からゴミ箱を探します。
# `trash-empty`は`files`がシンボリックリンクでも辿って中身を消すので、
# rootのまま掃除すると、リンクを仕込んだユーザに任意の場所を消させられます。
# 権限を落とす処理が外れても、ビルドは通り、掃除も今まで通り動いて見えます。
#
# sandwichのテストは一般ユーザとして走るので、権限を落とす場面を確かめられません。
# VMの中で`nixos/core/trash.nix`の実際のユニットを、その権限の絞り込みのまま動かして、以下を見ます。
#
# - 期限切れのエントリが消えて、空になったゴミ箱がゴミ箱ごと消える
# - 期限切れでないエントリが残る
# - `files`をrootしか書けない場所へのシンボリックリンクにしても、リンクの先が残る
# - rootが所有するゴミ箱が掃除される。`sudo trash`でできるゴミ箱である
# - 名前のuidと所有者が食い違うゴミ箱が、所有者の権限で掃除される
#
# 権限の絞り込みが強すぎてuidを変えられない時は、ユニットが失敗するのでここで落ちます。
#
# ユニットの定義はホストごとに変わらないので、ホストごとのブートテストではなくここに置いています。
{ testers }:
let
  user = "alice";
  base = "/home/${user}/trash-empty-stray-test";
  # ユーザのホームの外にある、rootしか書けない場所。
  victim = "/var/lib/trash-empty-stray-test-victim";
  # どんな保持日数でも期限切れになる昔と、期限切れにならない先。
  expired = "2000-01-01T00:00:00";
  fresh = "2999-01-01T00:00:00";
in
testers.runNixOSTest {
  name = "trash-empty-stray";

  nodes.machine = {
    imports = [ ../../nixos/core/trash.nix ];
    # ホストの構成では`flake.nix`の`specialArgs`から渡している。
    _module.args.hardening = import ../../lib/systemd-hardening.nix;
    users.users.${user}.isNormalUser = true;
  };

  testScript = # python
    ''
      def put_entry(runner, trash_dir, name, deletion_date):
          # `trash-put`が作るのと同じ形で、ゴミ箱へエントリを1つ置きます。
          machine.succeed(
              f"{runner} mkdir -p {trash_dir}/info {trash_dir}/files",
              f"{runner} touch {trash_dir}/files/{name}",
              f"printf '[Trash Info]\\nPath={name}\\nDeletionDate={deletion_date}\\n'"
              f" | {runner} tee {trash_dir}/info/{name}.trashinfo",
          )

      as_user = "runuser -u ${user} --"
      as_root = ""

      machine.wait_for_unit("multi-user.target")

      put_entry(as_user, "${base}/expired/deep/.Trash-1000", "old", "${expired}")
      put_entry(as_user, "${base}/fresh/.Trash-1000", "new", "${fresh}")
      put_entry(as_user, "${base}/mismatch/.Trash-0", "old", "${expired}")
      machine.succeed(f"{as_user} mkdir -p ${base}/root-owned")
      put_entry(as_root, "${base}/root-owned/.Trash-0", "old", "${expired}")
      machine.succeed(
          "mkdir -p ${victim}/sub",
          "touch ${victim}/file ${victim}/sub/file",
          f"{as_user} mkdir -p ${base}/attack/.Trash-1000 ${base}/attack-as-root/.Trash-0",
          f"{as_user} ln -s ${victim} ${base}/attack/.Trash-1000/files",
          f"{as_user} ln -s ${victim} ${base}/attack-as-root/.Trash-0/files",
      )

      machine.succeed("systemctl start trash-empty-stray.service")

      machine.succeed(
          "test ! -e ${base}/expired/deep/.Trash-1000",
          "test -e ${base}/fresh/.Trash-1000/files/new",
          "test -e ${base}/fresh/.Trash-1000/info/new.trashinfo",
          "test ! -e ${base}/mismatch/.Trash-0",
          "test ! -e ${base}/root-owned/.Trash-0",
          "test -e ${victim}/file",
          "test -e ${victim}/sub/file",
      )
    '';
}
