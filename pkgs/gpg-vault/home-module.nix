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
  inherit (pkgs.gpg-vault) clientSocketLinks socketDir sshSocketName;
  sshSocket = "${socketDir}/${sshSocketName}";
in
{
  options.services.gpg-vault.enable = lib.mkEnableOption "gpg-vaultのagentをgpgとsshのagentとして使う設定";

  config = lib.mkIf cfg.enable {
    # ソケットが見つからない時にgpgが鍵を持たないagentを勝手にspawnすると、
    # 「秘密鍵が見つからない」という紛らわしいエラーになるため、
    # autostartを無効化してソケット不在を明示的なエラーにします。
    programs.gpg.settings = {
      no-autostart = true;
      # gpgは秘密鍵の一覧を一度に取る近道(`HAVEKEY --list`)を最初に試します。
      # 制限付きのソケットではagentがこれを必ず拒否するので、
      # 署名のたびに「problem with fast path key listing: Forbidden - ignored」が出ます。
      # 鍵ごとの問い合わせに切り替わるだけで動作に問題は無く、
      # この警告を止める条件は`quiet`しかありません。
      # 鍵ファイルの`Remote-list`が効くのは`KEYINFO --list`で、この警告には効きません。
      quiet = true;
    };

    systemd.user = {
      # gpgクライアントは標準のソケットパス(`$XDG_RUNTIME_DIR/gnupg/`)を参照するため、
      # symlinkでvault agentのソケットへ誘導します。
      # gpgが普通のソケットとして探す名前の先は、vaultの制限付きのソケットです。
      # `%t`はユーザtmpfilesでは`$XDG_RUNTIME_DIR`に展開されます。
      tmpfiles.rules = [
        "d %t/gnupg 0700 - -"
      ]
      ++ lib.mapAttrsToList (
        name: target: "L+ %t/gnupg/${name} - - - - ${socketDir}/${target}"
      ) clientSocketLinks;

      # systemdユーザサービス(`emacs.service`など)向けにenvironment.d経由で設定します。
      # インタラクティブなシェル初期化だけではGUIアプリやsystemdサービスに届きません。
      sessionVariables.SSH_AUTH_SOCK = sshSocket;
    };

    # インタラクティブシェル向け。
    home.sessionVariables.SSH_AUTH_SOCK = sshSocket;
  };
}
