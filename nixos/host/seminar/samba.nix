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
  chihiroPath = "/mnt/noa/chihiro";
  # 共有のルートからの相対パス。`recycle:repository`はこの下にユーザごとのディレクトリを作る。
  recycleDir = ".recycle";
in
{
  services = {
    samba = {
      enable = true;
      # 全インタフェースではなく、LANとtailnetのインタフェースだけに開ける(下のnetworking.firewall)。
      openFirewall = false;
      # NetBIOSの名前解決とブラウズを担うデーモン。
      # NetBIOSを使わない理由は下の`disable netbios`に書いてある。
      nmbd.enable = false;
      # ドメインのユーザやグループをNSSやPAMへ見せるデーモン。
      # ドメインに参加しない単体のサーバで、
      # ユーザは`/etc/passwd`とSamba自身のpassdbだけで解決するので使わない。
      # rootで動き続けるデーモンを1つ減らす。
      winbindd.enable = false;
      settings = {
        global = {
          # 基本設定
          # NetBIOSの名前とワークグループは書かない。
          # 既定ではホスト名から導いた`SEMINAR`と`WORKGROUP`になり、
          # NetBIOSを使わないので他の値にする理由も無い。
          "server string" = "Seminar Home Server";
          # セキュリティ設定
          "security" = "user"; # ユーザ認証必須
          "map to guest" = "never"; # ゲストアクセス禁止
          # 待ち受け先の制限は`bind interfaces only`ではなくfirewallで行う(下のnetworking.firewall)。
          # Sambaはbroadcastできないインタフェースをbind候補から外すので、
          # point-to-pointのtailscale0には`interfaces`でどう書いてもbindできない。
          #
          # NetBIOSは使わない。
          # SMB2以降は445番へ直接繋ぐので、NetBIOSのセッション(139番)が要るのはSMB1の時代のクライアントだけで、
          # Sambaは既定でSMB1を受け付けないのでそういうクライアントはどのみち繋がらない。
          # 名前の解決はtailnetのMagicDNSかmDNS(下のavahi)で、
          # Windowsのエクスプローラへの表示はWS-Discovery(下のsamba-wsdd)で足りる。
          # NetBIOSはIPv4だけのプロトコルで、
          # nmbdはコンテナのvethも含む全てのインタフェースへ届かないブロードキャストを投げ続けていた。
          "disable netbios" = "yes";
          # 既定の待ち受けは`tcp, nbt`で、`disable netbios`だけでは`nbt`(139番)が残るので、
          # 445番へ直接繋ぐ`tcp`だけにする。
          "server smb transports" = "tcp";
        };
        "chihiro" = {
          "path" = chihiroPath;
          "browsable" = "yes";
          "read only" = "no"; # 書き込み可能に設定
          "guest ok" = "no";
          "valid users" = "ncaq";
          "create mask" = "0664";
          "directory mask" = "0775";
          # ゴミ箱
          # Sambaには古いものを消す機能が無いので、掃除は下のsystemd.tmpfilesが行う。
          "vfs objects" = "recycle";
          "recycle:repository" = "${recycleDir}/%U";
          "recycle:keeptree" = "yes";
          "recycle:versions" = "yes";
        };
      };
    };
    # Windows 10/11のネットワーク探索で表示されるように
    samba-wsdd = {
      enable = true;
      # 探索はLANの中でしか意味が無いので、LANのインタフェースに限定する。
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
  # WS-Discoveryの探索はLANからだけ受け付ける。
  # tailnetの端末はMagicDNS名で直接繋ぐので探索は要らない。
  #
  # インタフェースだけでなく送信元アドレスでも絞る。
  # LANのインタフェースにはグローバルIPv6アドレスも付いていて、
  # インタフェース単位の許可ではインターネットからそこへ届く経路を塞げないため。
  # LANのIPv6はリンクローカルだけ許す。
  # wsddはIPv6のマルチキャストでも探索に応答し、
  # LAN内のWindowsが探索で見つけた相手へIPv6で繋ぎに来ることがあるが、
  # リンクローカルならインターネットからは届かない。
  networking.firewall.extraInputRules = ''
    iifname "${lanInterface}" ip saddr ${lanIpv4Subnet} tcp dport { 445, 5357 } accept comment "SMB and wsdd from LAN"
    iifname "${lanInterface}" ip saddr ${lanIpv4Subnet} udp dport 3702 accept comment "wsdd from LAN"
    iifname "${lanInterface}" ip6 saddr fe80::/10 tcp dport { 445, 5357 } accept comment "SMB and wsdd from LAN link-local IPv6"
    iifname "${lanInterface}" ip6 saddr fe80::/10 udp dport 3702 accept comment "wsdd from LAN link-local IPv6"
    iifname "${tailscaleInterface}" ip saddr ${tailscaleIpv4Range} tcp dport 445 accept comment "SMB from tailnet"
    iifname "${tailscaleInterface}" ip6 saddr ${tailscaleIpv6Range} tcp dport 445 accept comment "SMB from tailnet"
  '';

  systemd = {
    # Sambaのゴミ箱へ入ってから、通常のゴミ箱と同じ日数が経ったものを消す。
    # Sambaはファイルを1つずつゴミ箱へ移動するので、その時にctimeが更新される。
    # systemd-tmpfilesはatimeとmtimeとctimeの全てが期限より古いファイルだけを消すため、
    # 元のファイルがどれだけ古くても、ゴミ箱へ入ってからの日数で数えられる。
    # `e`は中身だけを掃除して、ディレクトリ自体は作りも消しもしない。
    tmpfiles.rules = [
      "e ${chihiroPath}/${recycleDir} - - - ${toString config.local.trash.retentionDays}d"
    ];

    # smbdはrootで待ち受けて、接続ごとに認証したユーザへ切り替える。
    # 乗っ取られるとroot相当になるので、見える場所と書ける場所を必要なものだけにする。
    #
    # 禁止する場所を並べるのではなく、
    # `confinement`で空のルートへ必要なものだけをbind mountする。
    # ホームや他のデータ、`/run/secrets`、`/etc/shadow`、SSHのホスト鍵などは、
    # rootのままでも名前空間の中に存在しないので読めない。
    services.samba-smbd = {
      # 共有がマウントされていない時は、bind mountの元が無いので起動に失敗する。
      # 共有を出せないSambaを動かす意味は無いので、マウントを必須にして順序も付ける。
      # 上流の`/var/lib/samba`と同じオプションなので、合わせて上書きする。
      unitConfig.RequiresMountsFor = lib.mkForce [
        "/var/lib/samba"
        chihiroPath
      ];
      confinement = {
        enable = true;
        # `ExecStart`だけでなく、
        # `LD_LIBRARY_PATH`で渡されるNSSのモジュールもNix storeから見えるようにする。
        fullUnit = true;
        # シェルを呼ぶ設定(`add user script`など)は使っていない。
        binSh = null;
      };
      serviceConfig = hardening.network // {
        # `confinement`は既定でユーザ名前空間も分けるが、
        # それではホストのユーザへ切り替えられず、ファイルの所有者も合わなくなる。
        PrivateUsers = false;
        CapabilityBoundingSet = [
          # 445番で待ち受ける。
          "CAP_NET_BIND_SERVICE"
          # 認証したユーザへ切り替える。
          "CAP_SETGID"
          "CAP_SETUID"
          # ユーザを問わず共有の中を扱う。
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_DAC_READ_SEARCH"
          "CAP_FOWNER"
          # 他のユーザが所有するファイルにoplock用のleaseを掛ける。
          "CAP_LEASE"
          # ユーザへ切り替えた子プロセスへシグナルを送る。
          "CAP_KILL"
        ];
        RestrictAddressFamilies = hardening.network.RestrictAddressFamilies ++ [
          # インタフェースの一覧をnetlinkで取る。
          "AF_NETLINK"
        ];
        # `/run/samba`を起動のたびに用意する。
        # tmpfilesには無く、今まではsmbdが自分で作っていたが、
        # 無いパスはbind mountできない。
        RuntimeDirectory = [ "samba" ];
        BindPaths = [
          chihiroPath
          "/var/cache/samba"
          "/var/lib/samba"
          "/var/log/samba"
          # smbdはビルド時に決まった`/var/run`と`/var/lock`の側のパスを使う。
          # ホストではどちらも`/run`へのシンボリックリンクだが、空のルートには無い。
          "/run/samba:/var/run/samba"
          "/run/lock/samba:/var/lock/samba"
        ];
        BindReadOnlyPaths = [
          "/etc/samba/smb.conf"
          # 接続してきたユーザのuidとgidを引く。
          # ファイル単位のbind mountなので、ユーザを増減させた時はsmbdを再起動するまで反映されない。
          "/etc/group"
          "/etc/nsswitch.conf"
          "/etc/passwd"
          # ログの時刻。
          "-/etc/localtime"
        ];
      };
    };

    services.samba-password-setup = {
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
