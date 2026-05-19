# サーバの性能をあまり犠牲にしないで電力をある程度節約します。
_: {
  powerManagement = {
    # デフォルトで`enable`ですが、
    # わかりやすさのために明示的に有効にします。
    enable = true;
    # amd-pstateが有効になっている場合は、
    # governorはEPP(Energy Performance Preference)ヒントとして利用されます。
    # CPUに自律的に決めるヒントを与えているだけなので、
    # それで性能が性能固定されると言うわけではありません。
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
}
