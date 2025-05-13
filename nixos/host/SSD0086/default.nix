{ ... }:
{
  networking.hostName = "SSD0086";

  wsl = {
    enable = true;

    defaultUser = "ncaq";
    wslConf.user.default = "ncaq";
  };
}
