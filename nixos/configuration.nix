{
  pkgs,
  ...
}:
{
  system.stateVersion = "24.11";

  nix.settings = {
    experimental-features = [
      "flakes"
      "nix-command"
    ];
    cores = 0;
    max-jobs = "auto";
    accept-flake-config = true;
    trusted-users = [
      "root"
      "@wheel"
    ];
  };

  i18n.defaultLocale = "ja_JP.UTF-8";

  time.timeZone = "Asia/Tokyo";

  programs = {
    dconf.enable = true;
    zsh.enable = true;
  };

  services = {
    dbus.packages = [ pkgs.dconf ];
    locate = {
      enable = true;
      package = pkgs.plocate;
      interval = "hourly";
      pruneNames = [
        "$Recycle.Bin"
        ".Trash"
        ".Trash-1000"
        ".bzr"
        ".cabal"
        ".cache"
        ".cargo"
        ".dub"
        ".gem"
        ".ghcup"
        ".git"
        ".go"
        ".hg"
        ".julia"
        ".metals"
        ".npm"
        ".pyenv"
        ".rbenv"
        ".rustup"
        ".snapshots"
        ".stack"
        ".stack-work"
        ".stack-work-fast"
        ".stack-work-profile"
        ".stack-work-test"
        ".svn"
        "WinSxS"
        "__pycache__"
        "_cache"
        "_site"
        "appcache"
        "cache"
        "cache2"
        "cached"
        "cdk.out"
        "dist"
        "dist-newstyle"
        "dist-packages"
        "eln-cache"
        "elpy"
        "file-backup"
        "htmlcache"
        "node_modules"
        "site-packages"
        "steam-runtime"
        "target"
        "texmf-dist"
        "undo-tree"
        "virtualenv"
      ];
    };
  };

  users.users.ncaq = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    shell = pkgs.zsh;
  };
}
