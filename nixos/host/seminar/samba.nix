{
  lib,
  config,
  hardening,
  ...
}:
let
  lanInterface = config.local.lan.interface;
  lanIpv4Subnet = config.local.lan.ipv4Subnet;
  tailscaleInterface = config.services.tailscale.interfaceName;
in
{
  services = {
    samba = {
      enable = true;
      # 全インターフェイスではなく、LANとtailnetのインターフェイスだけに開ける(下のnetworking.firewall)。
      openFirewall = false;
      settings = {
        global = {
          # 基本設定
          "workgroup" = "WORKGROUP";
          "server string" = "Seminar Home Server";
          "netbios name" = "SEMINAR";
          # セキュリティ設定
          "security" = "user"; # ユーザー認証必須
          "map to guest" = "never"; # ゲストアクセス禁止
          # 待ち受けるアドレスをLANのプライベートアドレスとTailscaleのアドレスに限定する。
          # firewallの制限と二重になるが、
          # LANのインターフェイスにはグローバルIPv6アドレスも付いていて、
          # インターフェイス単位のfirewallではそこへの到達を防げないため、
          # bind先そのものを絞る。
          # コンテナ向けのvethにもbindしなくなり、
          # CIランナーなどのコンテナからホストのSMBへ到達できなくなる。
          # サブネット表記にすると、そのサブネットに属するアドレスを持つインターフェイスのそのアドレスだけにbindする。
          "bind interfaces only" = "yes";
          "interfaces" = lib.concatStringsSep " " [
            lanIpv4Subnet
            "100.64.0.0/10" # Tailscale IPv4
            "fd7a:115c:a1e0::/48" # Tailscale IPv6
          ];
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
    samba-wsdd = {
      enable = true;
      # 探索はLANの中でしか意味が無いので、LANのインターフェイスに限定する。
      interface = lanInterface;
      openFirewall = false;
    };
    # Avahi/mDNSで Samba サービスをアドバタイズ
    avahi.extraServiceFiles = {
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
  };

  # SMB本体はLANとtailnetの両方から、
  # NetBIOSやWS-Discoveryなどの探索系はLANからだけ受け付ける。
  # tailnetの端末はMagicDNS名で直接繋ぐので探索は要らない。
  # 139(NetBIOS session)は445(direct SMB)が使えない古いクライアント用なので、
  # tailnet側には開けない。
  networking.firewall.interfaces = {
    ${lanInterface} = {
      allowedTCPPorts = [
        139
        445
        5357 # wsdd
      ];
      allowedUDPPorts = [
        137
        138
        3702 # wsdd
      ];
    };
    ${tailscaleInterface}.allowedTCPPorts = [ 445 ];
  };

  systemd.services = {
    # `bind interfaces only`を有効にするとsmbdは起動時に存在するインターフェイスにしかbindしないので、
    # tailscale0が現れてから起動するように順序付ける。
    # tailscaledが壊れていてもSMB自体は動くように、requiresではなくwantsにしておく。
    samba-smbd = {
      wants = [ "sys-subsystem-net-devices-${tailscaleInterface}.device" ];
      after = [ "sys-subsystem-net-devices-${tailscaleInterface}.device" ];
    };

    samba-password-setup = {
      description = "Setup Samba password for ncaq user";
      requires = [ "samba-smbd.service" ];
      after = [ "samba-smbd.service" ];
      bindsTo = [ "samba-smbd.service" ];
      wantedBy = [ "multi-user.target" ];
      # smbpasswdはrootが所有する/var/lib/samba配下のpassdbを直接更新するだけで、
      # 追加のcapabilityもネットワーク通信も不要なので、
      # UNIXソケットのみ許可のハードニングまで絞る。
      # 平文のSMBパスワードを読むユニットなので絞る価値が大きい。
      # seminar上で同等のサンドボックスを再現して、
      # `smbpasswd -a -s`が成功することを確認済み。
      serviceConfig = hardening.unixSocket // {
        Type = "oneshot";
        RemainAfterExit = true;
        # tdbのロックやキャッシュに触る可能性があるディレクトリは、
        # `-`プレフィックスで存在する場合のみ書き込みを許可する。
        ReadWritePaths = [
          "/var/lib/samba"
          "-/var/cache/samba"
          "-/var/lock/samba"
          "-/run/samba"
        ];
      };
      script = ''
        set -euo pipefail
        PASSWORD=$(cat ${config.sops.secrets."samba-password".path})
        # smbpasswdはパスワードを2回(確認用)読み取る
        (echo "$PASSWORD"; echo "$PASSWORD") | ${lib.getExe' config.services.samba.package "smbpasswd"} -a -s ncaq
      '';
    };
  };

  sops.secrets."samba-password" = {
    sopsFile = ../../../secrets/samba.yaml;
    key = "password";
    mode = "0400";
  };
}
