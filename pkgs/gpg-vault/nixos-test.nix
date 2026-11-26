# 秘密鍵をgpg-vaultユーザへ隔離するagent(`module.nix`)を確認します。
# ソケットの権限やGNUPGHOMEの権限が緩んでも、評価とブートは通ったまま退行します。
# 逆にユニットの隔離を絞りすぎてagentが鍵を扱えなくなっても、起動だけは成功します。
#
# systemd-nspawnのコンテナの中で`module.nix`の実際のユニットを、その隔離のまま動かして確かめます。
# ホストの構成には依らないので、ホストをブートするテストではなくここに置いています。
# 実行するnix-daemonに要る設定は`nixos/core/nix-daemon.nix`に書いてあります。
#
# 鍵はテストの中で作ります。
# フィンガープリントとkeygripは評価の時に分からないので、モジュールへはダミーを渡します。
# 公開鍵のファイルだけは、取り込みが実際に通るように、ビルドの時に作った鍵のものを渡します。
#
# 以下を見ます。
#
# - agentが起動して、公開鍵がvault側のpubringへ取り込まれること
# - ソケットがgpg-vaultグループにだけ開いていること
# - グループに入ったユーザが、ソケット経由で鍵を作って署名できること
# - そのユーザからもvaultのGNUPGHOMEは読めず、自分の側に秘密鍵のファイルが無いこと
# - グループに入っていないユーザは、ソケットへ繋げないこと
#
# クライアント側の`home-module.nix`はhome-managerのモジュールなので、ここでは動かしません。
# 代わりに同じ形のソケットへのリンクを、ユーザのGNUPGHOMEへ手で置きます。
{ testers }:
let
  # vault側のpubringへ取り込ませる公開鍵のユーザID。
  importedUserId = "imported@example.com";
  # グループに入れるユーザと、入れないユーザ。
  member = "alice";
  outsider = "bob";
in
testers.runNixOSTest {
  name = "gpg-vault";

  containers.machine =
    { pkgs, ... }:
    {
      imports = [ ./module.nix ];
      services.gpg-vault = {
        enable = true;
        fingerprint = "0000000000000000000000000000000000000000";
        sshKeygrip = "0000000000000000000000000000000000000000";
        # 秘密鍵は捨てて、公開鍵だけを取り出します。
        publicKeyFile =
          pkgs.runCommand "gpg-vault-test-public-key.asc" { nativeBuildInputs = [ pkgs.gnupg ]; }
            ''
              export GNUPGHOME=$(mktemp -d)
              gpg --batch --pinentry-mode loopback --passphrase "" \
                --quick-generate-key ${importedUserId} ed25519 sign never
              gpg --batch --export --armor ${importedUserId} > $out
              gpgconf --kill gpg-agent
            '';
        users = [ member ];
      };
      users.users = {
        ${member} = {
          isNormalUser = true;
          # モジュールが`users`のユーザに求めます。
          linger = true;
        };
        ${outsider}.isNormalUser = true;
      };
      environment.systemPackages = [ pkgs.gnupg ];
    };

  testScript =
    { containers, ... }:
    let
      # 場所と名前はここに直に書かず、モジュールとパッケージの値から引きます。
      # 直に書くと、モジュールの側で場所を変えた時に、テストだけが古い場所を見続けます。
      inherit (containers.machine.services.gpg-vault) gnupgHome;
      inherit (containers.machine.nixpkgs.pkgs.gpg-vault) socketDir socketNames;
    in
    # python
    ''
      socket_dir = "${socketDir}"
      socket_names = ${builtins.toJSON socketNames}
      vault_home = "${gnupgHome}"
      vault_parent = "${dirOf gnupgHome}"


      def as_user(user, command):
          return f"runuser -u {user} -- sh -c 'cd && {command}'"


      def point_to_vault(user):
          # gpgがソケットを探す場所は、`/run/user/<uid>`があるかで変わります。
          # lingerのユーザは`/run/user/<uid>/gnupg`で、無いユーザはGNUPGHOMEの直下です。
          # どちらでも合うように、gpg自身に場所を聞きます。
          machine.succeed(as_user(
              user,
              "mkdir -m 700 -p .gnupg"
              " && echo no-autostart > .gnupg/gpg.conf"
              " && dir=$(gpgconf --list-dirs socketdir)"
              " && mkdir -m 700 -p $dir"
              f" && ln -sf {socket_dir}/S.gpg-agent $dir/S.gpg-agent"
          ))


      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("gpg-vault-agent.service")
      # lingerのユーザの`/run/user/<uid>`ができてから、gpgにソケットの場所を聞きます。
      machine.wait_until_succeeds("test -d /run/user/$(id -u ${member})")

      with subtest("公開鍵をvault側のpubringへ取り込む"):
          machine.succeed(
              f"runuser -u gpg-vault -- env GNUPGHOME={vault_home}"
              " gpg --batch --no-autostart --list-keys ${importedUserId}"
          )

      with subtest("ソケットはgpg-vaultグループにだけ開いている"):
          for name in socket_names:
              stat = machine.succeed(f"stat -c '%U %G %a' {socket_dir}/{name}").strip()
              assert stat == "gpg-vault gpg-vault 660", stat
          stat = machine.succeed(f"stat -c '%U %G %a' {socket_dir}").strip()
          assert stat == "gpg-vault gpg-vault 750", stat

      with subtest("グループのユーザはソケット経由で鍵を作って署名できる"):
          point_to_vault("${member}")
          machine.succeed(as_user(
              "${member}",
              "gpg --batch --pinentry-mode loopback --passphrase \"\""
              " --quick-generate-key test@example.com ed25519 sign never"
          ))
          machine.succeed(as_user(
              "${member}",
              "echo test | gpg --batch --sign --armor | gpg --batch --verify"
          ))

      with subtest("秘密鍵のファイルはvaultの中にだけある"):
          machine.succeed(f"test -n \"$(ls {vault_home}/private-keys-v1.d)\"")
          machine.fail(as_user("${member}", f"ls {vault_home}"))
          machine.fail(as_user("${member}", f"ls {vault_parent}"))
          # 上の`ls`の失敗は、一番外のディレクトリが閉じているだけで成り立ちます。
          # 中のディレクトリも個別に閉じていることを、権限を直に見て確かめます。
          for path in [vault_parent, vault_home, f"{vault_home}/private-keys-v1.d"]:
              stat = machine.succeed(f"stat -c '%U %G %a' {path}").strip()
              assert stat == "gpg-vault gpg-vault 700", f"{path}: {stat}"
          machine.fail(as_user("${member}", "ls .gnupg/private-keys-v1.d/*.key"))

      with subtest("グループの外のユーザはソケットへ繋げない"):
          point_to_vault("${outsider}")
          # `gpg-connect-agent`は繋げなくても0で終わるので、agentの応答があるかで見ます。
          ask_agent = "gpg-connect-agent --no-autostart \"getinfo version\" /bye | grep --quiet \"^D \""
          machine.fail(as_user("${outsider}", ask_agent))
          # 繋げる側では同じコマンドが通るので、失敗の理由は権限です。
          machine.succeed(as_user("${member}", ask_agent))
    '';
}
