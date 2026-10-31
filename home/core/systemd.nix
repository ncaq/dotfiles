{
  lib,
  osConfig ? null,
  ...
}:
{
  # home-managerが`systemctl --user`を呼ぶ時のパスは既定で`pkgs.systemd`を指すが、
  # NixOSで実際に動いているsystemdは`systemd.package`で差し替えられる可能性がある。
  # 別ビルドの`systemctl`で稼働中のPID 1と話さないように、
  # NixOS上ではシステム側と同じパッケージへ揃える。
  # 他のモジュールも`systemctl`が必要な時は`config.systemd.user.systemctlPath`を参照する。
  # standalone home-managerやTermuxでは`osConfig`が無いので既定値のまま。
  systemd.user.systemctlPath = lib.mkIf (osConfig != null) (
    lib.getExe' osConfig.systemd.package "systemctl"
  );
}
