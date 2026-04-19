{
  lib,
  pkgs,
  username,
  ...
}:
{
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    interval = "hourly";
    prunePaths = lib.mkOptionDefault [
      "/home/${username}/.claude/plugins"
      "/home/${username}/.claude/projects"
    ];
    pruneNames = lib.mkOptionDefault [
      "$Recycle.Bin"
      ".Trash"
      ".Trash-1000"
      ".cabal"
      ".cargo"
      ".dub"
      ".gem"
      ".ghcup"
      ".go"
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
      "Trash"
      "WinSxS"
      "__pycache__"
      "_cache"
      "_site"
      "appcache"
      "backup.encrypted"
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
}
