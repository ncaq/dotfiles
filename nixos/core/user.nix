{ pkgs, username, ... }:
{
  users.users.${username} = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "input"
      "networkmanager"
      "pipewire"
      "uinput"
      "wheel"
    ];
    shell = pkgs.zsh;
  };
}
