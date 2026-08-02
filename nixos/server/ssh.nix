{ lib, ... }:
{
  # サーバはヘッドレス運用なので、tailscaledが故障した時の復旧経路として、
  # tailnet限定にせずLANなどからのssh/moshも受け付ける。
  services.openssh.openFirewall = lib.mkForce true;
  programs.mosh.openFirewall = lib.mkForce true;
}
