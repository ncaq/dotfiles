{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Sambaパスワードをsopsで管理
  sops.secrets."samba-password" = {
    sopsFile = ../../../secrets/seminar/samba.yaml;
    key = "password";
    mode = "0400";
  };

  # Sambaパスワードを自動設定するサービス
  systemd.services.samba-password-setup = {
    description = "Setup Samba password for ncaq user";
    requires = [ "samba-smbd.service" ];
    after = [ "samba-smbd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      PASSWORD=$(cat ${config.sops.secrets."samba-password".path})
      # smbpasswdはパスワードを2回(確認用)読み取る
      (echo "$PASSWORD"; echo "$PASSWORD") | ${lib.getExe' pkgs.samba "smbpasswd"} -a -s ncaq
    '';
  };

  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        # 基本設定
        "workgroup" = "WORKGROUP";
        "server string" = "Seminar Home Server";
        "netbios name" = "SEMINAR";

        # セキュリティ設定
        "security" = "user"; # ユーザー認証必須
        "map to guest" = "never"; # ゲストアクセス禁止
        # SMB3以降のみ許可
        "client min protocol" = "SMB3";
        "server max protocol" = "SMB3_11";
        "server min protocol" = "SMB3";
      };

      "chihiro" = {
        "path" = "/mnt/noa/chihiro";
        "browsable" = "yes";
        "read only" = "no"; # 書き込み可能に設定
        "guest ok" = "no";
        "valid users" = "ncaq";
        "create mask" = "0664";
        "directory mask" = "0775";

        # ゴミ箱
        "vfs objects" = "recycle";
        "recycle:repository" = ".recycle/%U";
        "recycle:keeptree" = "yes";
        "recycle:versions" = "yes";
      };
    };
  };

  # Windows 10/11のネットワーク探索で表示されるように
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Avahi/mDNSで Samba サービスをアドバタイズ
  services.avahi.extraServiceFiles = {
    smb = ''
      <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h</name>
        <service>
          <type>_smb._tcp</type>
          <port>445</port>
        </service>
      </service-group>
    '';
  };
}
