{ config, ... }:
{
  home.file = {
    # CIFSでマウントされて解決される。
    "Videos" = {
      source = config.lib.file.mkOutOfStoreSymlink "/mnt/chihiro/Videos";
    };
  };
}
