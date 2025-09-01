{ ... }:
{
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
    gvfs.enable = true;
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
