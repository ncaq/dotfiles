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
  # `libgamemodeauto.so`が`dlopen`で`libgamemode.so`を見つけられるように、
  # 自身のlibディレクトリをRUNPATHへ追加する。
  #
  # `libgamemodeauto.so`は`LD_PRELOAD`されると、
  # コンストラクタで`libgamemode.so`を`dlopen`してgamemodedへ登録を行う。
  # この`dlopen`はライブラリ名だけで呼ばれるため、
  # 呼び出し元である`libgamemodeauto.so`自身のRUNPATHか、
  # `LD_LIBRARY_PATH`などの検索パスに`libgamemode.so`が無いと失敗する。
  #
  # nixpkgsのgamemodeはRUNPATHにglibcしか持たせていないので、
  # LutrisがProton(umu)経由でゲームを起動する時のように、
  # pressure-vesselコンテナ内で検索パスがリセットされる環境では、
  #
  # ```
  # gamemodeauto: dlopen failed - libgamemode.so: cannot open shared object file
  # ```
  #
  # というエラーになりgamemodeが有効化されない。
  # コンテナ内にも`/nix/store`は共有されているため、
  # RUNPATHでstoreパスを直接指せば解決する。
  #
  # nixpkgsは同じ理由で`gamemoded`などのバイナリにはrpathを追加済みなので、
  # ライブラリにも同じ措置をするだけであり、
  # upstreamのnixpkgsでも修正されるべきパッケージングバグ。
  nixpkgs.overlays = [
    (_final: prev: {
      gamemode = prev.gamemode.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          patchelf --add-rpath "$lib/lib" "$lib/lib/libgamemodeauto.so.0.0.0"
        '';
      });
    })
  ];

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
