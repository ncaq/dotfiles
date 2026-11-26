# gpg-vaultのagentを通常ユーザのgpgとsshから使うためのhome-managerモジュール。
#
# 秘密鍵は`module.nix`のgpg-vaultユーザのagentが保持するため、
# 通常ユーザ側ではgpg-agentを起動せずソケットだけをvaultに向けます。
# 使う側(`home/core/gpg.nix`)は、有効にするかどうかだけを決めます。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.gpg-vault;
  inherit (pkgs.gpg-vault) socketDir socketNames sshSocketName;
  sshSocket = "${socketDir}/${sshSocketName}";
in
{
  options.services.gpg-vault.enable = lib.mkEnableOption "gpg-vaultのagentをgpgとsshのagentとして使う設定";

  config = lib.mkIf cfg.enable {
    # ソケットが見つからない時にgpgが鍵を持たないagentを勝手にspawnすると、
    # 「秘密鍵が見つからない」という紛らわしいエラーになるため、
    # autostartを無効化してソケット不在を明示的なエラーにします。
    programs.gpg.settings.no-autostart = true;

    systemd.user = {
      # gpgクライアントは標準のソケットパス(`$XDG_RUNTIME_DIR/gnupg/`)を参照するため、
      # symlinkでvault agentのソケットへ誘導します。
      # `%t`はユーザtmpfilesでは`$XDG_RUNTIME_DIR`に展開されます。
      tmpfiles.rules = [
        "d %t/gnupg 0700 - -"
      ]
      ++ map (name: "L+ %t/gnupg/${name} - - - - ${socketDir}/${name}") socketNames;

      # systemdユーザサービス(`emacs.service`など)向けにenvironment.d経由で設定します。
      # インタラクティブなシェル初期化だけではGUIアプリやsystemdサービスに届きません。
      sessionVariables.SSH_AUTH_SOCK = sshSocket;
    };

    # インタラクティブシェル向け。
    home.sessionVariables.SSH_AUTH_SOCK = sshSocket;
  };
}
