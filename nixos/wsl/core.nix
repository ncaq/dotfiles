{
  lib,
  config,
  inputs,
  username,
  ...
}:
let
  cfg = config.wsl;
in
{
  imports = [ inputs.nixos-wsl.nixosModules.default ];

  options.wsl = {
    windowsUserHome = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.wslConf.automount.root}/c/Users/${cfg.defaultUser}";
      description = "Windows user home directory path as seen from WSL.";
    };
    windowsAppData = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.windowsUserHome}/AppData/Roaming";
      description = "Windows AppData/Roaming directory path as seen from WSL.";
    };
  };

  config.wsl = {
    enable = true;

    defaultUser = username;
    wslConf.user.default = username;

    docker-desktop.enable = true;

    useWindowsDriver = true;
  };
}
