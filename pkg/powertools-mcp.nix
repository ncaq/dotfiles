# powertools-mcp - AWS Powertools MCP Server
# https://github.com/aws-powertools/powertools-mcp
# AWS公式のPowertools for AWS Lambda用MCPサーバーです。
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "powertools-mcp";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "aws-powertools";
    repo = "powertools-mcp";
    tag = "v${version}";
    hash = "sha256-yUkMtsAS6YWej2k45fAe1a8Te2hGJGEN5xOzJJsBVBc=";
  };

  npmDepsHash = "sha256-BNb5zwwa40zUfKd9kgQFZIdc80/ik3YaV4jw3LQcD6M=";

  npmBuildScript = "build";

  meta = {
    description = "Powertools for AWS Lambda MCP Server - Official MCP server by AWS";
    homepage = "https://github.com/aws-powertools/powertools-mcp";
    license = lib.licenses.mit;
    mainProgram = "powertools-mcp";
  };
}
