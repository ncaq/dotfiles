# ランナのVMのストアの状態を作り直すサービス(`module.nix`)を確認します。
# ここが失敗するとVMが起動できなくなります。
# 権限の絞り込みが強すぎても、消すものや写すものがずれても、評価とブートは通ったままです。
#
# systemd-nspawnのコンテナの中で`module.nix`の実際のユニットを、その権限の絞り込みのまま動かして確かめます。
# ホストの構成には依らないので、ホストをブートするテストではなくここに置いています。
# 実機のVMのユニットがこのサービスを連れて起動することは、ホストをブートするテストで見ています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# 元のデータベースは、テストが作ったWALモードのSQLiteのデータベースを使います。
# 以下を見ます。
#
# - 他のユーザが所有するディレクトリの中の、前の書き込み用の層のイメージを消すこと
# - データベースの写しが壊れていない形で置かれ、元の中身を持っていること
# - もう一度動かすと、前の写しが捨てられて、今の中身に取り直されること
{ localLib, testers }:
let
  vmName = "runner";
  vmUser = "vm-owner";
  nixDbDir = "/var/lib/test-nix-db";
  imageDir = "/var/lib/test-vm";
  overlayImage = "${imageDir}/nix-store-overlay.img";
  # モジュールが決める名前を、モジュールの値から引かずに直に書きます。
  # VMの側が写しを読む場所なので、名前が変わったことに気付けるようにします。
  storeDatabase = "/var/cache/${vmName}-store/db.sqlite";
in
testers.runNixOSTest {
  name = "github-runner-store";

  node.specialArgs.hardening = localLib.hardening;

  containers.machine =
    { pkgs, ... }:
    {
      imports = [ ./module.nix ];
      services.github-runner-store = {
        inherit nixDbDir;
        vms.${vmName} = { inherit overlayImage; };
      };
      users = {
        users.${vmUser} = {
          isSystemUser = true;
          group = vmUser;
        };
        groups.${vmUser} = { };
      };
      environment.systemPackages = [ pkgs.sqlite ];
    };

  testScript = # python
    ''
      def rows():
          return machine.succeed("sqlite3 ${storeDatabase} 'SELECT id FROM paths ORDER BY id'")

      machine.wait_for_unit("multi-user.target")

      machine.succeed(
          "mkdir -p ${nixDbDir}",
          "sqlite3 ${nixDbDir}/db.sqlite"
          " 'PRAGMA journal_mode=WAL; CREATE TABLE paths (id INTEGER); INSERT INTO paths VALUES (1);'",
          # イメージとその親のディレクトリは、VMを動かすユーザだけが触れる形にします。
          "install --directory --owner=${vmUser} --group=${vmUser} --mode=700 ${imageDir}",
          "runuser -u ${vmUser} -- touch ${overlayImage}",
      )

      with subtest("イメージを消して写しを置く"):
          machine.succeed("systemctl start ${vmName}-store.service")
          machine.fail("test -e ${overlayImage}")
          integrity = machine.succeed("sqlite3 ${storeDatabase} 'PRAGMA integrity_check'")
          assert integrity.strip() == "ok", integrity
          assert rows() == "1\n", rows()

      with subtest("もう一度動かすと取り直す"):
          machine.succeed(
              "sqlite3 ${nixDbDir}/db.sqlite 'INSERT INTO paths VALUES (2);'",
              "runuser -u ${vmUser} -- touch ${overlayImage}",
              "systemctl start ${vmName}-store.service",
          )
          machine.fail("test -e ${overlayImage}")
          assert rows() == "1\n2\n", rows()
    '';
}
