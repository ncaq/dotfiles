# デスクトップの性能をあまり犠牲にしないでアイドル時の消費電力と発熱を抑えます。
_: {
  powerManagement = {
    # デフォルトで`enable`ですが、
    # わかりやすさのために明示的に有効にします。
    enable = true;
    # amd-pstate-eppドライバではgovernorは`performance`と`powersave`の2択で、
    # カーネルデフォルトは`performance`です。
    # `performance`だとEPP(Energy Performance Preference)も`performance`に固定され、
    # アイドル時でも積極的にブーストして無駄に発熱します。
    # クロック制御はCPUが自律的に行うため、
    # 負荷時のブーストが制限されるわけではありません。
    cpuFreqGovernor = "powersave";
  };

  # EPPの設定はpower-profiles-daemonに任せます。
  # デフォルトの`balanced`プロファイルがamd-pstateでは、
  # governorを`powersave`、EPPを`balance_performance`に設定します。
  # governorを`powersave`にしただけではEPPは`performance`のまま残るので、
  # EPPを設定する仕組みが別途必要です。
  # bulletでの実測ではEPPを`balance_performance`にすることで、
  # アイドル時のパッケージ電力が約39Wから約33Wに下がり、
  # シングルスレッド負荷時は変わらず約5.7GHzまでブーストしました。
  services.power-profiles-daemon.enable = true;
}
