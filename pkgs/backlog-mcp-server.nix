# backlog-mcp-server - Backlog MCP Server
# https://github.com/nulab/backlog-mcp-server
# Nulab公式のBacklog用MCPサーバーです。
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "backlog-mcp-server";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "nulab";
    repo = "backlog-mcp-server";
    tag = "v${version}";
    hash = "sha256-2gqqzOQxMvmrCycNakp7g1z+GKKiTA80gug4rOt4gRY=";
  };

  npmDepsHash = "sha256-6tvkPdDrCn5VzCaM66OvQOrdAgD46yNntxls4AQlfkU=";

  npmBuildScript = "build";

  meta = {
    description = "Backlog MCP Server - Official MCP server for Backlog by Nulab";
    homepage = "https://github.com/nulab/backlog-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "backlog-mcp-server";
  };
}
