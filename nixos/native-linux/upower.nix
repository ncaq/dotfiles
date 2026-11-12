_: {
  # バッテリーの状態をD-Busで提供します。
  # 本体にバッテリーの無いデスクトップでも、
  # MX Ergoなどの周辺機器やBluetoothデバイスの残量を`upower -d`で見られるようになります。
  # ラップトップのDPMSの切り替えが使う`upower`コマンドもこのサービスに接続し、
  # 無いとcoredumpします。
  services.upower.enable = true;
}
