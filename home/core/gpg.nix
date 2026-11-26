{
  lib,
  pkgs,
  config,
  isTermux,
  osConfig ? null,
  ...
}:
let
  inherit (lib.hm.dag) entryBetween;
  keyConfig = import ../../key;
  # NixOSホストではnixos/core/gpg-vault.nixのgpg-vaultユーザが秘密鍵を保持し、
  # ncaq側ではgpg-agentを起動せずソケットだけをvaultに向けます。
  # コーディングエージェントなどによる秘密鍵ファイルのうっかり流出防止です。
  useVault = osConfig != null;
in
{
  # vaultのagentへ向けるクライアント側の設定は、vaultの本体と同じくパッケージの隣にある。
  imports = [ ../../pkgs/gpg-vault/home-module.nix ];

  config = lib.mkMerge [
    {
      # 共通設定
      programs.gpg = {
        enable = true;
        publicKeys = [
          {
            trust = "ultimate";
            source = keyConfig.publicKeyFile;
          }
        ];
      };
      home = {
        # `use-keyboxd`を有効化しないために空の`common.conf`を配置します。
        # 有効化するとkeyboxdデーモンが`pubring.db`のロックを抱え続けるため、
        # root権限で動く`sops-install-secrets`がユーザのGPG keyringを参照する際に、
        # ロック競合で復号化に失敗します。
        # `gpg.conf`を弄っても効かない(keyboxd設定は`common.conf`を見る)ため、
        # `programs.gpg.settings`ではなく直接ファイルを配置しています。
        file.".gnupg/common.conf".text = "";
        packages = with pkgs; [
          # 最終復旧手段として印刷するためのパッケージ。
          paperkey
        ];
      };
    }
    (lib.mkIf (!useVault) {
      # 非gracefulなシャットダウン(WSL終了など)でgpg-agentのsentinel lockが残留し、
      # importGpgKeysでgpg-agentに接続できなくなることがあります。
      # importGpgKeysの前にstaleなロックファイルを削除して回避します。
      # sentinel lockはgpgがagentを自動起動する時に作るものです。
      # vaultを使う環境は`no-autostart`で自動起動しないので、ロックが作られません。
      home.activation.cleanGpgStaleLocks = entryBetween [ "importGpgKeys" ] [ "createGpgHomedir" ] ''
        $DRY_RUN_CMD ${lib.getExe' pkgs.coreutils "rm"} -f \
          "${config.programs.gpg.homedir}/gnupg_spawn_agent_sentinel.lock"
      '';
    })
    {
      # NixOS環境: 秘密鍵はgpg-vaultユーザのagentが保持するため、
      # ncaq側ではgpg-agentを起動しません。
      services.gpg-vault.enable = !isTermux && useVault;
    }
    (lib.mkIf (!isTermux && !useVault) {
      # standalone home-manager環境: systemdサービスでgpg-agentを管理
      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
        pinentry.package = pkgs.pinentry-qt;
        sshKeys = [ keyConfig.sshKeygrip ];
      };
      home.packages = with pkgs; [
        # `pinentry-gnome3`はモーダルでウィンドウを固定するのでパスワードマネージャが使いづらいため、
        # こちらを優先して使っていきます。
        # `pinentry-curses`は`pinentry-qt`パッケージに含まれています。
        pinentry-qt
      ];
      # gpg-agentのssh-agentエミュレーションソケットをsystemdユーザセッション全体に伝える。
      # gpg-agentのSSH_AUTH_SOCK設定はインタラクティブなシェル初期化でしか行われないため、
      # GUIアプリやsystemdサービス(`emacs.service`など)には届かない。
      # その結果magitのssh経由のpullなどが失敗していた。
      # `environment.d`経由で設定すればsystemdユーザマネージャ配下の全プロセスに伝播する。
      # `$XDG_RUNTIME_DIR`は`environment.d`が展開するのでUIDのハードコードは不要。
      # デフォルトのgpg homedirを使う限りソケットパスは、
      # `$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh`で固定。
      systemd.user.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";
    })
    (lib.mkIf isTermux {
      # Termux環境: 単一ユーザ環境で鍵の隔離は不可能なため従来構成。
      # systemdが使えないためシェル初期化でgpg-agentを起動
      programs.zsh.initContent = ''
        # gpg-agentをSSHサポート付きで起動
        export GPG_TTY=$(tty)
        gpgconf --launch gpg-agent
        export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
      '';
      home = {
        file = {
          ".gnupg/gpg-agent.conf".text = ''
            enable-ssh-support
            pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
          '';
          ".gnupg/sshcontrol".text = ''
            # SSH認証に使用するGPGサブキーのkeygrip
            ${keyConfig.sshKeygrip}
          '';
        };
        # Termux環境ではsystemdによるGPGデーモンのライフサイクル管理がないため、
        # keyboxdのdotlockファイルが残留しsops-nixの復号化を妨げることがあります。
        # importGpgKeysの前にkeyboxdをkillしてpublic-keys.d/を削除し、
        # stale lockのない状態で鍵を再インポートします。
        activation.cleanGpgKeyboxd = entryBetween [ "importGpgKeys" ] [ "createGpgHomedir" ] ''
          $DRY_RUN_CMD ${lib.getExe' config.programs.gpg.package "gpgconf"} --kill keyboxd 2>/dev/null || true
          $DRY_RUN_CMD ${lib.getExe' pkgs.coreutils "rm"} -rf \
            "${config.programs.gpg.homedir}/public-keys.d/"
        '';
      };
    })
  ];
}
