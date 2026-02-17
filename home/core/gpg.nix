{
  pkgs,
  config,
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
        # common.confはimportGpgKeysより前に配置する必要があるため、
        # home.fileではなくactivation hookで直接書き込みます。
        home.activation.cleanupGpgKeyboxd =
          lib.hm.dag.entryBetween [ "importGpgKeys" ] [ "createGpgHomedir" ]
            ''
              # Termux環境ではsystemdによるGPGデーモンのライフサイクル管理がないため、
              # keyboxdのdotlockファイルが残留しsops-nixの復号化をしばしば妨げます。
              # keyboxdを無効化して従来のpubring.kbx形式を使用することで回避します。
              # 並列アクセス性能は低下しますが、
              # 個人のTermux環境ではほぼ問題にならないため許容します。
              echo "no-use-keyboxd" > "${config.home.homeDirectory}/.gnupg/common.conf"
              $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpgconf --kill keyboxd 2>/dev/null || true
              $DRY_RUN_CMD ${pkgs.trashy}/bin/trash "${config.home.homeDirectory}/.gnupg/public-keys.d/" || true
            '';
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
