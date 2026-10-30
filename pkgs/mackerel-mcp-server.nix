# mackerel-mcp-server - Mackerel MCP Server
# https://github.com/mackerelio-labs/mcp-server
# Mackerel公式のMCPサーバーです。
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "mackerel-mcp-server";
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "mackerelio-labs";
    repo = "mcp-server";
    tag = "v${version}";
    hash = "sha256-nkkYQTGp/DvJbYShP0cPFnxz7do5S/SuERD9I0OA5lc=";
  };

  npmDepsHash = "sha256-vzKiFAdcSBEzNkz+glxpls8Am2VIUr4TMsHjopLoJHE=";

  meta = {
    description = "A Model Context Protocol server for interacting with Mackerel";
    homepage = "https://github.com/mackerelio-labs/mcp-server";
    license = lib.licenses.asl20;
    mainProgram = "mcp-server";
  };
}
