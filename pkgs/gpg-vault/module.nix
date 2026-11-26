/**
  GPG秘密鍵を通常ユーザから隔離するための専用ユーザとgpg-agentサービスのNixOSモジュール。

  コーディングエージェントなどが通常ユーザ権限でディレクトリを一括アップロードしても、
  秘密鍵ファイル自体は流出しないようにする「うっかり防止」の仕組みです。

  GnuPGは設計上、
  gpgクライアントは秘密鍵ファイルを直接読まず、
  秘密鍵操作は全てgpg-agentにソケット経由で委譲します。
  この性質を利用して、
  秘密鍵の実体はgpg-vaultユーザのGNUPGHOME(mode 700)に置き、
  gpg-agentをgpg-vaultユーザで動かし、
  ソケットだけをgpg-vaultグループ経由で通常ユーザに公開します。

  GNUPGHOMEに置く静的な設定のうち鍵に依らないものはパッケージ(`package.nix`)が持っていて、
  通常ユーザ側のクライアント設定は`home-module.nix`にあります。
  使う側(`nixos/core/gpg-vault.nix`)は、どの鍵を誰に使わせるかだけを決めます。
  テスト(`nixos-test.nix`)もこのモジュールだけを読むので、ホストの構成に依存しません。

  厳密なアクセス制御ではありません:
  通常ユーザはソケット経由で署名・復号・SSH認証・鍵のエクスポートを引き続き利用できます。
  防げるのはうっかりアップロードさせるミスだけです。
  悪意は防げません。
*/
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.gpg-vault;
  hardening = import ../../lib/systemd-hardening.nix;
  # クライアント側(home-managerの`programs.gpg`)と同じ既定のgnupgに揃えるため、
  # `pkgs.gnupg`を直接参照せずNixOSの`programs.gnupg.package`を経由する。
  gnupg = config.programs.gnupg.package;

  vaultUser = "gpg-vault";
  # `StateDirectory`と`RuntimeDirectory`に渡す名前。
  directoryName = "gpg-vault";
  vaultHome = "/var/lib/${directoryName}";
  agentService = "gpg-vault-agent";

  # GNUPGHOMEに置く静的な設定のうち、どの鍵を使うかに依らないもの。
  gnupgHomeFiles = pkgs.gpg-vault;
  inherit (gnupgHomeFiles) socketDir;

  # `trusted-key`で主鍵をultimate信頼として宣言します。
  # これによりpreStartでの`--import-ownertrust`によるgpg起動が不要になります。
  gpgConf = pkgs.writeText "gpg-vault-gpg.conf" ''
    trusted-key ${cfg.fingerprint}
  '';

  sshcontrolFile = pkgs.writeText "gpg-vault-sshcontrol" ''
    ${cfg.sshKeygrip}
  '';

  # v4のフィンガープリントとkeygripの形。どちらもSHA-1の160bitを、空白の無い大文字の16進数で書く。
  # 鍵の実在までは確かめられないが、空白入りの表記や鍵IDを渡す取り違えは評価の時に落とせる。
  hex40 = lib.types.strMatching "[0-9A-F]{40}";
