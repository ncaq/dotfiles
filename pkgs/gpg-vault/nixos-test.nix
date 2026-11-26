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
# - SSHのソケットも、グループのユーザにだけ応答すること
# - agentを再起動しても、ソケットが同じ場所に同じ権限でできること
# - `clientUnits`に入れたユニットを起動すると、agentが引き込まれて先に起動すること
#
# クライアント側の`home-module.nix`は、グループに入ったユーザの構成としてhome-managerで評価します。
# そこから出てきたユーザのtmpfilesの規則と`gpg.conf`を、そのユーザへそのまま適用します。
# そのユーザのgpgは、`home-module.nix`が決めたリンクと設定だけでagentへ繋ぐので、
# リンクの先がパッケージの`socketDir`からずれると、署名が通らなくなります。
#
# home-managerの有効化そのものは動かしません。
# 有効化はnix-daemonを必要としますが、コンテナの中のnix-daemonはストアの所有者を変えられずに失敗します。
# 生成されたファイルを置くところだけを、テストが代わりに行います。
#
# グループに入っていないユーザはhome-managerを使わず、リンクをテストが手で置きます。
{ homeManagerConfiguration, testers }:
let
  # vault側のpubringへ取り込ませる公開鍵のユーザID。
  importedUserId = "imported@example.com";
  # グループに入れるユーザと、入れないユーザ。
  member = "alice";
  outsider = "bob";
  # `/run/user/<uid>`を指すので、グループに入れるユーザのUIDを決めておきます。
  memberUid = 1000;
  # `home-module.nix`から出てきたファイルを置く、`/etc`の下のディレクトリ。
  homeFilesDir = "gpg-vault-home";
  # `clientUnits`に入れる、agentへ接続するユニット。
  clientService = "vault-client";
