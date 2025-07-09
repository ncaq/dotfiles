{ nixos-wsl, username, ... }:
{
  imports = [ nixos-wsl.nixosModules.default ];
  wsl = {
    enable = true;

    defaultUser = username;
    wslConf.user.default = username;

    docker-desktop.enable = true;

    useWindowsDriver = true;
  };
  isWSL = true;
}
