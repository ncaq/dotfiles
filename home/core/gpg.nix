{
  pkgs,
  lib,
  isTermux,
  ...
}:
let
  keyConfig = import ../../key;
  # SSH認証に使用するGPGサブキーのkeygrip。
  # `gpg --list-keys --with-keygrip`で[A]能力を持つサブキーのkeygripを確認できます。
  sshKeygrip = "29C212A380A9E2977752FA41C35A2F9BF6CA24E2"; # 認証サブキー 0xACA66AB679E75544
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
          sshKeys = [ sshKeygrip ];
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
        home.file.".gnupg/gpg-agent.conf".text = ''
          enable-ssh-support
          pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
        '';
        home.file.".gnupg/sshcontrol".text = ''
          # SSH認証に使用するGPGサブキーのkeygrip
          ${sshKeygrip}
        '';
        home.packages = with pkgs; [
          pinentry-curses
        ];
      }
  )
]