in
{
  options.services.gpg-vault = {
    enable = lib.mkEnableOption "GPG秘密鍵を通常ユーザから隔離するgpg-agent";
    fingerprint = lib.mkOption {
      type = hex40;
      description = "ultimate信頼として宣言する主鍵のフィンガープリント。";
    };
    sshKeygrip = lib.mkOption {
      type = hex40;
      description = "SSH認証に使用するGPGサブキーのkeygrip。";
    };
    publicKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "vault側のpubringへ取り込む公開鍵のファイル。";
    };
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        agentのソケットへ接続できるようにするユーザ。
        このモジュールは作らないので、使う側で定義しておく。
      '';
    };
    clientUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "sops-install-secrets.service" ];
      description = ''
        agentへ接続するユニット。
        agentをこれらより前に起動して、これらの起動でagentも引き込む。
        失敗してもなるべく起動してほしいので弱い依存にする。
      '';
    };
    gnupgHome = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = "${vaultHome}/.gnupg";
      description = ''
        秘密鍵を持つgpg-vaultユーザのGNUPGHOME。
        rootで動くsops-install-secretsのように、vaultの鍵で復号するものが参照する。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # `RuntimeDirectory`が作るのは`/run/${directoryName}`で、パッケージのリダイレクト先と別々に決まっている。
        assertion = socketDir == "/run/${directoryName}";
        message = "gpg-vaultのパッケージの`socketDir`がユニットの`RuntimeDirectory`と食い違っています。";
      }
    ];

    users = {
      users = {
        ${vaultUser} = {
          isSystemUser = true;
          group = vaultUser;
          home = vaultHome;
          description = "GPG secret key vault";
        };
      }
      # ソケットへの接続はgpg-vaultグループで制限します。
      // lib.genAttrs cfg.users (_: {
        extraGroups = [ vaultUser ];
      });
      groups.${vaultUser} = { };
    };

    systemd = {
      # GNUPGHOMEの静的な内容は宣言的に配置します。
      tmpfiles.settings."50-gpg-vault" =
        let
          vaultDir = {
            user = vaultUser;
            group = vaultUser;
            mode = "0700";
          };
        in
        {
          # ディレクトリは実体として作ります。
          ${vaultHome}.d = vaultDir;
          ${cfg.gnupgHome}.d = vaultDir;
          "${cfg.gnupgHome}/private-keys-v1.d".d = vaultDir;
          # 空のファイルを実体として作ります。
          # 空にするのはkeyboxdを有効化しないためです。
          # 有効化するとkeyboxdデーモンが`pubring.db`のロックを抱え続けるため、
          # rootで動くsops-install-secretsがこのGNUPGHOMEを参照する際に、
          # ロック競合で復号化に失敗します。
          "${cfg.gnupgHome}/common.conf".f = {
            user = vaultUser;
            group = vaultUser;
            mode = "0600";
          };
          # 内容を持つ設定ファイルはstoreへのsymlinkにします。
          "${cfg.gnupgHome}/gpg.conf"."L+".argument = "${gpgConf}";
          "${cfg.gnupgHome}/sshcontrol"."L+".argument = "${sshcontrolFile}";
        }
        // lib.genAttrs' [ "gpg-agent.conf" "S.gpg-agent" "S.gpg-agent.ssh" ] (
          name:
          lib.nameValuePair "${cfg.gnupgHome}/${name}" {
            "L+".argument = "${gnupgHomeFiles}/${name}";
          }
        );

      services.${agentService} = {
        description = "gpg-agent holding secret keys isolated from normal users";
        # sops-install-secretsは`sysinit.target`より前に走り、
        # このサービスの後に順序付けされています。
        # 既定の依存関係(`After=basic.target`など)が残っていると、
        # 順序が循環してsystemdがsops-install-secretsのジョブを削除してしまい、
        # シークレットが展開されなくなります。
        unitConfig.DefaultDependencies = false;
        wantedBy = [
          # 既定の依存関係を外した代わりにsysinit段階で起動します。
          # 接続するユニットからの引き込みに頼らず自身も`sysinit.target`から引き込みます。
          "sysinit.target"
        ]
        # agentが未起動だとgpgのautostartがリダイレクト先の、
        # 存在しない`socketDir`にソケットを作ろうとして失敗します。
        ++ cfg.clientUnits;
        after = [
          "local-fs.target"
          # GNUPGHOMEの設定ファイルはtmpfilesで配置されるためその後に起動します。
          "systemd-tmpfiles-setup.service"
          # 秘密鍵を扱うプロセスなので、
          # 保存済みエントロピーの投入を待ちます。
          "systemd-random-seed.service"
          # 同じ理由で、
          # sysctlによるカーネル側の保護の適用も待ちます。
          "systemd-sysctl.service"
        ];
        before = [
          # ユーザセッションがソケットを参照する前に起動を完了させます。
          "sysinit.target"
          # 既定の依存関係を外すと停止時の`shutdown.target`との衝突と順序も失われるため、
          # シャットダウン時に確実に停止するよう下の`conflicts`と合わせて明示的に復元します。
          "shutdown.target"
        ]
        ++ cfg.clientUnits;
        conflicts = [ "shutdown.target" ];
        # agentが読む設定はtmpfilesで配置されていてunit定義に含まれないため、
        # 内容が変わってもそのままではサービスが再起動されません。
        # 設定変更時に確実に再起動させます。
        restartTriggers = [
          gnupgHomeFiles
          sshcontrolFile
        ];
        # rootで動くsops-install-secretsがこのGNUPGHOMEで復号する際に、
        # 鍵IDを解決できるよう公開鍵をvault側のpubringにも取り込みます。
        # importは冪等ですが手続き的な処理なので、
        # ここだけpreStartに残しています。
        # ExecStartPreは`User=`で指定したgpg-vaultユーザで実行されます。
        preStart = ''
          umask 077
          ${lib.getExe' gnupg "gpg"} --batch --no-autostart --quiet --import ${cfg.publicKeyFile}
        '';
        serviceConfig =
          # 秘密鍵を扱うプロセスなので、
          # 不要な場所を見せず不要な特権と通信経路を断ちます。
          # gpg-agentのソケットはUNIXドメインのみでネットワーク通信は不要です。
          hardening.unixSocket // {
            User = vaultUser;
            Group = vaultUser;
            # gpg-agentはソケットを作り終えてからforkするため、
            # forkingなら起動完了時点でソケットが利用可能です。
            Type = "forking";
            ExecStart = "${lib.getExe' gnupg "gpg-agent"} --daemon";
            # gpg-agentはumaskに関係なくソケットを0700で生成することを検証済みなので、
            # このchmodによるグループ書き込み(=接続)許可は必須です。
            # ExecStartPostの完了までunitはstartedにならないため、
            # After=で順序付けされた依存サービスが0700の窓に当たることはありません。
            ExecStartPost = "${pkgs.coreutils}/bin/chmod 0660 ${socketDir}/S.gpg-agent ${socketDir}/S.gpg-agent.ssh";
            Restart = "on-failure";
            Environment = [ "GNUPGHOME=${cfg.gnupgHome}" ];
            UMask = "0007";
            # `socketDir`の実体です。
            RuntimeDirectory = directoryName;
            RuntimeDirectoryMode = "0750";
            # `vaultHome`の実体です。
            StateDirectory = directoryName;
            StateDirectoryMode = "0700";
          };
      };
    };
  };
}
