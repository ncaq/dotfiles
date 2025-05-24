{ pkgs, username, ... }:
{
  users.users.${username} = {
    isNormalUser = true;
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
