{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cloudflared
    dig
    iproute2
    net-tools
    nmap
    wget
  ];
}
