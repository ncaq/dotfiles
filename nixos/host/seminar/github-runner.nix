{
  pkgs,
  config,
  ...
}:
let
  githubActionsRunnerPackages = import ../../../lib/github-actions-runner-packages.nix {
    inherit pkgs;
  };
in
{
  services.github-runners.dotfiles-x64 = {
    enable = true;
    ephemeral = true;
    replace = true;
    extraPackages = githubActionsRunnerPackages;
    tokenFile = config.sops.secrets."github-runner/dotfiles".path;
    url = "https://github.com/ncaq/dotfiles";
  };

  sops.secrets."github-runner/dotfiles" = {
    sopsFile = ../../../secrets/seminar/github-runner/dotfiles.yaml;
    key = "pat";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
