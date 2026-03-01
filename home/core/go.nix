{ pkgs, config, ... }:
{
  programs.go = {
    enable = true;
    env.GOPATH = "${config.home.homeDirectory}/.go";
  };

  home = {
    packages = with pkgs; [
      gopls
    ];
    sessionPath = [
      "${config.home.homeDirectory}/.go/bin"
    ];
  };
}
