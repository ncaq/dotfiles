{ lib, pkgs, ... }:
{
  boot = {
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/efi";
      };
      timeout = 1;
      limine = {
        enable = true;
        # ディスク容量を埋め尽くさないように上限を定めます。
        maxGenerations = 40;
        style = {
          interface = {
            # ブート時はGPUを効率的に使えないことが多いため解像度を下げて負荷を減らします。
            resolution = "1920x1080";
          };
          # 画像は`resolution`と同じ1920x1080なので、
          # デフォルトのwallpaperStyle(stretched)でも歪みません。
          wallpapers = [ ../../wallpaper/hare-sitting-at-the-pc-and-looking-back.png ];
        };
        # セキュアブート設定。
        secureBoot = {
          # `/var/lib/sbctl`の鍵でlimineバイナリをsbctl署名します。
          enable = true;
          # 自動での鍵作成と署名を有効化して、
          # 確認は手動で`sudo bootctl`や`sudo sbctl status`で行います。
          autoGenerateKeys = true;
          autoEnrollKeys = {
            enable = true;
            # デフォルトでMicrosoftやファームウェアの鍵が含まれるため、
            # ファームウェア特有の事情がない限り`extraArgs`の設定は基本的に不要です。
          };
        };
        # Nixが直接対応していない設定を直接書き込みます。
        extraConfig = ''
          # 最後に起動したエントリを記憶して次回起動時に自動選択します。
          remember_last_entry: yes
          # ブートローダーでも慣れたdvorak入力を使ってトラブルシューティングを楽にします。
          keyboard_layout: dvorak
        '';
      };
    };
    initrd = {
      systemd = {
        enable = true;
      };
    };
  };

  # Limineの`remember_last_entry`はエントリのパス名をEFI変数`LimineLastBootedEntry`に保存します。
  # 例: `NixOS default profile/Generation 769`
  # NixOSの世代エントリは名前に世代番号を含むため、
  # 記憶されたままだとrebuild後も古い世代が延々と選択され続けてしまいます。
  # そこでNixOS起動時に記憶を消して、
  # 次回起動は`default_entry`(常に最新世代)に戻します。
  # Windowsのエントリ名は不変なので、
  # Windows起動時の記憶はそのまま機能します。
  # Windows Updateの複数回再起動でもWindowsが選択され続けます。
  systemd.services.limine-forget-last-entry =
    let
      limineLastBootedEntryPath = "/sys/firmware/efi/efivars/LimineLastBootedEntry-513ee0d0-6e43-cb05-b272-f146a2fcb88a";
    in
    {
      description = "Forget Limine last booted entry so the newest NixOS generation boots next";
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExists = limineLastBootedEntryPath;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "limine-forget-last-entry";
            runtimeInputs = with pkgs; [
              coreutils
              e2fsprogs
            ];
            text = ''
              var=${limineLastBootedEntryPath}
              # efivarfsは変数をimmutable属性付きで公開するため、削除前に解除します。
              chattr -i "$var"
              rm "$var"
            '';
          }
        );
      };
    };
}
