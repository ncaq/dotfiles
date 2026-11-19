# サーバの性能をあまり犠牲にしないで電力をある程度節約します。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  powerManagement = {
    # デフォルトで`enable`ですが、
    # わかりやすさのために明示的に有効にします。
    enable = true;
    # amd-pstate-eppドライバではgovernorは`performance`と`powersave`の2択で、
    # カーネルデフォルトは`performance`です。
    # `performance`だとEPP(Energy Performance Preference)も`performance`に固定されます。
    # `powersave`でもクロック制御はCPUが自律的に行い、
    # EPPはそのヒントでしかないので、
    # 性能が低く固定されるわけではありません。
    cpuFreqGovernor = "powersave";
    powertop = {
      # USBデバイスはサーバには常時接続していないので、
      # powertopがUSBデバイスをスリープさせることには問題はありません。
      enable = true;
      # powertopの`--auto-tune`はSATAのLPMも`med_power_with_dipm`にするので、
      # 終わった後に`scsiLinkPolicy`のudevルールをかけ直して戻します。
      postStart = ''
        ${lib.getExe' config.systemd.package "udevadm"} trigger --settle --action=add --subsystem-match=scsi_host
      '';
    };
    # SATAのLPMを省電力にすると、
    # HDDのリンクがリセットを繰り返して、
    # RAIDからディスクが脱落することがあります。
    # seminarでは`med_power_with_dipm`の間に、
    # 8日で3台合わせて80回以上リセットが起きて、
    # 最後には1台が脱落しました。
    # 同じ症状がWDのHDDで報告されていて、
    # `max_performance`にすると収まっています。
    # https://discussion.fedoraproject.org/t/fc44-problem-with-link-power-management-policy-type-med-power-with-dipm-on-wd-gold-hdd/190748
    # https://github.com/ncaq/dotfiles/issues/1732
    scsiLinkPolicy = "max_performance";
  };
  # governorが`powersave`でもEPPはファームウェアの初期値のまま残り、
  # seminarでは`performance`になっていて、
  # アイドル時でもコアが最大クロック近くまでブーストしていました。
  # desktopと同様にEPPの設定はpower-profiles-daemonに任せて、
  # デフォルトの`balanced`プロファイルでEPPを`balance_performance`にします。
  services.power-profiles-daemon.enable = true;
  # upstreamのユニットは`WantedBy=graphical.target`ですが、
  # サーバはヘッドレスで`multi-user.target`までしか到達しないため、
  # そのままでは自動起動しません。
  systemd.services.power-profiles-daemon.wantedBy = [ "multi-user.target" ];
  # `powertop`
  environment.systemPackages = [ pkgs.powertop ];
}