in
testers.runNixOSTest {
  name = "gpg-vault";

  containers.machine =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    {
      imports = [ ./module.nix ];
      # `home-module.nix`を有効にした構成から出てきたファイルを、テストから読める場所へ置きます。
      environment.etc =
        let
          home =
            (homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./home-module.nix
                {
                  home = {
                    username = member;
                    homeDirectory = config.users.users.${member}.home;
                    inherit (config.system) stateVersion;
                  };
                  programs.gpg.enable = true;
                  services.gpg-vault.enable = true;
                }
              ];
            }).config;
        in
        {
          "${homeFilesDir}/user-tmpfiles.conf".source =
            home.xdg.configFile."user-tmpfiles.d/home-manager.conf".source;
          "${homeFilesDir}/gpg.conf".source = home.home.file."${home.programs.gpg.homedir}/gpg.conf".source;
          "${homeFilesDir}/environment.conf".source =
            home.xdg.configFile."environment.d/10-home-manager.conf".source;
        };
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
        clientUnits = [ "${clientService}.service" ];
      };
      # agentへ接続するユニットの代わり。
      # sops-install-secretsと同じく、rootがvaultのGNUPGHOMEを指してagentへ繋ぎます。
      # ブートでは起動せず、テストが手で起動します。
      systemd.services.${clientService}.serviceConfig = {
        Type = "oneshot";
        Environment = [ "GNUPGHOME=${config.services.gpg-vault.gnupgHome}" ];
        ExecStart = pkgs.writeShellScript "vault-client" ''
          ${lib.getExe' pkgs.gnupg "gpg-connect-agent"} --no-autostart "getinfo version" /bye \
            | ${lib.getExe pkgs.gnugrep} --quiet "^D "
        '';
      };
      users.users = {
        ${member} = {
          isNormalUser = true;
          uid = memberUid;
          # モジュールが`users`のユーザに求めます。
          linger = true;
        };
        ${outsider}.isNormalUser = true;
      };
      environment.systemPackages = [
        pkgs.gnupg
        # SSHのソケットへ`ssh-add`で繋ぎます。
        pkgs.openssh
      ];
    };

  testScript =
    { containers, ... }:
    let
      # 場所と名前はここに直に書かず、モジュールとパッケージの値から引きます。
      # 直に書くと、モジュールの側で場所を変えた時に、テストだけが古い場所を見続けます。
      inherit (containers.machine.services.gpg-vault) gnupgHome;
      inherit (containers.machine.nixpkgs.pkgs.gpg-vault)
        agentSocketName
        socketDir
        socketNames
        sshSocketName
        ;
    in
    # python
    ''
      socket_dir = "${socketDir}"
      socket_names = ${builtins.toJSON socketNames}
      agent_socket_name = "${agentSocketName}"
      ssh_socket = "${socketDir}/${sshSocketName}"
      # グループに入ったユーザの`XDG_RUNTIME_DIR`。
      runtime_dir = "/run/user/${toString memberUid}"
      vault_home = "${gnupgHome}"
      vault_parent = "${dirOf gnupgHome}"


      def as_user(user, command):
          return f"runuser -u {user} -- sh -c 'cd && {command}'"


      def point_to_vault(user):
          # home-managerを使わないユーザのgpgを、手でagentのソケットへ向けます。
          # gpgがソケットを探す場所は、`/run/user/<uid>`があるかで変わるので、gpg自身に聞きます。
          machine.succeed(as_user(
              user,
              "mkdir -m 700 -p .gnupg"
              " && echo no-autostart > .gnupg/gpg.conf"
              " && dir=$(gpgconf --list-dirs socketdir)"
              " && mkdir -m 700 -p $dir"
              f" && ln -sf {socket_dir}/{agent_socket_name} $dir/{agent_socket_name}"
          ))


      def check_socket_permissions():
          for name in socket_names:
              stat = machine.succeed(f"stat -c '%U %G %a' {socket_dir}/{name}").strip()
              assert stat == "gpg-vault gpg-vault 660", f"{name}: {stat}"
          stat = machine.succeed(f"stat -c '%U %G %a' {socket_dir}").strip()
          assert stat == "gpg-vault gpg-vault 750", stat


      def ssh_add_status(user):
          # `ssh-add -l`は、agentに繋がって鍵が無ければ1、繋がらなければ2で終わります。
          status, _ = machine.execute(as_user(user, f"SSH_AUTH_SOCK={ssh_socket} ssh-add -l"))
          return status


      # `gpg-connect-agent`は繋げなくても0で終わるので、agentの応答があるかで見ます。
      ask_agent = "gpg-connect-agent --no-autostart \"getinfo version\" /bye | grep --quiet \"^D \""
      sign = "echo test | gpg --batch --sign --armor | gpg --batch --verify"

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("gpg-vault-agent.service")
      # lingerのユーザの`/run/user/<uid>`ができるのを待ちます。
      machine.wait_until_succeeds(f"test -d {runtime_dir}")

      with subtest("公開鍵をvault側のpubringへ取り込む"):
          machine.succeed(
              f"runuser -u gpg-vault -- env GNUPGHOME={vault_home}"
              " gpg --batch --no-autostart --list-keys ${importedUserId}"
          )

      with subtest("ソケットはgpg-vaultグループにだけ開いている"):
          check_socket_permissions()

      with subtest("home-module.nixの規則がソケットへのリンクを置く"):
          home_files = "/etc/${homeFilesDir}"
          # home-managerの有効化の代わりに、生成された`gpg.conf`とユーザのtmpfilesの規則を適用します。
          machine.succeed(as_user(
              "${member}",
              "mkdir -m 700 -p .gnupg"
              f" && ln -sf {home_files}/gpg.conf .gnupg/gpg.conf"
              f" && XDG_RUNTIME_DIR={runtime_dir} systemd-tmpfiles --user --create {home_files}/user-tmpfiles.conf"
          ))
          for name in socket_names:
              target = machine.succeed(f"readlink {runtime_dir}/gnupg/{name}").strip()
              assert target == f"{socket_dir}/{name}", f"{name}: {target}"
          # 鍵を持たないagentを自分で起動しないようにする設定です。
          machine.succeed(f"grep --line-regexp no-autostart {home_files}/gpg.conf")
          # ユーザのsystemdが起動の時に読む`environment.d`に出すファイルです。
          machine.succeed(
              f"grep --line-regexp --fixed-strings 'SSH_AUTH_SOCK={ssh_socket}'"
              f" {home_files}/environment.conf"
          )

      with subtest("グループのユーザはソケット経由で鍵を作って署名できる"):
          # このユーザのgpgは、上で適用した`home-module.nix`のリンクと設定だけでagentへ繋ぎます。
          machine.succeed(as_user(
              "${member}",
              "gpg --batch --pinentry-mode loopback --passphrase \"\""
              " --quick-generate-key test@example.com ed25519 sign never"
          ))
          machine.succeed(as_user("${member}", sign))

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
          machine.fail(as_user("${outsider}", ask_agent))
          # 繋げる側では同じコマンドが通るので、失敗の理由は権限です。
          machine.succeed(as_user("${member}", ask_agent))

      with subtest("SSHのソケットもグループのユーザにだけ応答する"):
          # sshcontrolのkeygripはダミーなので、繋がっても鍵は出ません。
          status = ssh_add_status("${member}")
          assert status == 1, f"${member}: {status}"
          status = ssh_add_status("${outsider}")
          assert status == 2, f"${outsider}: {status}"

      with subtest("agentを再起動してもソケットが同じ場所に同じ権限でできる"):
          # 設定を変えた時は`restartTriggers`で再起動されるので、実際にも通る経路です。
          # リダイレクトのファイルが残ることと、`ExecStartPost`のchmodが毎回効くことを見ます。
          machine.succeed("systemctl restart gpg-vault-agent.service")
          check_socket_permissions()
          machine.succeed(as_user("${member}", ask_agent))
          machine.succeed(as_user("${member}", sign))
          status = ssh_add_status("${member}")
          assert status == 1, f"${member}: {status}"

      with subtest("clientUnitsのユニットを起動すると、agentが先に起動する"):
          before = machine.succeed("systemctl show --property=Before --value gpg-vault-agent.service")
          assert "${clientService}.service" in before.split(), before
          # agentを止めておいて、接続するユニットだけを起動します。
          # agentが引き込まれないか、順序が付いていなければ、接続に失敗してユニットが失敗します。
          machine.succeed("systemctl stop gpg-vault-agent.service")
          machine.fail("systemctl is-active gpg-vault-agent.service")
          machine.succeed("systemctl start ${clientService}.service")
          machine.succeed("systemctl is-active gpg-vault-agent.service")
    '';
}
