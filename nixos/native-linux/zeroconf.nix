_: {
  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
    };
    # systemd-resolvedのmDNSレスポンダを無効化してavahiにmDNSを一本化する。
    # 両者が同じホスト名を広告するとavahiがself-conflictを起こし、
    # `Host name conflict, retrying with hostname-N`で名前末尾の数字が増え続ける。
    # Debian trixieの、
    # [TC decision on avahi vs systemd-resolved - #1091864](https://lists.debian.org/debian-ctte/2025/02/msg00019.html)や、
    # Fedora(`-Ddefault-mdns=no`ビルド)が同等の対処をしており、
    # avahi-daemonを主のmDNS実装とする運用が業界標準。
    resolved.settings.Resolve.MulticastDNS = "no";
  };

  # nscdのsystemd再起動制限を緩和。
  # 起動時にavahiがネットワーク変更のたびにnscdを再起動させるため。
  systemd.services.nscd = {
    serviceConfig = {
      # 再起動間隔を延長。
      RestartSec = "5s";
      # 再起動試行回数を増やす。
      StartLimitBurst = 10;
      StartLimitIntervalSec = 30;
    };
  };
}
