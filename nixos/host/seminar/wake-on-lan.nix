# LAN内のbulletをWake-on-LANで起動するコマンドを提供します。
# magic packetを受け取る側の設定はbulletにあります。
#
# seminarは常時稼働していてtailnet経由でどこからでも入れるので、
# 外出先からbulletを使いたい時はseminarにログインして`wake-bullet`を実行します。
{ pkgs, hostInfo, ... }:
let
  wakeBullet = pkgs.writeShellApplication {
    name = "wake-bullet";
    runtimeInputs = [ pkgs.wakeonlan ];
    # magic packetはブロードキャストのUDPパケットを投げるだけで応答は返りません。
    # 実際に起動したかどうかは`ping bullet`などで確認します。
    text = ''
      wakeonlan ${hostInfo.bullet.macAddress}
    '';
  };
in
{
  environment.systemPackages = [ wakeBullet ];
}
