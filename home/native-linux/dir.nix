{ config, ... }:
{
  home.file = {
    "Videos" = {
      # 既にcifsでマウントされている自宅サーバのVideosディレクトリを参照。
      source = config.lib.file.mkOutOfStoreSymlink "/mnt/chihiro/Videos";
    };
  };
}
