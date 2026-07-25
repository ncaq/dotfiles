# サーバの性能をあまり犠牲にしないで電力をある程度節約します。
_: {
  powerManagement = {
    # デフォルトで`enable`ですが、
    # わかりやすさのために明示的に有効にします。
    enable = true;
    # amd-pstateが有効になっている場合は、
    # governorはEPP(Energy Performance Preference)ヒントとして利用されます。
    # CPUに自律的に決めるヒントを与えているだけなので、
    # それで性能が固定されるというわけではありません。
    # デフォルトで`powersave`ですが念の為に明示的に設定します。
    cpuFreqGovernor = "powersave";
    powertop = {
      # USBデバイスはサーバには常時接続していないので、
      # powertopがUSBデバイスをスリープさせることには問題はありません。
      # SATA HDDなどには一応レイテンシへの影響がありますが、
      # 使用していない時はむしろスリープにしたいので、
      # 電力節約のために許容可能な範囲のレイテンシ増加は受け入れます。
      enable = true;
    };
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
}
