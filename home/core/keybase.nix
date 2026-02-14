{
  pkgs,
  isTermux,
  ...
}:

if !isTermux then
  {
    services = {
      keybase.enable = true;
      kbfs.enable = true;
    };
  }
else
  {
    # Termux環境ではserviceが利用できないためパッケージだけ明示的にインストールします。
    home.packages = with pkgs; [ keybase ];
  }
