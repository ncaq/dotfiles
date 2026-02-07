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
    # Termux環境ではsystemdサービスが使えないためkeybaseサービスを無効にしますが、
    # keybaseのパッケージ自体は一応インストールします。
    home.packages = with pkgs; [ keybase ];
  }
