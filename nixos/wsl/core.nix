{ inputs, username, ... }:
{
  imports = with inputs; [ nixos-wsl.nixosModules.default ];
  wsl = {
    enable = true;

    defaultUser = username;
    wslConf.user.default = username;

    docker-desktop.enable = true;

    useWindowsDriver = true;
  };
}
