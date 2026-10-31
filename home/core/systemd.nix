{
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
let
  # 稼働中のsystemdと同じビルドのパッケージ。
  # NixOSで実際に動いているsystemdは`systemd.package`で差し替えられる可能性があるため、
  # NixOS上ではシステム側と同じパッケージへ揃える。
  # standalone home-managerやTermuxでは`osConfig`が無いので`pkgs.systemd`にフォールバックする。
  # 判定はここの1か所だけに置き、
  # `systemd-run`などパッケージ単位で必要なモジュールはモジュール引数`systemdPackage`で受け取る。
  # `systemctl`のパスだけで足りるモジュールは`config.systemd.user.systemctlPath`を参照する。
  systemdPackage = if osConfig != null then osConfig.systemd.package else pkgs.systemd;
in
{
  _module.args = { inherit systemdPackage; };

  # home-managerが`systemctl --user`を呼ぶ時のパスは既定で`pkgs.systemd`を指す。
  # 別ビルドの`systemctl`で稼働中のPID 1と話さないように、
  # 上と同じパッケージへ揃える。
  systemd.user.systemctlPath = lib.getExe' systemdPackage "systemctl";
}
