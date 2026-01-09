# gcloud-mcp - Google Cloud MCP Server
# https://github.com/googleapis/gcloud-mcp
# Google公式のgcloud CLI用MCPサーバーです。
# npmパッケージはビルド済みバンドルを含むため、直接インストールします。
{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  makeWrapper,
}:
stdenvNoCC.mkDerivation rec {
  pname = "gcloud-mcp";
  version = "0.5.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@google-cloud/gcloud-mcp/-/gcloud-mcp-${version}.tgz";
    hash = "sha256-Q2ujZBp7PH+wS7RASl1y0uWJFk42NHSLnhBpl9206to=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/gcloud-mcp $out/bin
    cp -r dist package.json $out/lib/gcloud-mcp/
    makeWrapper ${nodejs}/bin/node $out/bin/gcloud-mcp \
      --add-flags "$out/lib/gcloud-mcp/dist/bundle.js"
    runHook postInstall
  '';

  meta = {
    description = "Google Cloud MCP Server - Official MCP server for gcloud CLI by Google";
    homepage = "https://github.com/googleapis/gcloud-mcp";
    license = lib.licenses.asl20;
    mainProgram = "gcloud-mcp";
  };
}
