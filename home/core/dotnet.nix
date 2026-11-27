{
  lib,
  pkgs,
  config,
  ...
}:
{
  options.local.dotnet.sdk = lib.mkOption {
    type = lib.types.package;
    # 別名の`dotnet-sdk`は指す版が変わりうるので、バージョンを明示します。
    # EOLを考えて現行のLTSの10.0だけを入れています。
    default = pkgs.dotnet-sdk_10;
    description = ''
      入れるdotnet SDK。
      SDKに依存するツールもこれに揃えるので、版を上げる時はここだけを変える。
    '';
  };

  config.home.packages = with pkgs; [
    config.local.dotnet.sdk
    netcoredbg # デバッガ
  ];
}
