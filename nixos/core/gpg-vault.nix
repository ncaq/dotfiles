/**
  GPG秘密鍵を通常ユーザから隔離するための専用ユーザとgpg-agentサービス。

  コーディングエージェントなどが通常ユーザ権限でディレクトリを一括アップロードしても、
  秘密鍵ファイル自体は流出しないようにする「うっかり防止」の仕組みです。

  GnuPGは設計上、
  gpgクライアントは秘密鍵ファイルを直接読まず、
  秘密鍵操作は全てgpg-agentにソケット経由で委譲します。
  この性質を利用して、
  秘密鍵の実体はgpg-vaultユーザのGNUPGHOME(mode 700)に置き、
  gpg-agentをgpg-vaultユーザで動かし、
  ソケットだけをgpg-vaultグループ経由で通常ユーザに公開します。

  通常ユーザ側のクライアント設定はhome/core/gpg.nixにあります。

  厳密なアクセス制御ではありません:
  通常ユーザはソケット経由で署名・復号・SSH認証・鍵のエクスポートを引き続き利用できます。
  防げるのはうっかりアップロードさせるミスだけです。
  悪意は防げません。
*/
{
  pkgs,
  username,
  ...
}:
let
  keyConfig = import ../../key;
  vaultHome = "/var/lib/gpg-vault";
  gnupgHome = "${vaultHome}/.gnupg";
  socketDir = "/run/gpg-vault";
in
{
  users = {
    users = {
      gpg-vault = {
        isSystemUser = true;
        group = "gpg-vault";
        home = vaultHome;
        description = "GPG secret key vault";
      };
      # ソケットへの接続はgpg-vaultグループで制限します。
      ${username}.extraGroups = [ "gpg-vault" ];
    };
    groups.gpg-vault = { };
  };

  systemd.services = {
    gpg-vault-agent = {
      description = "gpg-agent holding secret keys isolated from normal users";
      wantedBy = [ "multi-user.target" ];
      # GNUPGHOMEを毎回起動時に整備します。
      # 全て冪等な操作です。
      # ExecStartPreは`User=`で指定したgpg-vaultユーザで実行されます。
      preStart = ''
        umask 077
        mkdir -p "${gnupgHome}/private-keys-v1.d"

        # keyboxdを有効化しないための空のcommon.conf。
        # 理由はhome/core/gpg.nixのncaq側common.confと同じです。
        : > "${gnupgHome}/common.conf"

        # パスフレーズなし運用なのでpinentryが実際に呼ばれることはありませんが、
        # 設定として有効なパスは必要です。
        # allow-loopback-pinentryは鍵更新時にncaq側から、
        # `--pinentry-mode loopback`でパスフレーズ操作をするために必要です。
        # pinentryはユーザ境界を跨いでncaqの端末を開けないためloopbackを使います。
        {
          echo "enable-ssh-support"
          echo "allow-loopback-pinentry"
          echo "pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses"
        } > "${gnupgHome}/gpg-agent.conf"

        # SSH認証に使用するGPGサブキーのkeygrip。
        echo "${keyConfig.sshKeygrip}" > "${gnupgHome}/sshcontrol"

        # gpg-vaultはシステムユーザで/run/user/<uid>を持たないため、
        # 何もしないとソケットはGNUPGHOME直下に作られ、
        # mode 700のディレクトリ内なので通常ユーザから届かなくなります。
        # Assuanソケットリダイレクトで共有ディレクトリにソケットを作らせます。
        printf '%%Assuan%%\nsocket=%s\n' "${socketDir}/S.gpg-agent" \
          > "${gnupgHome}/S.gpg-agent"
        printf '%%Assuan%%\nsocket=%s\n' "${socketDir}/S.gpg-agent.ssh" \
          > "${gnupgHome}/S.gpg-agent.ssh"

        # rootで動くsops-install-secretsがこのGNUPGHOMEで復号する際に、
        # 鍵IDを解決できるよう公開鍵をvault側のpubringにも取り込みます。
        ${pkgs.gnupg}/bin/gpg --batch --no-autostart --quiet --import ${keyConfig.publicKeyFile}
        echo "${keyConfig.fingerprint}:6:" | \
          ${pkgs.gnupg}/bin/gpg --batch --no-autostart --quiet --import-ownertrust
      '';
      serviceConfig = {
        User = "gpg-vault";
        Group = "gpg-vault";
        # gpg-agentはソケットを作り終えてからforkするため、
        # forkingなら起動完了時点でソケットが利用可能です。
        Type = "forking";
        ExecStart = "${pkgs.gnupg}/bin/gpg-agent --daemon";
        # ソケットのパーミッションはumaskに依存するため、
        # グループ書き込み(=接続)可能に揃えます。
        ExecStartPost = "${pkgs.coreutils}/bin/chmod 0660 ${socketDir}/S.gpg-agent ${socketDir}/S.gpg-agent.ssh";
        Restart = "on-failure";
        Environment = [ "GNUPGHOME=${gnupgHome}" ];
        UMask = "0007";
        RuntimeDirectory = "gpg-vault";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "gpg-vault";
        StateDirectoryMode = "0700";
        # ハードニング。
        # 秘密鍵を扱うプロセスなので、
        # 不要な場所を見せず不要な特権と通信経路を断ちます。
        CapabilityBoundingSet = [ ];
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        # gpg-agentのソケットはUNIXドメインのみでネットワーク通信は不要です。
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        SystemCallFilter = [ "@system-service" ];
      };
    };

    # sops-install-secretsはvault agent経由で復号するため順序を保証します。
    # agentが未起動だとgpgのautostartがリダイレクト先の、
    # 存在しない${socketDir}にソケットを作ろうとして失敗します。
    sops-install-secrets = {
      after = [ "gpg-vault-agent.service" ];
      wants = [ "gpg-vault-agent.service" ];
    };

    # home-manager activationのimportGpgKeysなどはgpg-agentに接続するため、
    # vault agentの起動を待ちます。
    "home-manager-${username}" = {
      after = [ "gpg-vault-agent.service" ];
      wants = [ "gpg-vault-agent.service" ]; # 失敗してもなるべく起動してほしいので弱い依存。
    };
  };
}
