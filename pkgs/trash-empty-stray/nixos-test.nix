# 探して見つけたゴミ箱が、所有者の権限で掃除されることを確認します。
#
# `trash-empty-stray.service`はrootで動き、ユーザが好きに作れる場所からゴミ箱を探します。
# rootのまま掃除すると、ゴミ箱の中身を細工したユーザに、自分では消せないものを消させられます。
# 所有者の権限へ落とす処理が外れても、ビルドは通り、掃除も今まで通り動いて見えます。
#
# sandwichのテストは一般ユーザとして走るので、権限を落とす場面を確かめられません。
# VMの中で`module.nix`の実際のユニットを、その権限の絞り込みのまま動かして、以下を見ます。
#
# - 期限切れのエントリが消えて、空になったゴミ箱がゴミ箱ごと消える
# - 期限切れでないエントリが残る
# - 一般ユーザのゴミ箱にある、rootにしか消せない中身を持つ期限切れのエントリが残る。
#   権限を落とす処理だけを確かめている。rootのまま掃除していれば消える
# - `files`をrootしか書けない場所へのシンボリックリンクにしても、リンクの先が残る。
#   こちらは掃除の前の確認(`info`と`files`が本物のディレクトリか)で弾かれる
# - rootが所有するゴミ箱が掃除される。`sudo trash`でできるゴミ箱である
# - 名前のuidと所有者が食い違うゴミ箱が、所有者の権限で掃除される
# - ユーザの一覧に無いuidが所有するゴミ箱が掃除される。
#   消したユーザや、他のホストから持ってきたデータの所有者が当たる。
#   主グループを引けない時の扱いが壊れると、そのゴミ箱ごとに毎日失敗し続ける
# - 起点と違うデバイスの中にあるゴミ箱が、期限切れでも残る。
#   ネットワークマウントやスナップショットのサブボリュームを辿らないための境界で、
#   マウントを作れないsandwichのテストでは確かめられない
#
# 権限の絞り込みが強すぎてuidを変えられない時は、ユニットが失敗するのでここで落ちます。
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
    imports = [ ./module.nix ];
    services.trash-empty = {
      enable = true;
      retentionDays = 7;
      stray.roots = [ "/home" ];
    };
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

      # 一般ユーザのゴミ箱の中に、rootにしか消せない中身を持つエントリを置く。
      # `info`と`files`は一般ユーザの本物のディレクトリなので、掃除の前の確認は通る。
      machine.succeed(
          f"{as_user} mkdir -p ${base}/undeletable/.Trash-1000/info ${base}/undeletable/.Trash-1000/files",
          "mkdir ${base}/undeletable/.Trash-1000/files/old",
          "touch ${base}/undeletable/.Trash-1000/files/old/kept",
          "printf '[Trash Info]\\nPath=old\\nDeletionDate=${expired}\\n'"
          f" | {as_user} tee ${base}/undeletable/.Trash-1000/info/old.trashinfo",
      )

      # ユーザの一覧に無いuidが所有するゴミ箱。
      put_entry(as_root, "${base}/unknown-owner/.Trash-4242", "old", "${expired}")
      machine.succeed("chown -R 4242:4242 ${base}/unknown-owner/.Trash-4242")

      # 起点と違うデバイスの中にあるゴミ箱。
      machine.succeed(
          f"{as_user} mkdir -p ${base}/other-device",
          "mount -t tmpfs tmpfs ${base}/other-device",
          "chown ${user} ${base}/other-device",
      )
      put_entry(as_user, "${base}/other-device/.Trash-1000", "old", "${expired}")

      machine.succeed("systemctl start trash-empty-stray.service")

      machine.succeed(
          "test ! -e ${base}/expired/deep/.Trash-1000",
          "test -e ${base}/fresh/.Trash-1000/files/new",
          "test -e ${base}/fresh/.Trash-1000/info/new.trashinfo",
          "test ! -e ${base}/mismatch/.Trash-0",
          "test ! -e ${base}/root-owned/.Trash-0",
          "test -e ${victim}/file",
          "test -e ${victim}/sub/file",
          "test -e ${base}/undeletable/.Trash-1000/files/old/kept",
          # 親はrootの所有なので、空になったゴミ箱自体は残る。エントリが消えたことだけを見る。
          "test ! -e ${base}/unknown-owner/.Trash-4242/files/old",
          "test ! -e ${base}/unknown-owner/.Trash-4242/info/old.trashinfo",
          "test -e ${base}/other-device/.Trash-1000/files/old",
          "test -e ${base}/other-device/.Trash-1000/info/old.trashinfo",
      )
    '';
}
