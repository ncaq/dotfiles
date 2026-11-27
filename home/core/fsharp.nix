{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    # nixpkgsのfantomasは既定の`dotnet-sdk`でビルドされ、
    # 実行時にもそれを引き込むので、
    # `local.dotnet.sdk`で入れているSDKに揃えます。
    (fantomas.override {
      buildDotnetGlobalTool =
        args:
        buildDotnetGlobalTool (
          args
          // {
            dotnet-sdk = config.local.dotnet.sdk;
            dotnet-runtime = config.local.dotnet.sdk;
          }
        );
    })
  ];
}
