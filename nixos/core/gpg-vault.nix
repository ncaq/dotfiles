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

  # `trusted-key`で主鍵をultimate信頼として宣言します。
  # これによりpreStartでの`--import-ownertrust`によるgpg起動が不要になります。
  gpgConf = pkgs.writeText "gpg-vault-gpg.conf" ''
    trusted-key ${keyConfig.fingerprint}
  '';

  gpgAgentConf = pkgs.writeText "gpg-vault-gpg-agent.conf" ''
    enable-ssh-support
    # 鍵更新時にncaq側から`--pinentry-mode loopback`でパスフレーズ操作をするために必要です。
    # pinentryはユーザ境界を跨いでncaqの端末を開けないためloopbackを使います。
    allow-loopback-pinentry
    # パスフレーズなし運用なのでpinentryが実際に呼ばれることはありませんが、
    # 設定として有効なパスは必要です。
    pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
    # スマートカードは使わない運用なので、
    # 鍵操作時にscdaemonがカード探索のためにspawnされるのを止めます。
    disable-scdaemon
  '';

  # SSH認証に使用するGPGサブキーのkeygrip。
  sshcontrolFile = pkgs.writeText "gpg-vault-sshcontrol" ''
    ${keyConfig.sshKeygrip}
  '';

  # gpg-vaultはシステムユーザで/run/user/<uid>を持たないため、
  # 何もしないとソケットはGNUPGHOME直下に作られ、
  # mode 700のディレクトリ内なので通常ユーザから届かなくなります。
  # Assuanソケットリダイレクトで共有ディレクトリにソケットを作らせます。
  # gpg-agentはリダイレクトファイル自体は終了時に削除しない
  # (削除するのはリダイレクト先の実ソケットだけ)ことを検証済みなので、
  # storeへのsymlinkとして配置してもサービス再起動を跨いで機能します。
  socketRedirect =
    socketName:
    pkgs.writeText "gpg-vault-redirect-${socketName}" ''
      %Assuan%
      socket=${socketDir}/${socketName}
    '';
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

  # GNUPGHOMEの静的な内容は宣言的に配置します。
  # ディレクトリと空のcommon.confを実体として作り、
  # 内容を持つ設定ファイルはstoreへのsymlinkにします。
  # common.confを空にするのはkeyboxdを有効化しないためで、
  # 理由はhome/core/gpg.nixのncaq側common.confと同じです。
  systemd.tmpfiles.settings."50-gpg-vault" =
    let
      vaultDir = {
        user = "gpg-vault";
        group = "gpg-vault";
        mode = "0700";
      };
    in
    {
      ${vaultHome}.d = vaultDir;
      ${gnupgHome}.d = vaultDir;
      "${gnupgHome}/private-keys-v1.d".d = vaultDir;
      "${gnupgHome}/common.conf".f = {
        user = "gpg-vault";
        group = "gpg-vault";
        mode = "0600";
      };
      "${gnupgHome}/gpg.conf"."L+".argument = "${gpgConf}";
      "${gnupgHome}/gpg-agent.conf"."L+".argument = "${gpgAgentConf}";
      "${gnupgHome}/sshcontrol"."L+".argument = "${sshcontrolFile}";
      "${gnupgHome}/S.gpg-agent"."L+".argument = "${socketRedirect "S.gpg-agent"}";
      "${gnupgHome}/S.gpg-agent.ssh"."L+".argument = "${socketRedirect "S.gpg-agent.ssh"}";
    };

  systemd.services = {
    gpg-vault-agent = {
      description = "gpg-agent holding secret keys isolated from normal users";
      wantedBy = [ "multi-user.target" ];
      # agentが読む設定はtmpfilesで配置されていてunit定義に含まれないため、
      # 内容が変わってもそのままではサービスが再起動されません。
      # 設定変更時に確実に再起動させます。
      restartTriggers = [
        gpgAgentConf
        sshcontrolFile
        (socketRedirect "S.gpg-agent")
        (socketRedirect "S.gpg-agent.ssh")
      ];
      # rootで動くsops-install-secretsがこのGNUPGHOMEで復号する際に、
      # 鍵IDを解決できるよう公開鍵をvault側のpubringにも取り込みます。
      # importは冪等ですが手続き的な処理なので、
      # ここだけpreStartに残しています。
      # ExecStartPreは`User=`で指定したgpg-vaultユーザで実行されます。
      preStart = ''
        umask 077
        ${pkgs.gnupg}/bin/gpg --batch --no-autostart --quiet --import ${keyConfig.publicKeyFile}
      '';
      serviceConfig = {
        User = "gpg-vault";
        Group = "gpg-vault";
        # gpg-agentはソケットを作り終えてからforkするため、
        # forkingなら起動完了時点でソケットが利用可能です。
        Type = "forking";
        ExecStart = "${pkgs.gnupg}/bin/gpg-agent --daemon";
        # gpg-agentはumaskに関係なくソケットを0700で生成することを検証済みなので、
        # このchmodによるグループ書き込み(=接続)許可は必須です。
        # ExecStartPostの完了までunitはstartedにならないため、
        # After=で順序付けされた依存サービスが0700の窓に当たることはありません。
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
