{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Steam外部も含めたアプリをSteamのProtonを使って管理・起動するためのツール。
    # FHS環境にgamemodeのライブラリを追加して、
    # gamemodeautoの`dlopen`が`libgamemode.so`を見つけられるようにする。
    (lutris.override { extraLibraries = pkgs: [ pkgs.gamemode.lib ]; })
  ];
}
