{
  lib,
  pkgs,
  username,
  ...
}:
let
  # 9950X3Dのような片側CCDにだけ3D V-Cacheを搭載するCPUでは、
  # カーネルのamd_x3d_vcacheドライバが提供する`amd_x3d_mode`によって、
  # amd-pstateのコア優先度ランキングを切り替えられる。
  #
  # - `frequency`: 高クロック側CCDを優先(デフォルト)
  # - `cache`: 3D V-Cache側CCDを優先
  #
  # ゲーム中はキャッシュ容量が効くワークロードが多いので、
  # customフックでゲーム開始時に`cache`へ切り替えて、
  # スケジューラがV-Cache側CCDへスレッドを配置するようにする。
  # 終了時はデフォルトの`frequency`へ戻す。
  #
  # ワイルドカード部分はACPIデバイス名(bulletでは`AMDI0101:00`)を吸収する。
  # X3D非搭載CPUのホストではglobがマッチせず何もしない。
  modeFileGlob = "/sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode";

  x3d-mode = pkgs.writeShellApplication {
    name = "x3d-mode";
    text = ''
      mode="$1"
      for f in ${modeFileGlob}; do
        [ -e "$f" ] || continue
        echo "$mode" > "$f"
      done
    '';
  };
in
{
  # LutrisがProton(umu)経由で起動するゲームでもgamemodeが効くように、
  # `libgamemodeauto.so`のRUNPATHを修正する。
  nixpkgs.overlays = [ (import ../../lib/gamemode-lib-rpath-overlay.nix) ];

  programs.gamemode = {
    enable = true;
    settings.custom = {
      start = "${lib.getExe x3d-mode} cache";
      end = "${lib.getExe x3d-mode} frequency";
    };
  };

  # gamemodedはCPUガバナー変更などの特権操作をpkexecで行う。
  # gamemodeが同梱するpolkitルールは`gamemode`グループのユーザにだけ認証なしで許可するので、
  # ユーザをグループに追加する。
  users.users.${username}.extraGroups = [ "gamemode" ];

  # `amd_x3d_mode`はデフォルトでroot専用書き込みなので、
  # gamemodedを動かす一般ユーザが属するgamemodeグループへ書き込みを許可する。
  # `%S`はsysfsのマウントポイント、
  # `%p`はデバイスパスに展開される。
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="amd_x3d_vcache", RUN+="${pkgs.coreutils}/bin/chgrp gamemode %S%p/amd_x3d_mode", RUN+="${pkgs.coreutils}/bin/chmod 0664 %S%p/amd_x3d_mode"
  '';
}
