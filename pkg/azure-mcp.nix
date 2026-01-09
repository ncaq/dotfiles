# azure-mcp - Azure MCP Server
# https://github.com/Azure/azure-mcp
# Microsoft Azure公式のMCPサーバーです。
{
  lib,
  buildDotnetModule,
  fetchFromGitHub,
  dotnetCorePackages,
}:
buildDotnetModule rec {
  pname = "azure-mcp";
  version = "0.5.8";

  src = fetchFromGitHub {
    owner = "Azure";
    repo = "azure-mcp";
    tag = version;
    hash = "sha256-dFy7qW8utF2ZV/XSHnm0matYk3NctgcqroahYHA1vOE=";
  };

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_9_0;

  nugetDeps = ./azure-mcp-nuget-deps.json;

  projectFile = [ "core/src/AzureMcp.Cli/AzureMcp.Cli.csproj" ];

  postFixup = ''
    mv $out/bin/azmcp $out/bin/azure-mcp || true
  '';

  meta = {
    description = "Azure MCP Server - Official MCP server for Azure by Microsoft";
    homepage = "https://github.com/Azure/azure-mcp";
    license = lib.licenses.mit;
    mainProgram = "azure-mcp";
    platforms = lib.platforms.linux;
  };
}
