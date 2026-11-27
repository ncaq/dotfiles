{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # nixpkgsのfantomasは既定の`dotnet-sdk`(8.0)でビルドされ、
    # 実行時にもそれを引き込むので、
    # 入れているSDKの10.0に揃えます。
    (fantomas.override {
      buildDotnetGlobalTool =
        args:
        buildDotnetGlobalTool (
          args
          // {
            dotnet-sdk = dotnet-sdk_10;
            dotnet-runtime = dotnet-sdk_10;
          }
        );
    })
  ];
}
