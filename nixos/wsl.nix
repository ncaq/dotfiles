{ ... }:
{
  wsl = {
    enable = true;

    defaultUser = "ncaq";
    wslConf.user.default = "ncaq";

    docker-desktop.enable = true;
  };
}
