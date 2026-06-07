{
  pkgs,
  config,
  lib,
  isTermux,
  ...
}:
let
  inherit (lib.hm.dag) entryBetween;
  keyConfig = import ../../key;
in
lib.mkMerge [
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
    # 非gracefulなシャットダウン(WSL終了など)でgpg-agentのsentinel lockが残留し、
    # importGpgKeysでgpg-agentに接続できなくなることがあります。
    # importGpgKeysの前にstaleなロックファイルを削除して回避します。
    home.activation.cleanGpgStaleLocks = entryBetween [ "importGpgKeys" ] [ "createGpgHomedir" ] ''
      $DRY_RUN_CMD ${pkgs.trash-cli}/bin/trash \
        "${config.programs.gpg.homedir}/gnupg_spawn_agent_sentinel.lock" \
        2>/dev/null || true
    '';
    home.packages = with pkgs; [ paperkey ];
  }
  (
    if !isTermux then
      {
        # 通常環境: systemdサービスでgpg-agentを管理
        services.gpg-agent = {
          enable = true;
          enableSshSupport = true;
          pinentry.package = pkgs.pinentry-qt; # pinentry-gnome3はモーダルでパスワードマネージャが使いづらい。
          sshKeys = [ keyConfig.sshKeygrip ];
        };
        home.packages = with pkgs; [
          pinentry-qt
        ];
      }
    else
      {
        # Termux環境: systemdが使えないためシェル初期化でgpg-agentを起動
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
            $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpgconf --kill keyboxd 2>/dev/null || true
            $DRY_RUN_CMD ${pkgs.trash-cli}/bin/trash \
              "${config.home.homeDirectory}/.gnupg/public-keys.d/" \
              2>/dev/null || true
          '';
          packages = with pkgs; [
            pinentry-curses
          ];
        };
      }
  )
]
