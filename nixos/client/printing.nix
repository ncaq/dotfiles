{ pkgs, hardening, ... }:
{
  services.printing = {
    enable = true;
    # プリンタはIPP Everywhereのドライバレス接続で使っているので、
    # hplipのようなメーカ固有のドライバは入れない。
    drivers = with pkgs; [ cups-filters ];
    # ネットワーク上のプリンタの発見はcupsd自身のDNS-SD対応で足りる。
    # cups-browsedは過去にリモートコード実行の入口になった経緯があるので動かさない。
    browsed.enable = false;
  };

  systemd = {
    # cupsdはrootで動いて、フィルタとバックエンドを`cups`ユーザへ落として実行する。
    # 上流のユニットもnixpkgsのモジュールも`PrivateTmp`の他は何も絞っていないので、
    # 書ける場所を自分のディレクトリだけにして、権限も要るものへ絞る。
    services.cups.serviceConfig =
      removeAttrs hardening.network [
        # USB接続のプリンタは`/dev/bus/usb`を開く。
        # 今はネットワークのプリンタしか使っていないが、繋いだ時に動かなくなるのは避ける。
        "PrivateDevices"
        # デバイスを許可リスト方式へ切り替える副作用があり、同じくUSBのプリンタを開けなくなる。
        "ProtectClock"
      ]
      // {
        CapabilityBoundingSet = [
          # 631番で待ち受ける。
          "CAP_NET_BIND_SERVICE"
          # フィルタとバックエンドを`cups`ユーザへ落として実行する。
          "CAP_SETGID"
          "CAP_SETUID"
          # 落としたユーザのプロセスを止める。
          "CAP_KILL"
          # スプールや設定のファイルを、所有者とグループを付け替えながら扱う。
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_DAC_READ_SEARCH"
          "CAP_FOWNER"
          # 管理操作のBasic認証でPAMが監査ログを書く。
          "CAP_AUDIT_WRITE"
        ];
        RestrictAddressFamilies = hardening.network.RestrictAddressFamilies ++ [
          # インタフェースの一覧をnetlinkで取る。
          "AF_NETLINK"
        ];
        ReadWritePaths = [
          "/run/cups"
          "/var/cache/cups"
          # `/etc/cups`の実体で、プリンタの定義や`cupsd.conf`を書き換える。
          "/var/lib/cups"
          "/var/spool/cups"
        ];
      };
    # nixpkgsのモジュールは`ExecStartPre`でこれらを作るが、
    # 無いパスは`ReadWritePaths`に書けず、名前空間の準備の段階で失敗する。
    # 初回の起動でも先に存在するようにする。
    # モードと所有者は`ExecStartPre`とcupsdが作るものに合わせている。
    tmpfiles.rules = [
      "d /var/cache/cups 0770 root lp -"
      "d /var/lib/cups 0755 root root -"
      "d /var/spool/cups 0710 root lp -"
    ];
  };
}
