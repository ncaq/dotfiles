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
  tailscaleIpv4Range = config.local.tailscale.ipv4Range;
  tailscaleIpv6Range = config.local.tailscale.ipv6Range;
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
          # 待ち受け先の制限は`bind interfaces only`ではなくfirewallで行う(下のnetworking.firewall)。
          # Sambaはbroadcastできないインターフェイスをbind候補から外すので、
          # point-to-pointのtailscale0には`interfaces`でどう書いてもbindできない。
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
  #
  # インターフェイスだけでなく送信元アドレスでも絞る。
  # LANのインターフェイスにはグローバルIPv6アドレスも付いていて、
  # インターフェイス単位の許可ではインターネットからそこへ届く経路を塞げないため。
  # LANのIPv6はリンクローカルだけ許す。
  # LAN内のWindowsが探索で見つけた相手へIPv6で繋ぎに来ることがあり、
  # リンクローカルならインターネットからは届かない。
  networking.firewall.extraInputRules = ''
    iifname "${lanInterface}" ip saddr ${lanIpv4Subnet} tcp dport { 139, 445, 5357 } accept comment "SMB and wsdd from LAN"
    iifname "${lanInterface}" ip saddr ${lanIpv4Subnet} udp dport { 137, 138, 3702 } accept comment "NetBIOS and wsdd from LAN"
    iifname "${lanInterface}" ip6 saddr fe80::/10 tcp dport { 139, 445 } accept comment "SMB from LAN link-local IPv6"
    iifname "${tailscaleInterface}" ip saddr ${tailscaleIpv4Range} tcp dport 445 accept comment "SMB from tailnet"
    iifname "${tailscaleInterface}" ip6 saddr ${tailscaleIpv6Range} tcp dport 445 accept comment "SMB from tailnet"
  '';

  systemd.services = {
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
